// noren's Dock loader: puts dock/payload.m into the Dock, and again whenever the Dock restarts.
// Runs as root (docs/dock.md). It starts a thread in the Dock that dlopens the payload, then waits
// for that Dock to exit.
//
// Needs System Integrity Protection's debugging restrictions off (task_for_pid on the Dock); see
// docs/dock.md. Apple Silicon only: the Dock is arm64e.
//
// Usage: inject PAYLOAD
//
// The injection (shell_code and main's thread setup) is adapted from yabai's src/osax/loader.m,
// whose arm64e path credits Jeremy Legendre (https://github.com/jslegendre). yabai's licence:
//
//   The MIT License (MIT)
//
//   Copyright (c) 2019 Åsmund Vikane
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software
//   and associated documentation files (the "Software"), to deal in the Software without
//   restriction, including without limitation the rights to use, copy, modify, merge, publish,
//   distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom
//   the Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all copies or
//   substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//   INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
//   PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
//   FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//   OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <ptrauth.h>
#include <sys/event.h>

static const char *const kDockPath = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock";
// A Dock younger than this may still be launching; its payload thread would race its setup
static const NSTimeInterval kDockSettle = 2;
// Where in shell_code the two function addresses and the payload path go
static const size_t kCreateThreadOffset = 88;
static const size_t kDlopenOffset = 160;
static const size_t kPathOffset = 168;
// What the payload thread leaves in x0 once it has called dlopen
static const uint64_t kDoneMarker = 0x79616265;

// Starts a pthread (the second routine below) that dlopens the path at kPathOffset, marks x0 with
// kDoneMarker and spins until it is terminated
static char shell_code[] =
    "\xFF\xC3\x00\xD1"                  // sub        sp, sp, #0x30
    "\xFD\x7B\x02\xA9"                  // stp        x29, x30, [sp, #0x20]
    "\xFD\x83\x00\x91"                  // add        x29, sp, #0x20
    "\xA0\xC3\x1F\xB8"                  // stur       w0, [x29, #-0x4]
    "\xE1\x0B\x00\xF9"                  // str        x1, [sp, #0x10]
    "\xE0\x23\x00\x91"                  // add        x0, sp, #0x8
    "\x08\x00\x80\xD2"                  // mov        x8, #0
    "\xE8\x07\x00\xF9"                  // str        x8, [sp, #0x8]
    "\xE1\x03\x08\xAA"                  // mov        x1, x8
    "\xE2\x01\x00\x10"                  // adr        x2, #0x3C
    "\xE2\x23\xC1\xDA"                  // paciza     x2
    "\xE3\x03\x08\xAA"                  // mov        x3, x8
    "\x49\x01\x00\x10"                  // adr        x9, #0x28 ; pthread_create_from_mach_thread
    "\x29\x01\x40\xF9"                  // ldr        x9, [x9]
    "\x20\x01\x3F\xD6"                  // blr        x9
    "\xA0\x4C\x8C\xD2"                  // movz       x0, #0x6265
    "\x20\x2C\xAF\xF2"                  // movk       x0, #0x7961, lsl #16
    "\x09\x00\x00\x10"                  // adr        x9, #0
    "\x20\x01\x1F\xD6"                  // br         x9
    "\xFD\x7B\x42\xA9"                  // ldp        x29, x30, [sp, #0x20]
    "\xFF\xC3\x00\x91"                  // add        sp, sp, #0x30
    "\xC0\x03\x5F\xD6"                  // ret
    "\x00\x00\x00\x00\x00\x00\x00\x00"  //
    "\x7F\x23\x03\xD5"                  // pacibsp
    "\xFF\xC3\x00\xD1"                  // sub        sp, sp, #0x30
    "\xFD\x7B\x02\xA9"                  // stp        x29, x30, [sp, #0x20]
    "\xFD\x83\x00\x91"                  // add        x29, sp, #0x20
    "\xA0\xC3\x1F\xB8"                  // stur       w0, [x29, #-0x4]
    "\xE1\x0B\x00\xF9"                  // str        x1, [sp, #0x10]
    "\x21\x00\x80\xD2"                  // mov        x1, #1
    "\x60\x01\x00\x10"                  // adr        x0, #0x2c ; payload_path
    "\x09\x01\x00\x10"                  // adr        x9, #0x20 ; dlopen
    "\x29\x01\x40\xF9"                  // ldr        x9, [x9]
    "\x20\x01\x3F\xD6"                  // blr        x9
    "\x09\x00\x80\x52"                  // mov        w9, #0
    "\xE0\x03\x09\xAA"                  // mov        x0, x9
    "\xFD\x7B\x42\xA9"                  // ldp        x29, x30, [sp, #0x20]
    "\xFF\xC3\x00\x91"                  // add        sp, sp, #0x30
    "\xFF\x0F\x5F\xD6"                  // retab
    "\x00\x00\x00\x00\x00\x00\x00\x00"  //
    "\x00\x00\x00\x00\x00\x00\x00\x00"  // empty space for payload_path
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00";

typedef kern_return_t (*ThreadConvertThreadStateFunction)(thread_act_t, int, thread_state_flavor_t,
                                                          thread_state_t, mach_msg_type_number_t,
                                                          thread_state_t, mach_msg_type_number_t *);

// The pid of the Dock, or 0 if none is running
static pid_t DockPid(void) {
  int count = proc_listallpids(NULL, 0);
  if (count <= 0) return 0;
  NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(pid_t)];
  pid_t *pids = buffer.mutableBytes;
  count = proc_listallpids(pids, (int)buffer.length);
  char path[PROC_PIDPATHINFO_MAXSIZE];
  for (int i = 0; i < count; i++) {
    if (proc_pidpath(pids[i], path, sizeof path) > 0 && strcmp(path, kDockPath) == 0) {
      return pids[i];
    }
  }
  return 0;
}

// Seconds since the process started, or 0 if it cannot be told
static NSTimeInterval Age(pid_t pid) {
  struct proc_bsdinfo info;
  if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) != sizeof info) return 0;
  NSDate *started =
      [NSDate dateWithTimeIntervalSince1970:info.pbi_start_tvsec + info.pbi_start_tvusec / 1e6];
  return -started.timeIntervalSinceNow;
}

// Runs the payload in the Dock `pid`; NO, with the reason on stderr, if that failed
static BOOL Inject(pid_t pid, const char *payload) {
  if (strlen(payload) >= sizeof(shell_code) - kPathOffset) {
    fprintf(stderr, "payload path too long: %s\n", payload);
    return NO;
  }
  mach_port_t task;
  kern_return_t error = task_for_pid(mach_task_self(), pid, &task);
  if (error != KERN_SUCCESS) {
    fprintf(stderr, "task_for_pid(%d): %s (SIP debugging restrictions still on?)\n", pid,
            mach_error_string(error));
    return NO;
  }
  mach_vm_address_t stack = 0, code = 0;
  vm_size_t stackSize = 16 * 1024;
  uint64_t stackContents = 0x00000000CAFEBABE;
  if (mach_vm_allocate(task, &stack, stackSize, VM_FLAGS_ANYWHERE) != KERN_SUCCESS ||
      mach_vm_write(task, stack, (vm_address_t)&stackContents, sizeof stackContents) !=
          KERN_SUCCESS ||
      vm_protect(task, stack, stackSize, 1, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS ||
      mach_vm_allocate(task, &code, sizeof shell_code, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
    fprintf(stderr, "could not set up memory in the Dock\n");
    return NO;
  }
  uint64_t createThread = (uint64_t)ptrauth_strip(
      dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
  uint64_t dlopenAddress =
      (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);
  memcpy(shell_code + kCreateThreadOffset, &createThread, sizeof createThread);
  memcpy(shell_code + kDlopenOffset, &dlopenAddress, sizeof dlopenAddress);
  memcpy(shell_code + kPathOffset, payload, strlen(payload) + 1);
  if (mach_vm_write(task, code, (vm_address_t)shell_code, sizeof shell_code) != KERN_SUCCESS ||
      vm_protect(task, code, sizeof shell_code, 0, VM_PROT_EXECUTE | VM_PROT_READ) !=
          KERN_SUCCESS) {
    fprintf(stderr, "could not write the shell code into the Dock\n");
    return NO;
  }

  void *kernel = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
  ThreadConvertThreadStateFunction convert =
      kernel ? dlsym(kernel, "thread_convert_thread_state") : NULL;
  if (!convert) {
    fprintf(stderr, "thread_convert_thread_state not found\n");
    return NO;
  }
  arm_thread_state64_t state = {}, machineState = {};
  mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
  mach_msg_type_number_t machineCount = ARM_THREAD_STATE64_COUNT;
  __darwin_arm_thread_state64_set_pc_fptr(
      state, ptrauth_sign_unauthenticated((void *)code, ptrauth_key_asia, 0));
  __darwin_arm_thread_state64_set_sp(state, stack + stackSize / 2);
  thread_act_t thread;
  if (thread_create(task, &thread) != KERN_SUCCESS) {
    fprintf(stderr, "could not create a thread in the Dock\n");
    return NO;
  }
  error = convert(thread, 2, ARM_THREAD_STATE64, (thread_state_t)&state, count,
                  (thread_state_t)&machineState, &machineCount);
  thread_terminate(thread);
  if (error != KERN_SUCCESS) {
    fprintf(stderr, "could not convert the thread state: %s\n", mach_error_string(error));
    return NO;
  }
  error = thread_create_running(task, ARM_THREAD_STATE64, (thread_state_t)&machineState,
                                machineCount, &thread);
  if (error != KERN_SUCCESS) {
    fprintf(stderr, "could not start a thread in the Dock: %s\n", mach_error_string(error));
    return NO;
  }

  // The thread marks x0 once dlopen has returned; it then spins, so end it
  BOOL done = NO;
  for (int i = 0; i < 10 && !done; i++) {
    usleep(20000);
    if (thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count) !=
        KERN_SUCCESS) {
      break;
    }
    done = state.__x[0] == kDoneMarker;
  }
  thread_terminate(thread);
  if (!done) fprintf(stderr, "the payload thread did not finish\n");
  return done;
}

// Blocks until the process exits; returns at once if it already has
static void WaitForExit(pid_t pid) {
  int queue = kqueue();
  struct kevent change, event;
  EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
  kevent(queue, &change, 1, &event, 1, NULL);
  close(queue);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) {
      fprintf(stderr, "usage: inject PAYLOAD\n");
      return 2;
    }
    for (;;) {
      pid_t dock = DockPid();
      if (!dock || Age(dock) < kDockSettle) {
        sleep(1);
        continue;
      }
      if (Inject(dock, argv[1])) {
        printf("payload in the Dock (pid %d)\n", dock);
      } else {
        printf("could not put the payload in the Dock (pid %d); waiting for the next one\n", dock);
      }
      fflush(stdout);
      WaitForExit(dock);
    }
  }
}
