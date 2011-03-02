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

#import "ES2Renderer.h"
#import "RhModel.h"
#import "RhModelView.h"
#import "UIColor-RGBA.h"


#if defined (_DEBUG)
#define CheckGLError(xxx)  do { GLenum err = glGetError(); if (err) DLog (@"err: %x", err); } while (0)
#else
#define CheckGLError(xxx)  
#endif

@interface ES2Renderer (PrivateMethods)
- (BOOL) loadShaders;
- (const char *) getResourceAsString: (NSString *)name ofType:(NSString *)ext;
- (CRhGLShaderProgram*) loadShaderResource: (NSString *)baseName;
- (void) clearBackground;
- (void) renderDrawable: (const RhGLDrawable*) drawable;
- (void) drawScreenAlignedQuad;
@end


@implementation ES2Renderer

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

////////////////////////////////////////////////////////////////////
// Create an ES 2.0 context
- (id <ESRenderer>) init
{
	if (self = [super init])
	{
		mainContext = [[EAGLContext alloc] initWithAPI: kEAGLRenderingAPIOpenGLES2];
    if (!mainContext || ![EAGLContext setCurrentContext: mainContext] || ![self loadShaders])
		{
      [self release];
      return nil;
    }
    
    quad = NULL;
    gradientquad = NULL;
    
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
    glGenRenderbuffers( 1, &colorRenderbuffer );
    glBindRenderbuffer( GL_RENDERBUFFER, colorRenderbuffer );
  }
  
  return self;
}

////////////////////////////////////////////////////////////////////
- (GLuint) createFboTexture: (GLint) width  inHeight: (GLint) height
{
  GLuint fbt;
  glGenTextures(1, &fbt);
  glBindTexture(GL_TEXTURE_2D, fbt);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
  
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
      glGenFramebuffers( 1, &defaultFramebuffer );
      glGenRenderbuffers( 1, &depthRenderbuffer );
    }
    
    // Make sure our primary render buffer is bound and then query for
    // the physical dimensions...
    glBindRenderbuffer( GL_RENDERBUFFER, colorRenderbuffer );
    [mainContext renderbufferStorage: GL_RENDERBUFFER fromDrawable: layer];
    glGetRenderbufferParameteriv( GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH,  &backingWidth );
    glGetRenderbufferParameteriv( GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    // Determine if our frame buffer(s) need to be resized. If the current width or height
    // is different than our previous width/height, then we need to make sure our buffers
    // reflect the new sizes...
    if ( (backingWidth != oldBackingWidth) || (backingHeight != oldBackingHeight) )
    {
      // Allocate color buffer backing based on the current layer size
      glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
      glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
      glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
      glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
      glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer );
      
      if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
      {
        DLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
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
      
      // Lazy evaluation of texture's FBO...since we really don't know we
      // can anti-alias or what the oversampling sizes are until we reach 
      // this point...
      if ( textureFramebuffer == 0 )
      {
        glGenFramebuffers(1, &textureFramebuffer);
        glGenRenderbuffers(1, &textureDepthbuffer);
        texture = [self createFboTexture: textureWidth  inHeight: textureHeight];
      }
      
      // Check to see if the texture buffers need to be resized...
      if ( (textureWidth != oldWidth) || (textureHeight != oldHeight) )
      {
        // As far as I know, ES 2.0 devices all support NPOT textures...at least 
        // when being used as render buffers/targets. Interpretation of the 2.0 spec.
        // So we don't need to worry about perfect powers of 2 for our dimensions...
        glBindFramebuffer( GL_FRAMEBUFFER, textureFramebuffer );
        glBindRenderbuffer( GL_RENDERBUFFER, textureDepthbuffer );
        glRenderbufferStorage( GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, textureWidth, textureHeight );
        glFramebufferRenderbuffer( GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, textureDepthbuffer );
        glBindTexture( GL_TEXTURE_2D, texture );
        glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA,  textureWidth, textureHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
        
        // Validate the texture FBO. Note: This is framebuffer "bound" dependent...meaning,
        // this check validates against the currently bound framebuffer only.
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) 
        {
          DLog(@"failed to make complete texture buffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
          rc = NO;
        }
      }
    }
    
    // Always make sure our primary framebuffer is in use...
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
  }
  return rc;
}

/////////////////////////////////////////////////////////////////////
- (const char *) getResourceAsString: (NSString *)name ofType: (NSString *)ext 
{
	NSString   *resource = [[NSBundle mainBundle] pathForResource:name ofType:ext];
  const char *contents = [[NSString stringWithContentsOfFile:resource encoding:NSUTF8StringEncoding error:nil] UTF8String];
  
  return contents;
}

/////////////////////////////////////////////////////////////////////
- (CRhGLShaderProgram*) loadShaderResource: (NSString *)baseName 
{
  const char  *vertexShader   = [self getResourceAsString:baseName ofType:@"vsh"];
  const char  *fragmentShader = [self getResourceAsString:baseName ofType:@"fsh"];
  
  CRhGLShaderProgram *pShader = new CRhGLShaderProgram;
  if ( !pShader->BuildProgram( vertexShader, fragmentShader ) )
  {
    delete pShader;
    pShader = NULL;
  }
  
  return pShader;
}

/////////////////////////////////////////////////////////////////////
- (BOOL) loadShaders 
{
  activeShader    = NULL;
  
  perpixelShader  = [self loadShaderResource:@"PerPixelLighting"];
  pervertexShader = [self loadShaderResource:@"PerVertexLighting"];
  quadShader      = [self loadShaderResource:@"FullscreenQuad"];
  gradientShader  = [self loadShaderResource:@"GradientQuad"];
  anaglyphShader  = NULL;
  
  if ( (perpixelShader == NULL) || (pervertexShader == NULL) || (quadShader == NULL) || (gradientShader == NULL) )
    return NO;
  
  quadShader->Enable();
  int  loc = glGetUniformLocation( quadShader->Handle(), "Image" );
  glUniform1f( loc, 0 );
  quadShader->Disable();
  
	return YES;
}


/////////////////////////////////////////////////////////////////////
- (NSThread*) renderThread
{
  if (renderThread == nil) {
    renderThread = [[NSThread alloc] initWithTarget: self selector: @selector(renderFrames) object: nil];
    [renderThread start];
  }
  return renderThread;
}

/////////////////////////////////////////////////////////////////////
- (void) dealloc
{
  [capturedImage release];
  capturedImage = nil;
  
	// Tear down GL
	if (defaultFramebuffer)
	{
		glDeleteFramebuffers(1, &defaultFramebuffer);
		defaultFramebuffer = 0;
	}
	
	if (colorRenderbuffer)
	{
		glDeleteRenderbuffers(1, &colorRenderbuffer);
		colorRenderbuffer = 0;
	}
	
	if (depthRenderbuffer)
	{
		glDeleteRenderbuffers(1, &depthRenderbuffer);
		depthRenderbuffer = 0;
	}
	
	if (textureFramebuffer)
	{
		glDeleteFramebuffers(1, &textureFramebuffer);
		textureFramebuffer = 0;
	}
	
	if (texture)
	{
		glDeleteRenderbuffers(1, &texture);
		texture = 0;
	}
	
	if (textureDepthbuffer)
	{
		glDeleteRenderbuffers(1, &textureDepthbuffer);
		textureDepthbuffer = 0;
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
	
  if ( quad != NULL )
  {
    delete quad;
    quad = NULL;
  }
  
  if ( pervertexShader != NULL )
  {
    delete pervertexShader;
    pervertexShader = NULL;
  }
  
  if ( perpixelShader != NULL )
  {
    delete perpixelShader;
    perpixelShader = NULL;
  }
  
  if ( quadShader != NULL )
  {
    delete quadShader;
    quadShader = NULL;
  }
  
  if ( gradientShader != NULL )
  {
    delete gradientShader;
    gradientShader = NULL;
  }
  
  if ( anaglyphShader != NULL )
  {
    delete anaglyphShader;
    anaglyphShader = NULL;
  }
  
  activeShader = NULL;
  
	[super dealloc];
}


#pragma mark ---- OpenGL ES helper functions ----


#pragma mark ---- Accessors ----


/////////////////////////////////////////////////////////////////////
- (ON_Color) backgroundColor
{
  return backgroundColor;
}

/////////////////////////////////////////////////////////////////////
- (void) setBackgroundColor: (ON_Color) onColor
{
  backgroundColor = onColor;
}

/////////////////////////////////////////////////////////////////////
- (void) setDefaultBackgroundColor
{
  backgroundColor = RhinoApp.backgroundColor;
}


#pragma mark ---- Utilities ----

- (void) clearFrame
{
  [EAGLContext setCurrentContext: renderContext];
  glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
  glViewport (0, 0, backingWidth, backingHeight);
  
  glClearColor( (float)backgroundColor.FractionRed(), 
                (float)backgroundColor.FractionGreen(), 
                (float)backgroundColor.FractionBlue(), 
                (float)backgroundColor.FractionAlpha()
               );
  
  glDisable(GL_BLEND);
  [self clearBackground];
  glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
  [renderContext presentRenderbuffer: GL_RENDERBUFFER];
}

// This is run on the main thread and schedules an erase on the render thread
- (void) clearView
{
  [self performSelector: @selector(clearFrame) onThread: [self renderThread] withObject: nil waitUntilDone: NO];
}


/////////////////////////////////////////////////////////////////////
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

/////////////////////////////////////////////////////////////////////
-(UIImage *) capturedImage
{
  return capturedImage;
}

/////////////////////////////////////////////////////////////////////
- (void) setNeedsImageCapturedForDelegate: (id) aDelegate
{
  needsImageCapturedDelegate = aDelegate;
}

/////////////////////////////////////////////////////////////////////
- (void) renderDrawable:(const RhGLDrawable*) drawable
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
    stride += sizeof(float)*3;
  
  GLvoid* offset = (GLvoid*)(sizeof(float)*3);
  
  glBindBuffer( GL_ARRAY_BUFFER, drawable->vertexBuffer );
  
  glEnableVertexAttribArray( ATTRIB_VERTEX );
  glVertexAttribPointer( ATTRIB_VERTEX, 3, GL_FLOAT, GL_FALSE, stride, 0 );

  // Any normals?
  if ( drawable->attrs & 1 ) 
  {
    glEnableVertexAttribArray( ATTRIB_NORMAL );
    glVertexAttribPointer( ATTRIB_NORMAL, 3, GL_FLOAT, GL_FALSE, stride, offset );
    offset = (GLvoid*)((int)offset + sizeof(float)*3);
  }
  
  // Any texture coordinates?
  if (drawable->attrs & 2) 
  {
    glEnableVertexAttribArray( ATTRIB_TEXCOORD0 );
    glVertexAttribPointer( ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, stride, offset );
    offset = (GLvoid*)((int)offset + sizeof(float)*2);
  }
  
  // Any colors?
  if (drawable->attrs & 4) 
  {
    glEnableVertexAttribArray( ATTRIB_COLOR );
    glVertexAttribPointer( ATTRIB_COLOR, 3, GL_FLOAT, GL_FALSE, stride, offset );
  }
  
  glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, drawable->indexBuffer );
  glDrawElements( GL_TRIANGLES, drawable->indexCount, GL_UNSIGNED_SHORT, 0 ) ;
  
  glDisableVertexAttribArray( ATTRIB_VERTEX );
  glDisableVertexAttribArray( ATTRIB_NORMAL );
  glDisableVertexAttribArray( ATTRIB_TEXCOORD0 );
  glDisableVertexAttribArray( ATTRIB_COLOR );
}

/////////////////////////////////////////////////////////////////////
- (RhGLDrawable*) createQuad
{
  static float vertices[20] = { -1,-1,1,0,0, 1,-1,1,1,0, 1,1,1,1,1, -1,1,1,0,1 };
  static short indexes[6]   = { 0,1,3, 1,2,3 };
  
  GLuint vertexBuffer;
  
  glGenBuffers(1, &vertexBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData( GL_ARRAY_BUFFER,
               20 * sizeof(float),
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
  qd->attrs        = 2;
  
  return qd;
}

/////////////////////////////////////////////////////////////////////
- (RhGLDrawable*) createGradQuad
{
  UIColor* topColor = RhinoApp.backgroundTopColor;
  UIColor* bottomColor = RhinoApp.backgroundBottomColor;
  float vertices[24] = {
    -1,-1,1,
    [bottomColor red], [bottomColor green], [bottomColor blue],
    1,-1,1,
    [bottomColor red], [bottomColor green], [bottomColor blue],
    1,1,1,
    [topColor red], [topColor green], [topColor blue],
    -1,1,1,
    [topColor red], [topColor green], [topColor blue],
  };
  
  static short indexes[6]   = { 0,1,3, 1,2,3 };
  
  GLuint vertexBuffer;
  
  glGenBuffers(1, &vertexBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData( GL_ARRAY_BUFFER,
               24 * sizeof(float),
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

/////////////////////////////////////////////////////////////////////
- (void) drawScreenAlignedQuad
{
  // lazy evaluation of the quad drawable...
  if ( quad == NULL )
    quad = [self createQuad];
  
  glDepthMask( GL_FALSE );
  [self renderDrawable: quad];
  glDepthMask( GL_TRUE );
}

/////////////////////////////////////////////////////////////////////
- (void) clearBackground
{
  if ( gradientShader != NULL )
  {
    // lazy evaluation of the gradient quad drawable...
    if ( gradientquad == NULL )
      gradientquad = [self createGradQuad];
    
    gradientShader->Enable();
    glDepthMask( GL_FALSE );
    [self renderDrawable: gradientquad];
    glDepthMask( GL_TRUE );
    gradientShader->Disable();
    glClear( GL_DEPTH_BUFFER_BIT );
    if ( activeShader != NULL )
      activeShader->Enable();
  }
  else
    glClear( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT );
}


#pragma mark ---- ON_Materials ----

/////////////////////////////////////////////////////////////////////
- (void) setMaterial: (const ON_Material&) material
{
  if ( activeShader != NULL )
    activeShader->SetupMaterial( material );
}


#pragma mark ---- RhModelView ----

/////////////////////////////////////////////////////////////////////
- (BOOL) initGL
{
  glClearColor((float)backgroundColor.FractionRed(), 
               (float)backgroundColor.FractionGreen(), 
               (float)backgroundColor.FractionBlue(), 
               (float)backgroundColor.FractionAlpha()
               );

  // Rhino viewports have camera "Z" pointing at the camera in a right
  // handed coordinate system.
  glClearDepthf( 0.0f );
  glDepthRangef( 0.0, 1.0 );
  glEnable( GL_DEPTH_TEST );
  glDepthFunc( GL_GEQUAL );
  glDepthMask( GL_TRUE );
  glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
  glDisable( GL_DITHER );
  glDisable( GL_CULL_FACE );
  
  // default material
  ON_Material default_mat;
  [self setMaterial: default_mat];
  
  return true;
}

/////////////////////////////////////////////////////////////////////
- (void) setupActiveShader: (RhModel*) model inViewport: (const ON_Viewport&) viewport
{
  // Do we even have an active shader...
  if ( activeShader != NULL )
  {
    // Just use ON's default light for now...
    ON_Light   light;
    light.Default();
    
    // unfortunately ON assumes right-handedness...
    light.m_direction.z = -light.m_direction.z;
    
    // First enable the shader...
    activeShader->Enable();
    
    // Now setup and initialize frustum and lighting.
    activeShader->SetupViewport( viewport );
    activeShader->SetupLight( light );
  }
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

/////////////////////////////////////////////////////////////////////
- (void) DisableAnaglyphMode
{
  glColorMask( GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE );
}


////////////////////////////////////////////////////////////////////
- (void) renderToTarget: (RhModel*) scene inFBO: (GLuint) target inWidth: (int) width inHeight: (int) height
{
  // Enable oversample FBO...
  glBindFramebuffer( GL_FRAMEBUFFER, target );
  glViewport( 0, 0, width, height );
  glDepthFunc( GL_GEQUAL );
  
  [self clearBackground];
  [self drawScene: scene];
  CheckGLError();
}


/////////////////////////////////////////////////////////////////////
- (void) renderModelWithTexture: (RhModel*) model inViewport: (ON_Viewport&) viewport doPresent:(BOOL) present
{
  if ([model onMacModel] == nil)
    return;
  
  glDisable(GL_BLEND);
  [self renderToTarget: model inFBO: textureFramebuffer inWidth:textureWidth inHeight:textureHeight];
  
  //if ( present )
  //  [self saveTextureToFileNamed: @"/Users/jefflasor/Desktop/Texture.png"];
  
  glBindFramebuffer (GL_FRAMEBUFFER, defaultFramebuffer);
  glViewport (0, 0, backingWidth, backingHeight);
  CheckGLError();
  
  if ( present )
  {
    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, texture );
   
    glDisable( GL_BLEND );
    [self DisableAnaglyphMode];
    quadShader->Enable();
    [self drawScreenAlignedQuad];
    quadShader->Disable();
   
    CheckGLError();
  }
  
  if (present && needsImageCapturedDelegate) {
    [capturedImage release];
    capturedImage = [[self captureImage] retain];
    if ([needsImageCapturedDelegate respondsToSelector: @selector(didCaptureImage:)])
      [needsImageCapturedDelegate performSelectorOnMainThread: @selector(didCaptureImage:) withObject: capturedImage waitUntilDone: NO];
    needsImageCapturedDelegate = nil;
  }
    
  if ( present )
  {
    glBindRenderbuffer (GL_RENDERBUFFER, colorRenderbuffer);
    [renderContext presentRenderbuffer: GL_RENDERBUFFER];
    CheckGLError();
  }
}  


/////////////////////////////////////////////////////////////////////
- (void) renderModelWithoutTexture: (RhModel*) model inViewport: (ON_Viewport&) viewport doPresent:(BOOL) present
{
  if ([model onMacModel] == nil)
    return;
  
  glBindFramebuffer (GL_FRAMEBUFFER, defaultFramebuffer);
  glViewport (0, 0, backingWidth, backingHeight);
  
  glDisable(GL_BLEND);
  glDepthFunc( GL_GEQUAL );

  [self clearBackground];
  [self drawScene: model];
  
  CheckGLError();
  
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
    glBindRenderbuffer (GL_RENDERBUFFER, colorRenderbuffer);
    [renderContext presentRenderbuffer: GL_RENDERBUFFER];
    CheckGLError();
  }
}


/////////////////////////////////////////////////////////////////////
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
    
    [EAGLContext setCurrentContext: renderContext];
    CheckGLError();
    
    if ( !RhinoApp.fastDrawing )
      activeShader = perpixelShader;
    else
      activeShader = pervertexShader;
    
    [self setupActiveShader: model inViewport: viewport];  
    
    glDepthFunc( GL_GEQUAL );
    if (canAntialias && !RhinoApp.fastDrawing)
      [self renderModelWithTexture: model inViewport: viewport doPresent: YES];
    else
      [self renderModelWithoutTexture: model inViewport: viewport doPresent: YES];

    activeShader->Disable();
  }
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
    
    [EAGLContext setCurrentContext: renderContext];
    CheckGLError();
    
    if ( !RhinoApp.fastDrawing )
      activeShader = perpixelShader;
    else
      activeShader = pervertexShader;
    
    
    if (canAntialias && !RhinoApp.fastDrawing)
    {
      [self setupActiveShader: model inViewport: leftEye];  
      [self renderModelWithTexture: model inViewport: leftEye doPresent: NO];
      
      [self setupActiveShader: model inViewport: rightEye];  
      [self EnableAnaglypMode: stereoConfig];
      [self renderModelWithTexture: model inViewport: rightEye doPresent: YES];
    }
    else
    {
      [self setupActiveShader: model inViewport: leftEye];  
      [self renderModelWithoutTexture: model inViewport: leftEye doPresent: NO];
      
      [self setupActiveShader: model inViewport: rightEye];  
      [self EnableAnaglypMode: stereoConfig];
      [self renderModelWithoutTexture: model inViewport: rightEye doPresent: YES];
    }
    
    [self DisableAnaglyphMode];
    activeShader->Disable();
  }
}


/////////////////////////////////////////////////////////////////////
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
    renderContext = [[EAGLContext alloc] initWithAPI: kEAGLRenderingAPIOpenGLES2 sharegroup:group];
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


/////////////////////////////////////////////////////////////////////
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


/////////////////////////////////////////////////////////////////////
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


/////////////////////////////////////////////////////////////////////
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

/////////////////////////////////////////////////////////////////////
- (void) drawMesh: (DisplayMesh*) mesh
{
  [self setMaterial: [mesh material]];
  
  glBindBuffer( GL_ARRAY_BUFFER, [mesh vertexBuffer] );
  
  unsigned int stride = [mesh Stride];
  
  glEnableVertexAttribArray( ATTRIB_VERTEX );
  glVertexAttribPointer( ATTRIB_VERTEX, 3, GL_FLOAT, GL_FALSE, stride, 0 );
  
  if ( [mesh hasVertexNormals] )
  {
    glEnableVertexAttribArray( ATTRIB_NORMAL );
    glVertexAttribPointer( ATTRIB_NORMAL, 3, GL_FLOAT, GL_FALSE, stride, (GLvoid*)sizeof(ON_3fPoint) );
  }
  
  if ( [mesh hasVertexColors] )
  {
    int  offset = sizeof(ON_3fPoint);
    
    if ( [mesh hasVertexNormals] )
      offset += sizeof(ON_3fVector);
    
    glEnableVertexAttribArray( ATTRIB_COLOR );
    glVertexAttribPointer( ATTRIB_COLOR, 4, GL_FLOAT, GL_FALSE, stride, (GLvoid*)offset );
    if ( activeShader != NULL )
      activeShader->EnableColorUsage( true );
  }
  
  glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, [mesh indexBuffer] );
  glDrawElements( GL_TRIANGLES, 3 * [mesh triangleCount], GL_UNSIGNED_SHORT, 0 );  

  glDisableVertexAttribArray( ATTRIB_VERTEX );
  glDisableVertexAttribArray( ATTRIB_NORMAL );
}


@end
