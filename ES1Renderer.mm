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
#import "ES1Renderer.h"
#import "RhModel.h"
#import "RhModelView.h"
#import "DisplayMesh.h"
#import "UIColor-RGBA.h"


#if defined (_DEBUG)
#define CheckGLError(xxx)  do { GLenum err = glGetError(); if (err) DLog (@"err: %x", err); } while (0)
#else
#define CheckGLError(xxx)  
#endif



// forward declarations
@interface ES1Renderer ()
- (void) setGLModelViewMatrix: (const ON_Viewport&) viewport;
- (void) setGLProjectionMatrix: (ON_Viewport&) viewport inWidth: (int) width inHeight: (int) height;
@end


@implementation ES1Renderer

enum 
{
  AGM_RED_CYAN,
  AGM_AMBER_BLUE,
  AGM_MAGENTA_GREEN,
};

// round to the next power of two
- (unsigned int) power2: (unsigned int) v
{
  v--;
  v |= v >> 1;
  v |= v >> 2;
  v |= v >> 4;
  v |= v >> 8;
  v |= v >> 16;
  v++;
  return v;
}


// Create an ES 1.1 context
- (id <ESRenderer>) init
{
	if (self = [super init])
	{
		mainContext = [[EAGLContext alloc] initWithAPI: kEAGLRenderingAPIOpenGLES1];
    if (!mainContext || ![EAGLContext setCurrentContext: mainContext])
		{
      [self release];
      return nil;
    }
    
    [self setDefaultBackgroundColor];

    defaultFramebuffer = 0;
    depthRenderbuffer  = 0;
    texture            = 0;
    textureFramebuffer = 0;
    textureDepthbuffer = 0;
    
    backingWidth  = 0;
    backingHeight = 0;
    textureWidth  = 0;
    textureHeight = 0;
    
    canAntialias = NO;
    
    stereoConfig = AGM_RED_CYAN;
    
    // Create our primary render buffer here to give the default layer
    // something to chew on... All other buffers will get created and/or
    // sized in "resizeFromLayer"...
    glGenRenderbuffersOES( 1, &colorRenderbuffer );
    glBindRenderbufferOES( GL_RENDERBUFFER_OES, colorRenderbuffer );
    
    [self initGL];
  }
  return self;
}

////////////////////////////////////////////////////////////////////
- (GLuint) createFboTexture: (GLint) width  inHeight: (GLint) height
{
  GLuint fbt;
  
  glGenTextures( 1, &fbt );
  glBindTexture( GL_TEXTURE_2D, fbt );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
  glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
  glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0 );
  
  return fbt;
}


////////////////////////////////////////////////////////////////////
- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer
{
  BOOL rc = YES;
  @synchronized(self)
  {
    if (!mainContext || ![EAGLContext setCurrentContext: mainContext])
      DLog (@"could not set mainContext");
    
    GLint  oldBackingWidth  = backingWidth;
    GLint  oldBackingHeight = backingHeight;
    
    // Lazy evaluation of the primary FBO...
    if ( defaultFramebuffer == 0 )
    {
      glGenFramebuffersOES( 1, &defaultFramebuffer );
      glGenRenderbuffersOES( 1, &depthRenderbuffer );
    }
    
    // Make sure our primary render buffer is bound and then query for
    // the physical dimensions...
    glBindRenderbufferOES( GL_RENDERBUFFER_OES, colorRenderbuffer );
    [mainContext renderbufferStorage: GL_RENDERBUFFER_OES fromDrawable: layer];
    glGetRenderbufferParameterivOES( GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth );
    glGetRenderbufferParameterivOES( GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight );
    
    // Determine if our frame buffer(s) need to be resized. If the current width or height
    // is different than our previous width/height, then we need to make sure our buffers
    // reflect the new sizes...
    if ( (backingWidth != oldBackingWidth) || (backingHeight != oldBackingHeight) )
    {
      // Allocate color buffer backing based on the current layer size
      glBindFramebufferOES( GL_FRAMEBUFFER_OES, defaultFramebuffer );
      glFramebufferRenderbufferOES( GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorRenderbuffer );
      glBindRenderbufferOES( GL_RENDERBUFFER_OES, depthRenderbuffer );
      glRenderbufferStorageOES( GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight );
      glFramebufferRenderbufferOES( GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer );
      
      // Validate the primary FBO...
      if ( glCheckFramebufferStatusOES( GL_FRAMEBUFFER_OES ) != GL_FRAMEBUFFER_COMPLETE_OES )
      {
        DLog( @"Failed to make complete framebuffer object %x", glCheckFramebufferStatusOES( GL_FRAMEBUFFER_OES ) );
        rc = NO;
      }
      
      int   maxSize = ((backingWidth > backingHeight) ? backingWidth : backingHeight) * 2;
      GLint maxTexSize;
      
      glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexSize);
      canAntialias = maxSize <= maxTexSize;
    }
    
    if ( canAntialias )
    {
      GLint  oldWidth  = textureWidth;
      GLint  oldHeight = textureHeight;
      
      // set the texture size to twice that of our render buffer's size...
      textureWidth  = backingWidth  * 2;
      textureHeight = backingHeight * 2;
      
      // Lazy evaluation of the texture's FBO...since we really don't know 
      // we can anti-alias or what the oversampling sizes are until we reach 
      // this point...
      if ( textureFramebuffer == 0 )
      {
        glGenFramebuffersOES( 1, &textureFramebuffer );
        glGenRenderbuffersOES( 1, &textureDepthbuffer );
        texture = [self createFboTexture: textureWidth  inHeight: textureHeight];
      }
      
      // Check to see if the texture buffers need to be resized...
      if ( (textureWidth != oldWidth) || (textureHeight != oldHeight) )
      {
        GLint cropRect[4] = {0, 0, textureWidth, textureHeight}; 
        
        // Some 1.1 devices do not support NPOT textures...thus, we'll
        // always make sure the sized dimensions fit within a power of 2...
        GLint w = [self power2: textureWidth];
        GLint h = [self power2: textureHeight];
        
        glBindFramebufferOES( GL_FRAMEBUFFER_OES, textureFramebuffer );
        glBindRenderbufferOES( GL_RENDERBUFFER_OES, textureDepthbuffer );
        glRenderbufferStorageOES( GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, w, h );
        glFramebufferRenderbufferOES( GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, textureDepthbuffer );
        glBindTexture( GL_TEXTURE_2D, texture );
        glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA,  w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL );
        glTexParameteriv( GL_TEXTURE_2D, GL_TEXTURE_CROP_RECT_OES, cropRect );
        glFramebufferTexture2DOES( GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_TEXTURE_2D, texture, 0 );
        
        // Validate the texture FBO. Note: This is framebuffer "bound" dependent...meaning,
        // this check validates against the currently bound framebuffer only.
        if ( glCheckFramebufferStatusOES( GL_FRAMEBUFFER_OES ) != GL_FRAMEBUFFER_COMPLETE_OES ) 
        {
          DLog( @"failed to make complete texture buffer object %x", glCheckFramebufferStatusOES( GL_FRAMEBUFFER_OES ) );
          rc = NO;
        }
      }
    }
    
    // Always make sure our primary framebuffer is in use...
    glBindFramebufferOES( GL_FRAMEBUFFER_OES, defaultFramebuffer );
  }
  return rc;
}

////////////////////////////////////////////////////////////////////
- (NSThread*) renderThread
{
  if (renderThread == nil) {
    renderThread = [[NSThread alloc] initWithTarget: self selector: @selector(renderFrames) object: nil];
    [renderThread start];
  }
  return renderThread;
}

- (void) dealloc
{
  [capturedImage release];
  capturedImage = nil;
  
	// Tear down GL
	if (defaultFramebuffer)
	{
		glDeleteFramebuffersOES(1, &defaultFramebuffer);
		defaultFramebuffer = 0;
	}
	
	if (colorRenderbuffer)
	{
		glDeleteRenderbuffersOES(1, &colorRenderbuffer);
		colorRenderbuffer = 0;
	}
	
	if (depthRenderbuffer)
	{
		glDeleteRenderbuffersOES(1, &depthRenderbuffer);
		depthRenderbuffer = 0;
	}
	
	if (textureFramebuffer)
	{
		glDeleteFramebuffersOES(1, &textureFramebuffer);
		textureFramebuffer = 0;
	}
	
	if (texture)
	{
		glDeleteRenderbuffersOES(1, &texture);
		texture = 0;
	}
	
	if (textureDepthbuffer)
	{
		glDeleteRenderbuffersOES(1, &textureDepthbuffer);
		textureDepthbuffer = 0;
	}
  
  if (gradientquad)
  {
    if (gradientquad->vertexBuffer)
      glDeleteBuffers (1, &gradientquad->vertexBuffer);
    if (gradientquad->indexBuffer)
      glDeleteBuffers (1, &gradientquad->indexBuffer);
    delete gradientquad;
    gradientquad = NULL;
  }
  
	// Tear down context
	if ([EAGLContext currentContext] == mainContext)
    [EAGLContext setCurrentContext: nil];
	[mainContext release];
	mainContext = nil;
	
	if ([EAGLContext currentContext] == renderContext)
    [EAGLContext setCurrentContext: nil];
	[renderContext release];
	renderContext = nil;
	
	[super dealloc];
}


#pragma mark ---- OpenGL ES helper functions ----

void glLoadMatrixd (double* d)
{
  float f[16];
  for (int i=0; i<16; i++)
    f[i] = d[i];
  glLoadMatrixf( f );
}


#pragma mark ---- Accessors ----


- (ON_Color) backgroundColor
{
  return backgroundColor;
}

- (void) setBackgroundColor: (ON_Color) onColor
{
  backgroundColor = onColor;
}

- (void) setDefaultBackgroundColor
{
  backgroundColor = RhinoApp.backgroundColor;
}


#pragma mark ---- Utilities ----

/////////////////////////////////////////////////////////////////////
- (void) renderDrawable: (const RhGLDrawable*) drawable
{
  int stride = sizeof(float)*3;
  
  // Are there any normals?...
  if (drawable->attrs & 1)
    stride += sizeof(float)*3;
  
  // Are there any texture coordinates?...
  if (drawable->attrs & 2)
    stride += sizeof(float)*2;
  
  // Are there any colors?...
  if (drawable->attrs & 4)
    stride += sizeof(float)*4;      // N.B.  must be 4
  
  GLvoid* offset = (GLvoid*)(sizeof(float)*3);
  
  glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, drawable->indexBuffer);

  glBindBuffer( GL_ARRAY_BUFFER, drawable->vertexBuffer );
  
  glEnableClientState (GL_VERTEX_ARRAY);
  glVertexPointer(3, GL_FLOAT, stride, 0);

  // Any normals?
  if ( drawable->attrs & 1 ) 
  {
    glEnableClientState (GL_NORMAL_ARRAY);
    glNormalPointer(GL_FLOAT, stride, offset);
    offset = (GLvoid*)((int)offset + sizeof(float)*3);
  }
  
  // Any texture coordinates?
  if (drawable->attrs & 2) 
  {
    glEnableClientState (GL_TEXTURE_COORD_ARRAY);
    glTexCoordPointer(2, GL_FLOAT, stride, offset);
    offset = (GLvoid*)((int)offset + sizeof(float)*2);
  }

  // Any colors?
  if (drawable->attrs & 4) 
  {
    glEnableClientState (GL_COLOR_ARRAY);
    glColorPointer (4, GL_FLOAT, stride, offset);
  }
  
  glDrawElements(GL_TRIANGLES, drawable->indexCount, GL_UNSIGNED_SHORT, 0);
  CheckGLError();
  
  glDisableClientState (GL_VERTEX_ARRAY);
  glDisableClientState (GL_NORMAL_ARRAY);
  glDisableClientState (GL_TEXTURE_COORD_ARRAY);
  glDisableClientState (GL_COLOR_ARRAY);
}


/////////////////////////////////////////////////////////////////////
- (RhGLDrawable*) createGradQuad
{
  UIColor* topColor = RhinoApp.backgroundTopColor;
  UIColor* bottomColor = RhinoApp.backgroundBottomColor;
  float vertices[28] = {
    -1,-1,1,
    [bottomColor red], [bottomColor green], [bottomColor blue], [bottomColor alpha],
    1,-1,1,
    [bottomColor red], [bottomColor green], [bottomColor blue], [bottomColor alpha],
    1,1,1,
    [topColor red], [topColor green], [topColor blue], [topColor alpha],
    -1,1,1,
    [topColor red], [topColor green], [topColor blue], [topColor alpha],
  };
  static short indexes[6]   = { 0,1,3, 1,2,3 };

  GLuint vertexBuffer;
  
  glGenBuffers(1, &vertexBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData( GL_ARRAY_BUFFER,
               28 * sizeof(float),
               vertices,
               GL_STATIC_DRAW );
  
  int indexCount = 6;
  GLuint indexBuffer;
  
  glGenBuffers(1, &indexBuffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
  glBufferData( GL_ELEMENT_ARRAY_BUFFER,
               indexCount * sizeof(GLushort),
               indexes,
               GL_STATIC_DRAW);
  
  RhGLDrawable*  qd = new RhGLDrawable;
  
  qd->vertexBuffer = vertexBuffer;
  qd->indexBuffer  = indexBuffer;
  qd->indexCount   = indexCount;
  qd->attrs        = 4;
  
  return qd;
}


// draw gradient background
- (void) drawBackground
{
#if OLD_WAY
  glClearColor( (float)backgroundColor.FractionRed(), 
               (float)backgroundColor.FractionGreen(), 
               (float)backgroundColor.FractionBlue(), 
               (float)backgroundColor.FractionAlpha()
               );

  glDisable(GL_BLEND);
  glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
#endif
  
  glMatrixMode(GL_MODELVIEW);
  glPushMatrix();
  glLoadIdentity();
  glMatrixMode(GL_PROJECTION);
  glPushMatrix();
  glLoadIdentity();
  
  glDisable( GL_LIGHTING );
  
  [self renderDrawable: gradientquad];
  glClear( GL_DEPTH_BUFFER_BIT );
  
  glEnable( GL_LIGHTING );
  
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopMatrix();
}

- (void) clearFrame
{
  [EAGLContext setCurrentContext: renderContext];
  glBindFramebufferOES (GL_FRAMEBUFFER_OES, defaultFramebuffer);
  glViewport (0, 0, backingWidth, backingHeight);
  [self drawBackground];
  glBindRenderbufferOES (GL_RENDERBUFFER_OES, colorRenderbuffer);
  [renderContext presentRenderbuffer: GL_RENDERBUFFER_OES];
}

// This is run on the main thread and schedules an erase on the render thread
- (void) clearView
{
  [self performSelector: @selector(clearFrame) onThread: [self renderThread] withObject: nil waitUntilDone: NO];
}

- (UIImage*) captureImage
{
  int screenWidth = backingWidth;
  int screenHeight = backingHeight;
  
  NSInteger bufferLength = screenWidth * screenHeight * 4;
  
  unsigned char* buffer = (unsigned char*) malloc (bufferLength);
  
	glPixelStorei(GL_PACK_ALIGNMENT, 4);
  
  glReadPixels(0,0,screenWidth,screenHeight,GL_RGBA,GL_UNSIGNED_BYTE, buffer);

  // OpenGL pixels are reversed from UIImage pixels - flip the image horizontally
  CGDataProviderRef ref = CGDataProviderCreateWithData(NULL, buffer, bufferLength, NULL);
  CGImageRef iref = CGImageCreate(screenWidth,screenHeight,8,32,screenWidth*4,CGColorSpaceCreateDeviceRGB(),kCGBitmapByteOrderDefault|kCGImageAlphaLast,ref,NULL,true,kCGRenderingIntentDefault);
  size_t width         = CGImageGetWidth(iref);
  size_t height        = CGImageGetHeight(iref);
  size_t length        = width*height*4;
  uint32_t *pixels     = (uint32_t *)calloc(length, 1);
  CGContextRef bitmapContext = CGBitmapContextCreate(pixels, width, height, 8, width*4, CGImageGetColorSpace(iref), kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Big);
  CGContextTranslateCTM(bitmapContext, 0.0, height);
  CGContextScaleCTM(bitmapContext, 1.0, -1.0);
  CGContextDrawImage(bitmapContext, CGRectMake(0.0, 0.0, width, height), iref);
  CGImageRef outputRef = CGBitmapContextCreateImage(bitmapContext);
  UIImage *outputImage = [UIImage imageWithCGImage: outputRef];
  CFRelease(ref);
  CGImageRelease(iref);
  CGContextRelease(bitmapContext);
  CFRelease(outputRef);
  free(buffer);
  free(pixels);
  return outputImage;
}


#if _DEBUG
- (void) saveTextureToFileNamed: (NSString*) path
{
  NSInteger bufferLength = textureWidth * textureHeight * 4;
  
  unsigned char* buffer = (unsigned char*) malloc (bufferLength);
  
	glPixelStorei(GL_PACK_ALIGNMENT, 4);
  
  glReadPixels(0,0,textureWidth,textureHeight,GL_RGBA,GL_UNSIGNED_BYTE, buffer);
  
  // OpenGL pixels are reversed from UIImage pixels - flip the image horizontally
  CGDataProviderRef ref = CGDataProviderCreateWithData(NULL, buffer, bufferLength, NULL);
  CGImageRef iref = CGImageCreate(textureWidth,textureHeight,8,32,textureWidth*4,CGColorSpaceCreateDeviceRGB(),kCGBitmapByteOrderDefault|kCGImageAlphaLast,ref,NULL,true,kCGRenderingIntentDefault);
  size_t width         = CGImageGetWidth(iref);
  size_t height        = CGImageGetHeight(iref);
  size_t length        = width*height*4;
  uint32_t *pixels     = (uint32_t *)calloc(length,1);
  CGContextRef bitmapContext = CGBitmapContextCreate(pixels, width, height, 8, width*4, CGImageGetColorSpace(iref), kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Big);
  CGContextTranslateCTM(bitmapContext, 0.0, height);
  CGContextScaleCTM(bitmapContext, 1.0, -1.0);
  CGContextDrawImage(bitmapContext, CGRectMake(0.0, 0.0, width, height), iref);
  CGImageRef outputRef = CGBitmapContextCreateImage(bitmapContext);
  UIImage *outputImage = [UIImage imageWithCGImage: outputRef];
  
  NSData* data = UIImagePNGRepresentation (outputImage);
  BOOL rc = [data writeToFile: path atomically: NO];
  
  CFRelease(ref);
  CGImageRelease(iref);
  CGContextRelease(bitmapContext);
  CFRelease(outputRef);
  free(buffer);
  free(pixels);
}
#endif

-(UIImage *) capturedImage
{
  return capturedImage;
}

- (void) setNeedsImageCapturedForDelegate: (id) aDelegate
{
  needsImageCapturedDelegate = aDelegate;
}

#pragma mark ---- ON_Materials ----

- (void) setMaterialColor: (GLenum) pname fromONColor: (ON_Color) rc alpha: (GLfloat) alpha
{
  GLfloat c[4];
  c[0] = (GLfloat)rc.FractionRed();
  c[1] = (GLfloat)rc.FractionGreen();
  c[2] = (GLfloat)rc.FractionBlue();
  c[3] = alpha;
  glMaterialfv (GL_FRONT_AND_BACK, pname, c);
}


- (void) setMaterial: (const ON_Material&) material
{
  ON_Color blackColor;
  GLfloat alpha = (GLfloat)(1.0 - material.Transparency());
  GLfloat shine = 128.0*(material.Shine() / ON_Material::MaxShine());
  
  if (alpha < 1.0)
    glEnable (GL_BLEND);
  else
    glDisable (GL_BLEND);
  
  [self setMaterialColor: GL_AMBIENT fromONColor: material.Ambient() alpha: alpha];
  [self setMaterialColor: GL_DIFFUSE fromONColor: material.Diffuse() alpha: alpha];
  [self setMaterialColor: GL_EMISSION fromONColor: material.Emission() alpha: alpha];
  
  if ( shine == 0 )
    [self setMaterialColor: GL_SPECULAR fromONColor: blackColor alpha: alpha];
  else
    [self setMaterialColor: GL_SPECULAR fromONColor: material.Specular() alpha: alpha];
  
  glMaterialf(  GL_FRONT_AND_BACK, GL_SHININESS, shine );
}


#pragma mark ---- RhModelView ----

- (BOOL) initGL
{
  glClearColor( (float)backgroundColor.FractionRed(), 
               (float)backgroundColor.FractionGreen(), 
               (float)backgroundColor.FractionBlue(), 
               (float)backgroundColor.FractionAlpha()
               );
  
  glLightModelf( GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE );
  
  // Rhino viewports have camera "Z" pointing at the camera in a right
  // handed coordinate system.
  glClearDepthf( 0.0f );
  glEnable( GL_DEPTH_TEST );
  glDepthFunc( GL_GEQUAL );
  glDepthMask (GL_TRUE);
  glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable( GL_LIGHTING );
  glEnable( GL_DITHER );
  glDisable (GL_CULL_FACE);

  // default material
  ON_Material default_mat;
  [self setMaterial: default_mat];
  
  gradientquad = [self createGradQuad];

  CheckGLError();

  return true;
}


/////////////////////////////////////////////////////////////////////
- (void) drawTransparentMeshes: (RhModel*) scene
{
  // Drawing transparent meshes is a 3 pass process...
  //
  // Pass #1: With depth buffer writing OFF
  //            i. Draw all objects' backfaces
  //           ii. Draw all "open" objects' front faces.
  //
  // Pass #2: With depth buffer writing ON
  //            i. Draw all objects' front faces
  //
  // Pass #3: With depth buffer writing ON
  //            i. Draw all "open" objects' back faces
  //
  
  if ( scene ) 
  {
    // Now render all transparent meshes...
    NSArray* meshes = [scene transmeshes];
    
    if ( meshes.count > 0 )
    {
      glDepthMask( GL_FALSE );
      glEnable( GL_CULL_FACE );
      
      for (DisplayMesh* mesh in meshes) 
      {
        glCullFace( GL_FRONT );
        [self drawMesh: mesh];
        
        if ( !mesh.isClosed )
        {
          glCullFace( GL_BACK );
          [self drawMesh: mesh];
        }
      }
      
      glDepthMask( GL_TRUE );
      glCullFace( GL_BACK );
      for (DisplayMesh* mesh in meshes) 
        [self drawMesh: mesh];
      
      glCullFace( GL_FRONT );
      for (DisplayMesh* mesh in meshes) 
      {
        if ( !mesh.isClosed )
          [self drawMesh: mesh];
      }
      glDisable( GL_CULL_FACE );
    }
  }
}

/////////////////////////////////////////////////////////////////////
- (void) drawScene: (RhModel*) scene
{
  // Draw scene...
  if ( scene ) 
  {
    // draw each mesh
    NSArray* meshes = [scene meshes];
    
    // First render all opaque objects...
    for (DisplayMesh* mesh in meshes)
      [self drawMesh: mesh];
    
    [self drawTransparentMeshes: scene];
  }
  CheckGLError();
}

/////////////////////////////////////////////////////////////////////
- (void) setupLighting
{
  // simple bright white headlight
  glMatrixMode(GL_MODELVIEW);
  glPushMatrix();
  glLoadIdentity();
  GLfloat pos[4]  = { (GLfloat)0.0, (GLfloat)0.0, (GLfloat)1.0, (GLfloat)0.0 };
  glLightfv( GL_LIGHT0, GL_POSITION,  pos );
  GLfloat black[4] = { (GLfloat)0.0, (GLfloat)0.0, (GLfloat)0.0, (GLfloat)1.0 };
  GLfloat white[4] = { (GLfloat)1.0, (GLfloat)1.0, (GLfloat)1.0, (GLfloat)1.0 };
  glLightfv( GL_LIGHT0, GL_AMBIENT,  black );
  glLightfv( GL_LIGHT0, GL_DIFFUSE,  white );
  glLightfv( GL_LIGHT0, GL_SPECULAR, white );
  glEnable( GL_LIGHT0 );
  glPopMatrix();
  
}

- (void) renderTexture: (RhModel*) model inViewport: (ON_Viewport&) viewport
{
  glBindFramebufferOES (GL_FRAMEBUFFER_OES, textureFramebuffer);

  [self setupLighting];
  [self setGLModelViewMatrix: viewport];
  [self setGLProjectionMatrix: viewport inWidth: textureWidth inHeight: textureHeight];

  [self drawBackground];
  [self drawScene: model];
}


- (void) renderModelWithTexture: (RhModel*) model inViewport: (ON_Viewport&) viewport doPresent: (BOOL) present
{
  if ([model onMacModel] == nil)
    return;
  
  // First render our scene to a texture/target...
  [self renderTexture: model inViewport: viewport];
  CheckGLError();
  
  //  [self saveTextureToFileNamed: @"/Users/macrhino/Desktop/Texture.png"];
  
  // Next, bind our primary framebuffer...
  glBindFramebufferOES (GL_FRAMEBUFFER_OES, defaultFramebuffer);
  
  // Move the render texture/target into the framebuffer...
  // Turn off some expensive tests to make this as fast as possible.
  glDisable( GL_BLEND );
  glDisable( GL_CULL_FACE );
  glDisable( GL_LIGHTING );
  glDepthMask( GL_FALSE );
  glDepthFunc( GL_ALWAYS );
  
  // Note: texture units are FBO dependent, so this must happen here,
  //       after the primary framebuffer has been enabled/bound.
  glEnable( GL_TEXTURE_2D );
  glBindTexture(GL_TEXTURE_2D, texture);
  glDrawTexiOES( 0,0,0, backingWidth, backingHeight );
  glDisable( GL_TEXTURE_2D );
  
  // Restore certain defaults...
  glEnable( GL_LIGHTING );
  glDepthMask( GL_TRUE );
  glDepthFunc( GL_GEQUAL );
  
  CheckGLError();
  
  if (needsImageCapturedDelegate) {
    [capturedImage release];
    capturedImage = [[self captureImage] retain];
    if ([needsImageCapturedDelegate respondsToSelector: @selector(didCaptureImage:)])
      [needsImageCapturedDelegate performSelectorOnMainThread: @selector(didCaptureImage:) withObject: capturedImage waitUntilDone: NO];
    needsImageCapturedDelegate = nil;
  }
    
  if ( present )
  {
    glBindRenderbufferOES (GL_RENDERBUFFER_OES, colorRenderbuffer);
    [renderContext presentRenderbuffer: GL_RENDERBUFFER_OES];
    CheckGLError();
  }
}  


- (void) renderModelWithoutTexture: (RhModel*) model inViewport: (ON_Viewport&) viewport doPresent: (BOOL) present
{
  if ([model onMacModel] == nil)
    return;
  
  glBindFramebufferOES (GL_FRAMEBUFFER_OES, defaultFramebuffer);
	
  [self setupLighting];
  [self setGLModelViewMatrix: viewport];
  [self setGLProjectionMatrix: viewport inWidth: backingWidth inHeight: backingHeight];
  
  [self drawBackground];
  [self drawScene: model];
  
  if (needsImageCapturedDelegate) {
    [capturedImage release];
    capturedImage = [[self captureImage] retain];
    if ([needsImageCapturedDelegate respondsToSelector: @selector(didCaptureImage:)])
      [needsImageCapturedDelegate performSelectorOnMainThread: @selector(didCaptureImage:) withObject: capturedImage waitUntilDone: NO];
    needsImageCapturedDelegate = nil;
  }
  
//  BOOL imageScaleMatchesScreen = YES;
//  if ([model.thumbnailImage respondsToSelector: @selector(scale)])
//    imageScaleMatchesScreen = [model.thumbnailImage scale] == [RhinoApp screenScale];
//  if (model.thumbnailImage == nil || !imageScaleMatchesScreen) {
//    UIImage* outputImage = [self captureImage];
//    UIImage* thumbnailImage = [outputImage thumbnailImage: 48 * [RhinoApp screenScale]
//                                        transparentBorder: 1
//                                             cornerRadius: 0
//                                     interpolationQuality: kCGInterpolationHigh];
//    if ([RhinoApp screenScale] != 1.0)
//      thumbnailImage = [UIImage imageWithCGImage: thumbnailImage.CGImage scale: [RhinoApp screenScale] orientation: UIImageOrientationUp];
//    model.thumbnailImage = thumbnailImage;
//  }
  
  if ( present )
  {
    glBindRenderbufferOES (GL_RENDERBUFFER_OES, colorRenderbuffer);
    [renderContext presentRenderbuffer: GL_RENDERBUFFER_OES];
    CheckGLError();
  }
}


// This method is run on NSThread renderThread
- (void) renderOneFrame
{
  RhModel* model;
  static ON_Viewport viewport;
  
  @synchronized(self)
  {
    model = renderModel;
    viewport = renderViewport1;
    performingRender = NO;
    
    CheckGLError();
    [EAGLContext setCurrentContext: renderContext];
    CheckGLError();
    
    if (canAntialias && !RhinoApp.fastDrawing)
      [self renderModelWithTexture: model inViewport: viewport doPresent: YES];
    else
      [self renderModelWithoutTexture: model inViewport: viewport doPresent: YES];
  }
}

- (void) EnableAnaglypMode: (int)  mode
{
  switch ( mode )
  {
    case AGM_AMBER_BLUE:
      glColorMask( GL_TRUE, GL_TRUE, GL_FALSE, GL_TRUE );
      break;
      
    case AGM_MAGENTA_GREEN:
      glColorMask( GL_TRUE, GL_FALSE, GL_TRUE, GL_TRUE );
      break;
    
    case AGM_RED_CYAN:
    default:
      // Red/Cyan
      glColorMask( GL_TRUE, GL_FALSE, GL_FALSE, GL_TRUE );
      break;
  }
}

- (void) DisableAnaglyphMode
{
  glColorMask( GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE );
}

/////////////////////////////////////////////////////////////////////
// This method is run on NSThread renderThread
- (void) renderStereoFrame
{
  RhModel* model;
  static ON_Viewport leftEye;
  static ON_Viewport rightEye;
  
  @synchronized(self)
  {
    model = renderModel;
    leftEye  = renderViewport1;
    rightEye = renderViewport2;
    performingRender = NO;
    
    CheckGLError();
    [EAGLContext setCurrentContext: renderContext];
    CheckGLError();
    
    if (canAntialias && !RhinoApp.fastDrawing)
    {
      [self renderModelWithTexture: model inViewport: leftEye doPresent: NO];
      [self EnableAnaglypMode: stereoConfig];
      [self renderModelWithTexture: model inViewport: rightEye doPresent: YES];
    }
    else
    {
      [self renderModelWithoutTexture: model inViewport: leftEye doPresent: NO];
      [self EnableAnaglypMode: stereoConfig];
      [self renderModelWithoutTexture: model inViewport: rightEye doPresent: YES];
    }
    
    [self DisableAnaglyphMode];
  }
}


// This method is run on NSThread renderThread
- (void) renderFrames
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  // initialize OpenGL context in this render thread
  if (renderContext == nil) {
    EAGLSharegroup* group = mainContext.sharegroup;
    if (!group)
    {
      DLog(@"Could not get sharegroup from the main context");
    }
    renderContext = [[EAGLContext alloc] initWithAPI: kEAGLRenderingAPIOpenGLES1 sharegroup:group];
    if (!renderContext || ![EAGLContext setCurrentContext: renderContext]) {
      DLog(@"Could not create renderContext");
    }
  }
  
  [self initGL];
    
  [pool release];
  
  while (1) {
    NSRunLoop* currentRunLoop = [NSRunLoop currentRunLoop];
    [currentRunLoop run];
    [NSThread sleepForTimeInterval: 0.1];
    NSLog (@"restarting runloop:%p", currentRunLoop);
  }
}


// This method runs on the main thread and schedules one frame to be drawn on the render thread
- (void) renderModel: (RhModel*) model inViewport: (ON_Viewport) viewport
{
  @synchronized(self)
  {    
    renderModel = model;
    renderViewport1 = viewport;
    
    if (!performingRender)
      [self performSelector: @selector(renderOneFrame) onThread: [self renderThread] withObject: nil waitUntilDone: NO];
    performingRender = YES;
  }
}

- (void) renderModel: (RhModel*) model inLeftEye: (const ON_Viewport&) leftEye inRightEye: (const ON_Viewport&) rightEye;
{
  @synchronized(self)
  {    
    renderModel = model;
    renderViewport1 = leftEye;
    renderViewport2 = rightEye;
    
    if (!performingRender)
      [self performSelector: @selector(renderStereoFrame) onThread: [self renderThread] withObject: nil waitUntilDone: NO];
    performingRender = YES;
  }
}

// This method runs on the main thread
- (UIImage*) renderPreview: (RhModel*) model inViewport: (ON_Viewport) viewport
{
  [EAGLContext setCurrentContext: mainContext];
  CheckGLError();
  
  // set transparent background color
  ON_Color savedBackgroundColor = backgroundColor;
  backgroundColor = ON_Color (0, 0, 0, 0);
  glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

  // draw the model at texture size with a transparent background
  [self renderModelWithTexture: model inViewport: viewport doPresent: YES];
  UIImage* previewImage = [self captureImage];
  
  // restore background color
  backgroundColor = savedBackgroundColor;
  glClearColor( (float)backgroundColor.FractionRed(), 
               (float)backgroundColor.FractionGreen(), 
               (float)backgroundColor.FractionBlue(), 
               (float)backgroundColor.FractionAlpha()
               );
  return previewImage;
}

#pragma mark ---- view change ----

- (void) setGLModelViewMatrix: (const ON_Viewport&) viewport
{
  //  DLog (@"viewport:%p", &viewport);
  // sets model view matrix (world to camera transformation)
  ON_Xform modelviewMatrix; // world to camera transformation
  ON_BOOL32 bHaveWorldToCamera = viewport.GetXform(ON::world_cs, ON::camera_cs, modelviewMatrix);
  if (bHaveWorldToCamera) {
    modelviewMatrix.Transpose();
    glMatrixMode(GL_MODELVIEW);
    glLoadMatrixd( &modelviewMatrix.m_xform[0][0] );
  }
}

- (void) setGLProjectionMatrix: (ON_Viewport&) viewport inWidth: (int) width inHeight: (int) height
{
  viewport.SetScreenPort( 0, width-1, height-1, 0, 0, 0xffff );
  
  //int port_left, port_right, port_bottom, port_top;
	
  //viewport.GetScreenPort( &port_left, &port_right, &port_bottom, &port_top, NULL, NULL );
//  DLog (@"viewport:%p port_left:%d port_right:%d port_bottom:%d port_top:%d", &viewport, port_left, port_right, port_bottom, port_top);
  
  //const int port_width  = abs(port_right - port_left);
  //const int port_height = abs(port_top - port_bottom);
  //if ( port_width == 0 || port_height == 0 )
  //  return;
  
  ON_Xform projectionMatrix; // camera to clip transformation
  ON_BOOL32 bHaveCameraToClip = viewport.GetXform(ON::camera_cs, ON::clip_cs, projectionMatrix);
  
  if ( bHaveCameraToClip ) {
    projectionMatrix.Transpose();
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixd( &projectionMatrix.m_xform[0][0] );
  }
  
  glViewport (0, 0, width, height );
}

- (void) drawMesh: (DisplayMesh*) mesh
{
  [self setMaterial: [mesh material]];
  
  glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, [mesh indexBuffer]);
  
  if ( 1 ) {
    glBindBuffer (GL_ARRAY_BUFFER, [mesh vertexBuffer] );
    glEnableClientState (GL_VERTEX_ARRAY);
    glVertexPointer(3, GL_FLOAT, sizeof(VertexData), 0);
    glEnableClientState (GL_NORMAL_ARRAY);
    glNormalPointer(GL_FLOAT, sizeof(VertexData), (GLvoid*)sizeof(ON_3fPoint));
  }
  else {
    glBindBuffer (GL_ARRAY_BUFFER, [mesh vertexBuffer]);
    glEnableClientState (GL_VERTEX_ARRAY);
    glVertexPointer (3, GL_FLOAT, sizeof(ON_3fPoint), (void*)0);
  }
  
  glDrawElements(GL_TRIANGLES, 3 * [mesh triangleCount], GL_UNSIGNED_SHORT, 0);
}

@end
