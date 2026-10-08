#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

// Reverse-engineered layout of MultitouchSupport.framework (private API).
// Only types are declared here; symbols are resolved at runtime via dlsym.

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7,
} MTTouchState;

typedef struct {
    int frame;
    double timestamp;
    int pathIndex;          // finger identifier, stable for the lifetime of a contact
    int state;              // MTTouchState
    int fingerID;
    int handID;
    MTVector normalized;    // position/velocity in 0...1 trackpad coordinates
    float zTotal;
    int field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;      // position/velocity in millimetres
    int field14;
    int field15;
    float zDensity;
} MTTouch;                  // 96 bytes

typedef void *MTDeviceRef;

typedef int (*MTContactCallbackFunction)(MTDeviceRef device,
                                         const MTTouch *touches,
                                         int numTouches,
                                         double timestamp,
                                         int frame);

#endif
