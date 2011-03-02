/* $NoKeywords: $ */
/*
 //
 // Copyright (c) 1993-2011 Robert McNeel & Associates. All rights reserved.
 // Portions Copyright (C) 2009 Apple Inc. All Rights Reserved.
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

#import <QuartzCore/QuartzCore.h>
#import "DisplayMesh.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>


struct RhGLDrawable 
{
  unsigned int vertexBuffer;
  unsigned int indexBuffer;
  int    indexCount;
  int    attrs;
};


@class RhModel;
@class RhModelView;


@protocol ESRenderer <NSObject>

- (void) renderModel: (RhModel*) model inViewport: (ON_Viewport) viewport;
- (void) renderModel: (RhModel*) model inLeftEye: (const ON_Viewport&) leftEye inRightEye: (const ON_Viewport&) rightEye;
- (UIImage*) renderPreview: (RhModel*) model inViewport: (ON_Viewport) viewport;

- (BOOL)resizeFromLayer:(CAEAGLLayer*)layer;
- (void) clearView;

- (BOOL) initGL;

- (void) setMaterial: (const ON_Material&) material;
- (ON_Color) backgroundColor;
- (void) setBackgroundColor: (ON_Color) backgroundColor;
- (void) setDefaultBackgroundColor;

-(UIImage *) capturedImage;
- (void) setNeedsImageCapturedForDelegate: (id) aDelegate;
- (void) drawMesh: (DisplayMesh*) mesh;

@end


