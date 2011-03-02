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

#import "ESRenderer.h"

#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>


@class RhModelView;


@interface ES1Renderer : NSObject <ESRenderer>
{
@private
	EAGLContext *mainContext;     // OpenGL context on main thread
	EAGLContext *renderContext;   // OpenGL context on render thread
	
	// The pixel dimensions of the CAEAGLLayer
	GLint backingWidth;
	GLint backingHeight;
	
	// The OpenGL names for the framebuffer, depthBuffer, and renderbuffer used to render to this view
	GLuint defaultFramebuffer, colorRenderbuffer, depthRenderbuffer;
  
  RhGLDrawable* gradientquad;

  id needsImageCapturedDelegate;
  UIImage* capturedImage;
  
  BOOL canAntialias;
  
  ON_Color backgroundColor;

  // OpenGL names for the double-sized texture buffer
  GLuint textureFramebuffer, texture, textureDepthbuffer;
  
	// The pixel dimensions of the texture
	GLint textureWidth;
	GLint textureHeight;
  
  NSThread* renderThread;
  
  // coordinate render requests
  BOOL performingRender;
  int  stereoConfig;
  ON_Viewport renderViewport1;
  ON_Viewport renderViewport2;
  RhModel* renderModel;
}

- (void) renderModel: (RhModel*) model inViewport: (ON_Viewport) viewport;
- (void) renderModel: (RhModel*) model inLeftEye: (const ON_Viewport&) leftEye inRightEye: (const ON_Viewport&) rightEye;
- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer;
- (void) clearView;

- (BOOL) initGL;

- (void) setMaterial: (const ON_Material&) material;
- (void) drawMesh: (DisplayMesh*) mesh;

@end
