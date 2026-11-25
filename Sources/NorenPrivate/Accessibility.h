// Accessibility calls macOS exports from HIServices (in the ApplicationServices umbrella) but does
// not declare.
#ifndef NOREN_ACCESSIBILITY_H
#define NOREN_ACCESSIBILITY_H

#include <ApplicationServices/ApplicationServices.h>

// The window server id (CGWindowID) of the Accessibility window `element`. AeroSpace uses it too.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID* window);

#endif
