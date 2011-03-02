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

#import "AnaglyphCalculator.h"

@implementation AnaglyphCalculator

@synthesize Separation, Parallax, LeftEye, RightEye;

- (id) init
{
  self = [super init];
  if (self) 
  {
    Separation = 0.35;
    Parallax   = 1.65;
    Asymmetry  = 0.0;
    Offset     = 0.0;
  }
  
  return self;
}

- (void) calcAsymmetricView: (const ON_Viewport&) viewport target: (const ON_3dPoint&) target
{
  double  viewAngle;
  
  viewport.GetCameraAngle( &viewAngle );
  
  ON_3dVector direction    = ::ON_CrossProduct( viewport.CameraDirection(), viewport.CameraUp() );
  double      targetDist   = (viewport.CameraLocation() - target) * viewport.CameraZ();
  double      dX           = targetDist * 2.0 * tan( viewAngle );
  double      cameraOffset = dX * 0.035 * -Separation/2.0;
  double      nearDist     = viewport.FrustumNear() / targetDist;
  
  Offset    = cameraOffset; 
  Asymmetry = cameraOffset * Parallax * nearDist;

  // Left eye...
  double  leftFrustum  = viewport.FrustumLeft()  - Asymmetry;
  double  rightFrustum = viewport.FrustumRight() - Asymmetry;
 
  LeftEye = viewport;
  LeftEye.SetCameraLocation( viewport.CameraLocation() + Offset * direction );
  LeftEye.SetFrustum( leftFrustum, rightFrustum, 
                      viewport.FrustumBottom(), viewport.FrustumTop(),
                      viewport.FrustumNear(), viewport.FrustumFar() );

  // Right eye...
  leftFrustum  = viewport.FrustumLeft()  + Asymmetry;
  rightFrustum = viewport.FrustumRight() + Asymmetry;
  
  RightEye = viewport;
  RightEye.SetCameraLocation( viewport.CameraLocation() - Offset * direction );
  RightEye.SetFrustum( leftFrustum, rightFrustum, 
                       viewport.FrustumBottom(), viewport.FrustumTop(),
                       viewport.FrustumNear(), viewport.FrustumFar() );
}

@end


