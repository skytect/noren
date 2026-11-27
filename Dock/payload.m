// noren's Dock payload: new app windows stay hidden until AeroSpace has put them in place, and no
// app window has a shadow. Only the Dock's connection to the window server may change other apps'
// windows, so this runs inside the Dock, put there by inject.m.
//
// The window server tells every connection that asks of each window it creates: notification
// 1325, whose data is the window's space (a uint64_t) and then the window id, as JankyBorders reads
// it (src/events.c). Each new app window (layer 0) is tagged "no shadow" then; a tag stays with its
// window. A slow look at the windows on screen catches the rest: windows from before the payload
// came, and any whose app reset its tags. A new standalone document window, not a sheet or a
// panel, is also hidden, by setting its
// system alpha to 0: the window server's own factor on top of the alpha the app sets, the way
// yabai's scripting addition hides a window while it animates (do_window_swap_proxy_in in
// src/osax/payload.m). noren is told (NORMessageHeld, DockProtocol.h), and once AeroSpace has
// placed the window noren asks for it back: at once, or faded in over NOR_FADE.
//
// A window never stays hidden: one held for NOR_HOLD_LIMIT is shown regardless, one noren cannot be
// told about is shown at once, and while noren's port is missing (noren not running) no window is
// hidden at all.
//
// noren's Ctrl+drag (Drag.swift) moves windows through here too (NORMessageMove): the window server
// moves the window as it does one dragged by its title bar, in any app, where an app's own
// Accessibility answers lag behind the pointer.
//
// Tiled windows sit under the other windows of their level (NORMessageBelow, Layers.swift), so
// floating ones stay above them: the window's sublevel, as yabai's scripting addition sets a
// window's layer (do_window_layer in src/osax/payload.m). The windows a sunk window owns, its
// sheets and popups, stay at the normal level, as yabai keeps them (window_manager_set_window_layer
// in src/window_manager.c), so they still show over the floating windows.
//
// Needs System Integrity Protection partly off: see docs/dock.md.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

#import "DockProtocol.h"

// The window server's notification of a new window
static const uint32_t kWindowCreated = 1325;
// Window server tags, as JankyBorders names them (src/misc/window.h), and "no shadow"
static const uint64_t kDocumentTag = 1ULL << 0;
static const uint64_t kNoShadowTag = 1ULL << 3;
static const uint64_t kAttachedTag = 1ULL << 7;
static const uint64_t kIgnoresCycleTag = 1ULL << 18;
// How often a fade steps the alpha
static const NSTimeInterval kFadeFrame = 1.0 / 120;
// A window shown from the start is tagged again this much later, in case its app set the window's
// tags only after the window server reported it
static const NSTimeInterval kRetagDelay = 0.5;
// How long the payload waits to hand noren a message
static const NSTimeInterval kSendTimeout = 0.1;
// How often the windows on screen are looked at for ones without the tag
static const int64_t kSweepInterval = 2 * NSEC_PER_SEC;

typedef void (*NotifyProc)(uint32_t, void *, size_t, void *);
typedef int (*SLSMainConnectionIDFunction)(void);
typedef CGError (*SLSRegisterNotifyProcFunction)(NotifyProc, uint32_t, void *);
typedef CGError (*SLSGetWindowOwnerFunction)(int, uint32_t, int *);
typedef CGError (*SLSSetWindowTagsFunction)(int, uint32_t, uint64_t *, int);
typedef CFTypeRef (*SLSWindowQueryWindowsFunction)(int, CFArrayRef, uint32_t);
typedef CFTypeRef (*SLSWindowQueryResultCopyWindowsFunction)(CFTypeRef);
typedef bool (*SLSWindowIteratorAdvanceFunction)(CFTypeRef);
typedef int (*SLSWindowIteratorGetLevelFunction)(CFTypeRef);
typedef uint64_t (*SLSWindowIteratorGetTagsFunction)(CFTypeRef);
typedef uint32_t (*SLSWindowIteratorGetParentIDFunction)(CFTypeRef);
typedef CFTypeRef (*SLSTransactionCreateFunction)(int);
typedef CGError (*SLSTransactionSetWindowSystemAlphaFunction)(CFTypeRef, uint32_t, float);
typedef CGError (*SLSTransactionCommitFunction)(CFTypeRef, int);
typedef CGError (*SLSMoveWindowWithGroupFunction)(int, uint32_t, CGPoint *);
typedef void (*SLSReassociateWindowsSpacesByGeometryFunction)(int, CFArrayRef);
typedef CGError (*SLSSetWindowSubLevelFunction)(int, uint32_t, int);
typedef CFArrayRef (*SLSCopyAssociatedWindowsFunction)(int, uint32_t);
typedef uint32_t (*SLSWindowIteratorGetWindowIDFunction)(CFTypeRef);

static SLSGetWindowOwnerFunction gGetWindowOwner;
static SLSSetWindowTagsFunction gSetWindowTags;
static SLSWindowQueryWindowsFunction gQueryWindows;
static SLSWindowQueryResultCopyWindowsFunction gCopyWindows;
static SLSWindowIteratorAdvanceFunction gAdvance;
static SLSWindowIteratorGetLevelFunction gGetLevel;
static SLSWindowIteratorGetTagsFunction gGetTags;
static SLSWindowIteratorGetParentIDFunction gGetParentID;
static SLSTransactionCreateFunction gTransactionCreate;
static SLSTransactionSetWindowSystemAlphaFunction gSetSystemAlpha;
static SLSTransactionCommitFunction gCommit;
static SLSMoveWindowWithGroupFunction gMoveWindow;
static SLSReassociateWindowsSpacesByGeometryFunction gReassociate;
static SLSSetWindowSubLevelFunction gSetSubLevel;
static SLSCopyAssociatedWindowsFunction gCopyAssociated;
static SLSWindowIteratorGetWindowIDFunction gGetWindowID;

static int gConnection;  // the Dock's
static BOOL gHides;      // NO when noren could not reach the payload: then nothing is hidden
static dispatch_queue_t gQueue;  // the state below, and the messages both ways
// Hidden windows, by window id: when each was hidden
static NSMutableDictionary<NSNumber *, NSDate *> *gHeld;
// Fades under way, by window id
static NSMutableDictionary<NSNumber *, dispatch_source_t> *gFades;
static CFMessagePortRef gPort;

typedef enum {
  kNotAppWindow,  // another layer's window, or the Dock's own
  kAppWindow,     // a sheet, a panel, a child window
  kDocumentWindow,
} WindowKind;

static WindowKind Kind(uint32_t window) {
  int owner = 0;
  if (gGetWindowOwner(gConnection, window, &owner) != kCGErrorSuccess || owner == gConnection) {
    return kNotAppWindow;
  }
  CFTypeRef query = gQueryWindows(gConnection, (__bridge CFArrayRef) @[ @(window) ], 0);
  if (!query) return kNotAppWindow;
  WindowKind kind = kNotAppWindow;
  CFTypeRef iterator = gCopyWindows(query);
  if (iterator && gAdvance(iterator) && gGetLevel(iterator) == 0) {
    uint64_t tags = gGetTags(iterator);
    BOOL standalone = gGetParentID(iterator) == 0 && !(tags & (kAttachedTag | kIgnoresCycleTag));
    kind = standalone && (tags & kDocumentTag) ? kDocumentWindow : kAppWindow;
  }
  if (iterator) CFRelease(iterator);
  CFRelease(query);
  return kind;
}

static void TurnOffShadow(uint32_t window) {
  uint64_t tags = kNoShadowTag;
  gSetWindowTags(gConnection, window, &tags, 64);
}

static void SetSystemAlpha(uint32_t window, float alpha) {
  CFTypeRef transaction = gTransactionCreate(gConnection);
  if (!transaction) return;
  gSetSystemAlpha(transaction, window, alpha);
  gCommit(transaction, 0);
  CFRelease(transaction);
}

// Whether noren's port is there to be told of a hidden window
static BOOL NorenListens(void) {
  CFMessagePortRef port = CFMessagePortCreateRemote(NULL, CFSTR(NOR_APP_PORT));
  if (!port) return NO;
  CFRelease(port);
  return YES;
}

static BOOL TellNoren(NORMessage message, uint32_t window) {
  CFMessagePortRef port = CFMessagePortCreateRemote(NULL, CFSTR(NOR_APP_PORT));
  if (!port) return NO;
  NSData *data = [NSData dataWithBytes:&window length:sizeof window];
  SInt32 status = CFMessagePortSendRequest(port, message, (__bridge CFDataRef)data, kSendTimeout, 0,
                                           NULL, NULL);
  CFRelease(port);
  return status == kCFMessagePortSuccess;
}

// Shows `window` if it is hidden, faded in or at once. Runs on gQueue.
static void Show(uint32_t window, BOOL fade) {
  NSNumber *key = @(window);
  if (!gHeld[key]) return;
  [gHeld removeObjectForKey:key];
  TurnOffShadow(window);
  if (!fade) {
    SetSystemAlpha(window, 1);
    return;
  }
  int steps = MAX(1, (int)round(NOR_FADE / kFadeFrame));
  __block int step = 0;
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
  dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, (uint64_t)(kFadeFrame * NSEC_PER_SEC), 0);
  dispatch_source_set_event_handler(timer, ^{
    step++;
    SetSystemAlpha(window, (float)step / steps);
    if (step < steps) return;
    // Cancelling lets go of this handler, and with it the timer
    dispatch_source_cancel(timer);
    [gFades removeObjectForKey:key];
  });
  gFades[key] = timer;
  dispatch_resume(timer);
}

// Keeps the just hidden `window` hidden until noren asks for it, or NOR_HOLD_LIMIT has passed.
// Runs on gQueue.
static void Hold(uint32_t window) {
  NSNumber *key = @(window);
  dispatch_source_t fade = gFades[key];
  if (fade) {
    dispatch_source_cancel(fade);
    [gFades removeObjectForKey:key];
  }
  NSDate *since = [NSDate date];
  gHeld[key] = since;
  if (!TellNoren(NORMessageHeld, window)) {
    Show(window, NO);
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NOR_HOLD_LIMIT * NSEC_PER_SEC)), gQueue,
                 ^{
                   if (gHeld[key] != since) return;
                   NSLog(@"noren: window %u was not placed in time; showing it", window);
                   Show(window, YES);
                 });
}

// Notification 1325. The window server's notifications come on the Dock's main thread; the
// window is hidden there and then, and the rest is left to gQueue.
static void WindowCreated(uint32_t event, void *data, size_t length, void *context) {
  if (event != kWindowCreated || !data || length < sizeof(uint64_t) + sizeof(uint32_t)) return;
  uint32_t window;
  memcpy(&window, (const uint8_t *)data + sizeof(uint64_t), sizeof window);
  if (!window) return;
  @autoreleasepool {
    WindowKind kind = Kind(window);
    if (kind == kNotAppWindow) return;
    TurnOffShadow(window);
    BOOL hide = gHides && kind == kDocumentWindow && NorenListens();
    if (hide) SetSystemAlpha(window, 0);
    dispatch_async(gQueue, ^{
      if (hide) {
        Hold(window);
        return;
      }
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetagDelay * NSEC_PER_SEC)),
                     gQueue, ^{
                       TurnOffShadow(window);
                     });
    });
  }
}

// Moves `move.window` to `move`'s point, and onto the space of the screen it is now on, as
// yabai's scripting addition does (do_window_move in src/osax/payload.m). Runs on gQueue.
static void Move(NORMove move) {
  CGPoint point = CGPointMake(move.x, move.y);
  gMoveWindow(gConnection, move.window, &point);
  gReassociate(gConnection, (__bridge CFArrayRef) @[ @(move.window) ]);
}

// Puts `window` at the backstop sublevel, under the other windows of its level, or back at the
// normal one; the windows it owns stay at the normal sublevel. Runs on gQueue.
static void SetLayer(uint32_t window, BOOL below) {
  int normal = CGWindowLevelForKey(kCGNormalWindowLevelKey);
  gSetSubLevel(gConnection, window, below ? CGWindowLevelForKey(kCGBackstopMenuLevelKey) : normal);
  CFArrayRef associated = gCopyAssociated(gConnection, window);
  if (!associated) return;
  CFTypeRef query = gQueryWindows(gConnection, associated, (uint32_t)CFArrayGetCount(associated));
  CFRelease(associated);
  if (!query) return;
  // Each window owned by `window` or by one of its own, found as the walk reaches its owner
  NSMutableArray<NSArray<NSNumber *> *> *relations = [NSMutableArray array];
  CFTypeRef iterator = gCopyWindows(query);
  while (iterator && gAdvance(iterator)) {
    [relations addObject:@[ @(gGetParentID(iterator)), @(gGetWindowID(iterator)) ]];
  }
  if (iterator) CFRelease(iterator);
  CFRelease(query);
  NSMutableArray<NSNumber *> *owners = [NSMutableArray arrayWithObject:@(window)];
  for (NSUInteger i = 0; i < owners.count; i++) {
    for (NSArray<NSNumber *> *relation in relations) {
      if (![relation[0] isEqual:owners[i]] || [owners containsObject:relation[1]]) continue;
      gSetSubLevel(gConnection, relation[1].unsignedIntValue, normal);
      [owners addObject:relation[1]];
    }
  }
}

// noren's messages, on gQueue
static CFDataRef Received(CFMessagePortRef port, SInt32 message, CFDataRef data, void *info) {
  if (!data) return NULL;
  if (message == NORMessageMove) {
    if (CFDataGetLength(data) < (CFIndex)sizeof(NORMove)) return NULL;
    NORMove move;
    memcpy(&move, CFDataGetBytePtr(data), sizeof move);
    Move(move);
    return NULL;
  }
  NSData *bytes = (__bridge NSData *)data;
  const uint32_t *windows = bytes.bytes;
  for (NSUInteger i = 0; i < bytes.length / sizeof(uint32_t); i++) {
    switch (message) {
      case NORMessageShow:
      case NORMessageReveal:
        Show(windows[i], message == NORMessageReveal);
        break;
      case NORMessageBelow:
      case NORMessageNormal:
        SetLayer(windows[i], message == NORMessageBelow);
        break;
      default:
        return NULL;
    }
  }
  return NULL;
}

__attribute__((constructor)) static void NORDockPayloadStart(void) {
  void *skyLight =
      dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
  if (!skyLight) {
    NSLog(@"noren: SkyLight not found; windows keep their shadows");
    return;
  }
  SLSMainConnectionIDFunction mainConnection = dlsym(skyLight, "SLSMainConnectionID");
  SLSRegisterNotifyProcFunction registerNotifyProc = dlsym(skyLight, "SLSRegisterNotifyProc");
  gGetWindowOwner = dlsym(skyLight, "SLSGetWindowOwner");
  gSetWindowTags = dlsym(skyLight, "SLSSetWindowTags");
  gQueryWindows = dlsym(skyLight, "SLSWindowQueryWindows");
  gCopyWindows = dlsym(skyLight, "SLSWindowQueryResultCopyWindows");
  gAdvance = dlsym(skyLight, "SLSWindowIteratorAdvance");
  gGetLevel = dlsym(skyLight, "SLSWindowIteratorGetLevel");
  gGetTags = dlsym(skyLight, "SLSWindowIteratorGetTags");
  gGetParentID = dlsym(skyLight, "SLSWindowIteratorGetParentID");
  gTransactionCreate = dlsym(skyLight, "SLSTransactionCreate");
  gSetSystemAlpha = dlsym(skyLight, "SLSTransactionSetWindowSystemAlpha");
  gCommit = dlsym(skyLight, "SLSTransactionCommit");
  gMoveWindow = dlsym(skyLight, "SLSMoveWindowWithGroup");
  gReassociate = dlsym(skyLight, "SLSReassociateWindowsSpacesByGeometry");
  gSetSubLevel = dlsym(skyLight, "SLSSetWindowSubLevel");
  gCopyAssociated = dlsym(skyLight, "SLSCopyAssociatedWindows");
  gGetWindowID = dlsym(skyLight, "SLSWindowIteratorGetWindowID");
  if (!mainConnection || !registerNotifyProc || !gGetWindowOwner || !gSetWindowTags ||
      !gQueryWindows || !gCopyWindows || !gAdvance || !gGetLevel || !gGetTags || !gGetParentID ||
      !gTransactionCreate || !gSetSystemAlpha || !gCommit || !gMoveWindow || !gReassociate ||
      !gSetSubLevel || !gCopyAssociated || !gGetWindowID) {
    NSLog(@"noren: SkyLight calls not found; windows keep their shadows and show as they open");
    return;
  }
  gConnection = mainConnection();
  gQueue = dispatch_queue_create("noren.dock", DISPATCH_QUEUE_SERIAL);
  gHeld = [NSMutableDictionary dictionary];
  gFades = [NSMutableDictionary dictionary];

  gPort = CFMessagePortCreateLocal(NULL, CFSTR(NOR_DOCK_PORT), Received, NULL, NULL);
  if (gPort) {
    CFMessagePortSetDispatchQueue(gPort, gQueue);
    gHides = YES;
  } else {
    NSLog(@"noren: could not open %@; new windows show as they open", @NOR_DOCK_PORT);
  }

  // The windows on screen, now and every kSweepInterval; each is tagged once while it stays
  NSMutableSet<NSNumber *> *tagged = [NSMutableSet set];
  dispatch_source_t sweep = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
  dispatch_source_set_timer(sweep, DISPATCH_TIME_NOW, kSweepInterval, kSweepInterval / 4);
  dispatch_source_set_event_handler(sweep, ^{
    NSArray<NSDictionary *> *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    NSMutableSet<NSNumber *> *onScreen = [NSMutableSet setWithCapacity:windows.count];
    for (NSDictionary *window in windows) {
      if ([window[(id)kCGWindowLayer] intValue] != 0) continue;
      NSNumber *number = window[(id)kCGWindowNumber];
      [onScreen addObject:number];
      if (![tagged containsObject:number]) TurnOffShadow(number.unsignedIntValue);
    }
    [tagged setSet:onScreen];
  });
  dispatch_resume(sweep);
  // The timer lives as long as the Dock
  CFBridgingRetain(sweep);
  // Registered from the main thread, where the Dock takes its window server notifications
  dispatch_async(dispatch_get_main_queue(), ^{
    CGError error = registerNotifyProc(WindowCreated, kWindowCreated, NULL);
    if (error != kCGErrorSuccess) {
      NSLog(@"noren: no window server notifications (error %d); new windows keep shadows", error);
      return;
    }
    NSLog(@"noren: window shadows off%@", gHides ? @", new windows hidden until placed" : @"");
  });
}
