/* $NoKeywords: $ */
/*
 //
 // Copyright (c) 1993-2011 Robert McNeel & Associates. All rights reserved.
 // Rhinoceros is a registered trademark of Robert McNeel & Assoicates.
 //
 // THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT EXPRESS OR IMPLIED WARRANTY.
 // ALL IMPLIED WARRANTIES OF FITNESS FOR ANY PARTICULAR PURPOSE AND OF
 // MERCHANTABILITY ARE HEREBY DISCLAIMED.
 //				
 // For complete openNURBS copyright information see <http://www.opennurbs.org>.
 //
 ////////////////////////////////////////////////////////////////
 */

#import <CoreLocation/CoreLocation.h>

#import "ONModel.h"
#include "EAGLView.h"
#include "AppDelegate.h"

#import "AnaglyphCalculator.h"

class ON_Viewport;
class ON_3dVector;
class ON_Xform;
@class PrefTimer;
@class RhModel;



@interface RhModelView : EAGLView <CLLocationManagerDelegate, UIAccelerometerDelegate>
{
  ON_3dmView m_view;
	EX_ONX_Model* m_model;
  RhModel* rhinoModel;

  ON_BoundingBox m_bbox;
  
	float worldRotation [4];
	float objectRotation [4];

  CGPoint gDollyPanStartPoint;
  CGPoint gDollyRotateStartPoint;
  CGPoint oneTouchStartPoint;

  ON_3dVector rotateXAxis;
  ON_3dVector rotateYAxis;
	ON_3dPoint rotateCenter;
  float rotateHorzAngle;
  float rotateVertAngle;
  
  float twoTouchDistance;
  float twoTouchAngle;
  CGPoint twoTouchStartPoint;
  
  float magnifyTouchDistance;
  CGPoint magnifyStartPoint;
  
  bool moreThanTwoTouches;
  
  // determining a double tap
  int doubleTapState;
  NSTimeInterval doubleTapTimestamp;
  CGPoint doubleTapLocation;
  
  // restore view animation variables
  bool atInitialPosition;
  bool returnToInitialPosition;
  bool startRestoreAtInitialPosition;
  bool inAnimatedRestoreView;
  ON_Viewport initialPosition;
  ON_Viewport lastPosition;
  ON_Viewport restoreViewStartViewport;
  ON_Viewport restoreViewFinishViewport;
  uint64_t restoreViewStartTime;
  double restoreViewTotalTime;

  bool gRotate;
  bool gTwoTouch;
  
  CGRect lastBounds;
  
  // 3D stereo anaglyph variables
  BOOL stereoMode;
  AnaglyphCalculator*  anaglyph;

  BOOL pickMode;
  unsigned int pickColor;
  CGPoint pickStartLocation;
  NSTimer* pickTimer;

  UIDeviceOrientation orientation;
  UIAccelerationValue accelerationX;
  UIAccelerationValue accelerationY;
  UIAccelerationValue accelerationZ;
  double pitchAngle;
  double rollAngle;
  
  id delegate;
}

@property (nonatomic, assign) IBOutlet id delegate;

@property (nonatomic, assign) BOOL stereoMode;
@property (nonatomic, retain) AnaglyphCalculator*  anaglyph;

@property (nonatomic, retain) NSTimer* pickTimer;


- (RhModel*) model;
- (void) setModel: (RhModel*) aModel;
- (void) prepareForDisplay: (RhModel*) aModel;

- (void) rotateView: (ON_Viewport&) viewport
					axis: (const ON_3dVector&) axis
					center: (const ON_3dPoint&) center
					angle: (double) angle;
- (void) rotateLeftRight: (ON_Viewport&) viewport angle: (double) angle;
- (void) rotateUpDown: (ON_Viewport&) viewport angle: (double) angle;

- (void) zoomExtents;
- (void) zoomHome;

- (UIImage*) imageFromView;
- (UIImage*) previewImage;

- (void) viewDidAppear;
- (void) viewWillDisappear;

- (void) clearView;

- (void) setNeedsImageCapturedForDelegate: (id) delegate;


@end
