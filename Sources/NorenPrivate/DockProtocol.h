// What the noren app and its Dock payload (Dock/payload.m) say to each other about windows, over
// two CFMessagePorts in the user's session. A message's data is an array of uint32_t window server
// ids (CGWindowID), but NORMessageMove's: one NORMove. Neither side waits for a reply.
#ifndef NOREN_DOCK_PROTOCOL_H
#define NOREN_DOCK_PROTOCOL_H

#include <CoreFoundation/CoreFoundation.h>

// The payload's port, in the Dock: noren's messages to the payload arrive here
#define NOR_DOCK_PORT "local.noren.dock"
// noren's port: the payload's NORMessageHeld arrives here. The payload hides no window while it is
// gone.
#define NOR_APP_PORT "local.noren.app"

typedef CF_ENUM(SInt32, NORMessage) {
  NORMessageHeld = 1,  // payload to noren: these new windows are hidden until noren says otherwise
  NORMessageShow = 2,  // noren to payload: show these at once, if hidden
  NORMessageReveal = 3,  // noren to payload: fade these in over NOR_FADE, if hidden
  NORMessageMove = 4,    // noren to payload: move a window (Ctrl+drag)
  NORMessageBelow = 5,   // noren to payload: put these under the other windows
  NORMessageNormal = 6,  // noren to payload: bring these back among the others
};

// A window to move, and where its top-left corner goes, in the window server's global coordinates
// (the main screen's top-left corner at 0, y down)
typedef struct {
  uint32_t window;
  double x;
  double y;
} NORMove;

// How long the payload keeps a window hidden at most, in seconds: it shows the window itself after
// this
#define NOR_HOLD_LIMIT 1.0
// How long a reveal's fade takes, in seconds
#define NOR_FADE 0.15

#endif
