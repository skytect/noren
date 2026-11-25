// What the noren app and its Dock payload (payload.m) say to each other about new windows,
// over two CFMessagePorts in the user's session. Every message's data is an array of uint32_t
// window server ids (CGWindowID). Neither side waits for a reply.
#import <Foundation/Foundation.h>

// The payload's port, in the Dock: noren's kNORShow and kNORReveal arrive here
static NSString *const kNORDockPort = @"local.noren.dock";
// noren's port: the payload's kNORHeld arrives here. The payload hides no window while it is gone.
static NSString *const kNORAppPort = @"local.noren.app";

typedef NS_ENUM(SInt32, NORMessage) {
  kNORHeld = 1,    // payload to noren: these new windows are hidden until noren says otherwise
  kNORShow = 2,    // noren to payload: show these at once, if hidden
  kNORReveal = 3,  // noren to payload: fade these in over kNORFade, if hidden
};

// How long the payload keeps a window hidden at most: it shows the window itself after this
static const NSTimeInterval kNORHoldLimit = 1;
// How long a reveal's fade takes
static const NSTimeInterval kNORFade = 0.15;
