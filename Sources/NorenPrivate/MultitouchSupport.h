// MultitouchSupport, the private framework that hands out raw trackpad frames, as reverse
// engineered. The SDK has no headers for it, and its stubs cannot be linked from a Swift package,
// so noren looks the functions up at run time (dlsym) by the names below; each function's type is
// declared here, named after it with "Function" appended.
#ifndef NOREN_MULTITOUCH_SUPPORT_H
#define NOREN_MULTITOUCH_SUPPORT_H

#include <CoreFoundation/CoreFoundation.h>

#define NOR_MULTITOUCH_SUPPORT_PATH \
  "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

typedef struct {
  float x, y;
} MTPoint;

typedef struct {
  MTPoint position, velocity;
} MTReadout;

// One finger in a frame
typedef struct {
  int frame;
  double timestamp;
  int identifier;
  int state;  // 1 start, 2 hover, 3 make, 4 touching, 5 break, 6 linger, 7 leave
  int unknown1, unknown2;
  MTReadout normalized;  // 0 to 1 across and up the trackpad
  float size;
  int zero1;
  float angle, majorAxis, minorAxis;
  MTReadout millimeters;
  int zero2[2];
  float unknown3;
} MTTouch;

typedef void* MTDeviceRef;

// Called on MultitouchSupport's own thread with each frame's `count` touches
typedef int (*MTContactCallback)(MTDeviceRef device, MTTouch* touches, int count, double timestamp,
                                 int frame);

// Every multitouch device present now (Create rule)
typedef CFMutableArrayRef (*MTDeviceCreateListFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef device,
                                                       MTContactCallback callback);
typedef void (*MTUnregisterContactFrameCallbackFunction)(MTDeviceRef device,
                                                         MTContactCallback callback);
typedef void (*MTDeviceStartFunction)(MTDeviceRef device, int mode);
typedef void (*MTDeviceStopFunction)(MTDeviceRef device);

#endif
