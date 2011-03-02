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

@interface AnaglyphCalculator : NSObject
{
  ON_Viewport   LeftEye;
  ON_Viewport   RightEye;
  
  double  Separation;
  double  Parallax;
    
  @private double Asymmetry;
  @private double Offset;
}

@property (readwrite, nonatomic, assign) double Separation;
@property (readwrite, nonatomic, assign) double Parallax;
@property (readonly, nonatomic, assign) ON_Viewport& LeftEye;
@property (readonly, nonatomic, assign) ON_Viewport& RightEye;

- (void) calcAsymmetricView: (const ON_Viewport&) viewport target : (const ON_3dPoint&) target;
@end

