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

#import "RhModelView.h"
#import "DisplayMesh.h"
#import "RhModel.h";
#import "RhModelViewController.h"
#import "ClippingPlanes.h"

#import <CoreGraphics/CGGeometry.h>
#import <mach/mach.h>
#import <mach/mach_time.h>


// 13-Aug-2009 Dale Fugier, Cosine interpolator
static double CosInterp( double a, double b, double n )
{
  if (n <= 0)
    return a;
  if (n >= 1 || a == b)
    return b;
  double n2 = ( 1.0 - cos(n * ON_PI) ) / 2;
  return ( a * (1.0 - n2) + b * n2 );
}


#define RHINO_CLAMP(V,L,H) ( (V) < (L) ? (L) : ( (V) > (H) ? (H) : (V) ) )

// 13-Aug-2009 Dale Fugier, Spherical linear interpolator
static ON_3dVector Slerp( const ON_3dVector& v0, const ON_3dVector& v1, double n )
{
  if( n <= 0.0 )
    return v0;
  
  if( v0 == v1 || n >= 1.0 )
    return v1;
  
  ON_3dVector u0( v0 );
  ON_3dVector u1( v1 );
  
  u0.Unitize();
  u1.Unitize();
  
  double dot = ON_DotProduct( u0, u1 );
  dot = RHINO_CLAMP( dot, -1.0, 1.0 );
  double theta = acos( dot );
  if( theta == 0.0 )
    return v1;
  
  double st = sin( theta );
  return ( v0 * (sin((1.0 - n) * theta) / st) + v1 * sin(n * theta) / st );
}


// forward declare private function
@interface RhModelView ()
- (void) setTarget: (ON_3dPoint) target_location cameraLocation: (ON_3dPoint) camera_location cameraUp: (ON_3dVector) camera_up;
@end



@implementation RhModelView


@synthesize delegate, stereoMode, anaglyph;


#pragma mark ---- initialization ----


- (id) initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder: coder];
  if (self) {
    if([[UIScreen mainScreen] respondsToSelector: @selector(scale)] && [self respondsToSelector: @selector(setContentScaleFactor:)])
      self.contentScaleFactor = [[UIScreen mainScreen] scale];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(orientationChanged:) name: UIDeviceOrientationDidChangeNotification object: nil];
    self.anaglyph = [[[AnaglyphCalculator alloc] init] autorelease];
  }
  return self;
}

- (id) initWithFrame:(CGRect)frame
{
  self = [super initWithFrame: frame];
  if (self) {
    if([[UIScreen mainScreen] respondsToSelector: @selector(scale)] && [self respondsToSelector: @selector(setContentScaleFactor:)])
      self.contentScaleFactor = [[UIScreen mainScreen] scale];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(orientationChanged:) name: UIDeviceOrientationDidChangeNotification object: nil];
    self.anaglyph = [[[AnaglyphCalculator alloc] init] autorelease];
  }
  return self;
}

- (void) setFrustum: (ON_Viewport&) viewport boundingBox: (const ON_BoundingBox&) bbox
{
  ClippingInfo clipping;
  clipping.bbox = bbox;
  if (iCalcClippingPlanes (viewport, clipping))
    iSetupFrustum (viewport, clipping);
}

- (void) reshape
{
	if (!m_model)
		return;
  
  CGRect rect = [self bounds];
  m_view.m_vp.SetScreenPort( 0, rect.size.width-1, rect.size.height-1, 0, 0, 0xff );
  
  const double port_aspect = ((double)rect.size.width)/((double)rect.size.height);
  m_view.m_vp.SetFrustumAspect( port_aspect );
  
  if (rhinoModel)
    [self setFrustum: m_view.m_vp boundingBox: [rhinoModel boundingBox]];
}

- (void) setModel: (RhModel*) aModel
{
  rhinoModel = aModel;
	m_model = [aModel onMacModel];      // one of these should be eliminated
  rhinoModel.initializationFailed = NO;
  
  [renderer setDefaultBackgroundColor];
  
  if (m_model == NULL)
    return;
  
  m_bbox = m_model->BoundingBox();
  
  // initialize m_view from model
  bool initialized = false;
  int view_count = m_model->m_settings.m_views.Count();
//  DLog (@"view_count:%d", view_count);
  
  if ( view_count > 0 )
  {    
    // find first perspective viewport projection in file
    for (int idx=0; idx<view_count; idx++) {
      if (m_model->m_settings.m_views[idx].m_vp.Projection() == ON::perspective_view) {
        initialized = true;
        double angle;
        m_view.m_vp = m_model->m_settings.m_views[idx].m_vp;
        m_view.m_target = m_model->m_settings.m_views[idx].m_target;
        m_view.m_name = m_model->m_settings.m_views[idx].m_name;
//        DLog (@"%@", w2ns(m_view.m_name));
      }
    }
  }
  if (!initialized) 
  {
    m_model->GetDefaultView( m_bbox, m_view );
  }
  
  m_view.m_vp.SetTargetPoint (m_view.m_target);
  
  // fix up viewport values
  ON_3dVector camDir = m_view.m_vp.CameraDirection();
  camDir.Unitize();
  m_view.m_vp.SetCameraDirection(camDir);
  
  ON_3dVector camUp = m_view.m_vp.CameraUp();
  camUp.Unitize();
  m_view.m_vp.SetCameraUp(camUp);
  
  [self reshape];
  
//  DLog (@"CameraLocation %g %g %g", m_view.m_vp.CameraLocation().x, m_view.m_vp.CameraLocation().y, m_view.m_vp.CameraLocation().z);
//  DLog (@"TargetPoint %g %g %g", m_view.m_vp.TargetPoint().x, m_view.m_vp.TargetPoint().y, m_view.m_vp.TargetPoint().z);

  // If needed, enlarge frustum so its aspect matches the window's aspect.
  // Since the Rhino file does not store the far frustum distance in the
  // file, viewports read from a Rhil file need to have the frustum's far
  // value set by inspecting the bounding box of the geometry to be
  // displayed.
  
  DLog (@"meshes:%d polygonCount:%d filesize:%d", rhinoModel.renderMeshCount + rhinoModel.meshObjectCount, [rhinoModel polygonCount], [rhinoModel fileSize]);
  
  stereoMode = NO;
}


- (void) prepareForDisplay: (RhModel*) aModel
{
  [self setModel: aModel];
  
  // save initial viewport settings for restoreView
  initialPosition = lastPosition = m_view.m_vp;
  atInitialPosition = true;
}


- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  self.anaglyph = nil;
  [super dealloc];
}

#pragma mark ---- Accessors ----


- (RhModel*) model
{
  return rhinoModel;
}

#pragma mark ---- Utilities ----

- (uint64_t) nanosecondTime
{
  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  
  uint64_t now = mach_absolute_time();
  
  /* Convert mach_absolute_time to nanoseconds */
  now *= info.numer;
  now /= info.denom;
  return now;
}

- (CGFloat)distanceFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint
{
  float xDist = fromPoint.x - toPoint.x;
  float yDist = fromPoint.y - toPoint.y;
  
  float result = sqrt(xDist * xDist + yDist * yDist);
  return result;
}


- (float) distanceBetweenTouches: (NSSet*) touches
{
  if (touches.count == 2) {
    NSArray* bothTouches = [touches allObjects];
    UITouch* touch0 = [bothTouches objectAtIndex: 0];
    UITouch* touch1 = [bothTouches objectAtIndex: 1];
    return [self distanceFromPoint: [touch0 locationInView: self] toPoint: [touch1 locationInView: self]];
  }
  return 0.0;
}

- (CGFloat)angleFromPoint:(CGPoint)first toPoint:(CGPoint)second
{
	CGFloat height = second.y - first.y;
	CGFloat width = first.x - second.x;
	CGFloat rads = atan2 (height, width);
	return rads;
}

- (float) angleBetweenTouches: (NSSet*) touches
{
  if (touches.count == 2) {
    NSArray* bothTouches = [touches allObjects];
    UITouch* touch0 = [bothTouches objectAtIndex: 0];
    UITouch* touch1 = [bothTouches objectAtIndex: 1];
    // order the touches by hash value so we always use the touches in the same order when calculating angle
    if ([touch0 hash] > [touch1 hash]) {
      UITouch* temp = touch0;
      touch0 = touch1;
      touch1 = temp;
    }
    return [self angleFromPoint: [touch0 locationInView: self] toPoint: [touch1 locationInView: self]];
  }
  return 0.0;
}

- (CGPoint) midpointBetweenTouches: (NSSet*) touches
{
  CGPoint midpoint;
  NSArray* bothTouches = [touches allObjects];
  UITouch* touch0 = [bothTouches objectAtIndex: 0];
  UITouch* touch1 = [bothTouches objectAtIndex: 1];
  CGPoint location0 = [touch0 locationInView: self];
  CGPoint location1 = [touch1 locationInView: self];
  // calculate the point midway between the two touch points
  midpoint.x = (location0.x + location1.x) / 2;
  midpoint.y = (location0.y + location1.y) / 2;
  return midpoint;
}

- (void) dumpViewport: (ON_Viewport&) v completed: (double) percent
{
  double lens = 0.0;
  v.GetCamera35mmLenseLength( &lens );
  
  DLog (@"CameraLocation %#8.3f %#8.3f %#8.3f TargetPoint %#8.3f %#8.3f %#8.3f CameraUp %#8.3f %#8.3f %#8.3f lens %#8.3f", v.CameraLocation().x, v.CameraLocation().y, v.CameraLocation().z, v.TargetPoint().x, v.TargetPoint().y, v.TargetPoint().z, v.CameraUp().x, v.CameraUp().y, v.CameraUp().z, lens);
  
  ON_3dVector cam2TargetDir = v.CameraDirection() - v.TargetPoint();
  ON_3dVector camDir = v.CameraDirection();
  
  DLog (@"CameraDir %#8.3f %#8.3f %#8.3f DirToTarget %#8.3f %#8.3f %#8.3f Cam2TgtDist %#8.3f completed: %g", camDir.x, camDir.y, camDir.z, cam2TargetDir.x, cam2TargetDir.y, cam2TargetDir.z, v.CameraLocation().DistanceTo(v.TargetPoint()), percent);
  
  double target_frus_left, target_frus_right, target_frus_bottom, target_frus_top, target_frus_near, target_frus_far;
  v.GetFrustum( &target_frus_left, &target_frus_right, &target_frus_bottom, &target_frus_top, &target_frus_near, &target_frus_far );
  //  DLog (@"left %#8.3f right %#8.3f bottom %#8.3f top %#8.3f near %#8.3f far %#8.3f", target_frus_left, target_frus_right, target_frus_bottom, target_frus_top, target_frus_near, target_frus_far);
}

#pragma mark ---- rotate helpers ----

- (void) rotateView: (ON_Viewport&) viewport
               axis: (const ON_3dVector&) axis
             center: (const ON_3dPoint&) center
              angle: (double) angle
{
	ON_Xform rot;
	ON_3dPoint camLoc;
	ON_3dVector camY, camZ;
  
	rot.Rotation( angle, axis, center );
  
	if ( !viewport.GetCameraFrame( camLoc, NULL, camY, camZ ) )
		return;
  
	camLoc = rot*camLoc;
	camY   = rot*camY;
	camZ   = -(rot*camZ);
  
	viewport.SetCameraLocation( camLoc );
	viewport.SetCameraDirection( camZ );
	viewport.SetCameraUp( camY );
  
	[ self setNeedsDisplay ];
}


- (void) rotateLeftRight: (ON_Viewport&) viewport angle: (double) angle
{
	// ON_3dVector axis = ON_zaxis; // rotate camera about world z axis (z up feel)
	ON_3dVector axis = ON_zaxis; // rotate camera about world y axis (u up feel)
  
	ON_3dPoint center;
	if ( m_model )
		center = m_view.m_target;
	else
		viewport.GetFrustumCenter( center );
	[ self rotateView: viewport axis:axis center:center angle:angle ];
}


- (void) rotateUpDown: (ON_Viewport&) viewport angle: (double) angle
{
	// rotates camera around the screen x axis
	ON_3dVector camX;
	ON_3dPoint center;
	if ( m_model )
		center = m_view.m_target;
	else
		viewport.GetFrustumCenter( center );
	viewport.GetCameraFrame( NULL, camX, NULL, NULL );
	[ self rotateView: viewport axis:camX center:center angle:angle ];
}

#pragma mark ---- animate viewport restore ----

// perform one step of the restore view animation
- (void) animateRestoreView
{
  uint64_t restoreViewCurrentTime = [self nanosecondTime];
  double percentCompleted = (double)(restoreViewCurrentTime-restoreViewStartTime)/restoreViewTotalTime;
  if (percentCompleted > 1) {
    // Animation is completed. Perform one last draw.
    percentCompleted = 1;
    inAnimatedRestoreView = false;
    self.userInteractionEnabled = true;
    atInitialPosition = ! startRestoreAtInitialPosition;
    [self stopAnimation];
  }
  
  // Get some data from the starting view
  ON_3dPoint source_target = restoreViewStartViewport.TargetPoint();
  const ON_3dPoint& source_camera = restoreViewStartViewport.CameraLocation();
  double source_distance = source_camera.DistanceTo(source_target);
  ON_3dVector source_up = restoreViewStartViewport.CameraUp();
  source_up.Unitize();

  // Get some data from the ending view
  const ON_3dPoint& target_target = restoreViewFinishViewport.TargetPoint();
  ON_3dPoint target_camera = restoreViewFinishViewport.CameraLocation();
  double target_distance = target_camera.DistanceTo(target_target);
  ON_3dVector target_camera_dir = target_camera - target_target;
  ON_3dVector target_up = restoreViewFinishViewport.CameraUp();
  target_up.Unitize();

  // Adjust the target camera location so that the starting camera to target distance
  // and the ending camera to target distance are the same.  Doing this will calculate
  // a constant rotational angular momentum when tweening the camera location.
  // Further down we independently tween the camera to target distance.
  target_camera_dir.Unitize();
  target_camera_dir *= source_distance;
  target_camera = target_camera_dir + target_target;

  // calculate interim viewport values
  double frame_distance = CosInterp( source_distance, target_distance, percentCompleted );

  ON_3dPoint frame_target;
  frame_target.x = CosInterp( source_target.x, target_target.x, percentCompleted );
  frame_target.y = CosInterp( source_target.y, target_target.y, percentCompleted );
  frame_target.z = CosInterp( source_target.z, target_target.z, percentCompleted );
  
  ON_3dPoint frame_camera = ON_origin + Slerp( source_camera - ON_origin, target_camera - ON_origin, percentCompleted );
  ON_3dVector frame_camera_dir = frame_camera - frame_target;

  // adjust the camera location along the camera direction vector to preserve the target location and the camera distance
  frame_camera_dir.Unitize();
  frame_camera_dir *= frame_distance;  
  frame_camera = frame_camera_dir + frame_target;

  ON_3dVector frame_up = Slerp( source_up, target_up, percentCompleted );;
  
  if (percentCompleted >= 1) {
    // put the last redraw at the exact end point to eliminate any rounding errors
    [self setTarget: restoreViewFinishViewport.TargetPoint() cameraLocation: restoreViewFinishViewport.CameraLocation() cameraUp: restoreViewFinishViewport.CameraUp()];
  }
  else {
    [self setTarget: frame_target cameraLocation: frame_camera cameraUp: frame_up];
  }
  [self setFrustum: m_view.m_vp boundingBox: [rhinoModel boundingBox]];

  [self setNeedsDisplay];
  
  if (!inAnimatedRestoreView) {
    // RhinoApp.fastDrawing is still enabled and we just scheduled a draw of the model at the final location.
    // This entirely completes the animation. Now schedule one more redraw of the model with fastDrawing disabled
    // and this redraw will be done at exactly the same postion.  This prevents the final animation frame
    // from jumping to the final location because the final draw will take longer with fastDrawing disabled.
    [self performSelector: @selector(redrawSlow) withObject: nil afterDelay: 0.05];
  }
}

- (void) startRestoreViewTo: (ON_Viewport&) targetPosition
{
  inAnimatedRestoreView = true;
  RhinoApp.fastDrawing = YES;

  self.userInteractionEnabled = false;
  restoreViewStartTime = [self nanosecondTime];
  restoreViewTotalTime = 1000000000.0 / 2;    // finish in .5 seconds

  // start from current position
  restoreViewStartViewport = m_view.m_vp;
  restoreViewStartViewport.SetTargetPoint(m_view.m_target);
    
  restoreViewFinishViewport = targetPosition;
  
  // fix frustum aspect to match current screen aspect
  int port_left, port_right, port_bottom, port_top;
  m_view.m_vp.GetScreenPort( &port_left, &port_right, &port_bottom, &port_top, NULL, NULL );
  const int port_width  = abs(port_right - port_left);
  const int port_height = abs(port_top - port_bottom);
  const double port_aspect = ((double)port_width)/((double)port_height);
  restoreViewFinishViewport.SetFrustumAspect( port_aspect );

  [self startAnimation];
}

- (void) redrawSlow
{
  RhinoApp.fastDrawing = NO;
  [self setNeedsDisplay];
}

#pragma mark ---- view change ----

// move camera in xy plane
- (void) mouseLateralDollyFromPoint: (CGPoint) mouse0 toPoint: (CGPoint) mouse1
{
  int port_left, port_right, port_bottom, port_top;
  double frus_left, frus_right, frus_bottom, frus_top, frus_near;
  double dx, dy, s;
  
  m_view.m_vp.GetScreenPort(&port_left,&port_right,&port_bottom,&port_top);
  m_view.m_vp.GetFrustum(&frus_left,&frus_right,&frus_bottom,&frus_top,&frus_near);
  
  ON_3dPoint camLoc = m_view.m_vp.CameraLocation();
  ON_3dPoint target = m_view.m_target;
  
  ON_Xform s2c;
  m_view.m_vp.GetXform( ON::screen_cs, ON::clip_cs,  s2c );
  s2c = m_view.m_vp.ClipModInverseXform()*s2c;
  ON_3dPoint s0( mouse0.x, mouse0.y, 0.0 );
  ON_3dPoint s1( mouse1.x, mouse1.y, 0.0 );
  ON_3dPoint c0 = s2c*s0;
  ON_3dPoint c1 = s2c*s1;
  dx = 0.5*(c1.x - c0.x);
  dy = 0.5*(c1.y - c0.y);  
  dx *= (frus_right-frus_left);
  dy *= (frus_top-frus_bottom);
  
  if ( m_view.m_vp.Projection() == ON::perspective_view ) {
    s = target.DistanceTo( camLoc )/m_view.m_vp.FrustumNear();
    dx *= s;
    dy *= s;
  }
  
  ON_3dVector dolly_vector = dx*m_view.m_vp.CameraX() + dy*m_view.m_vp.CameraY();
  
  m_view.m_vp.SetTargetPoint(target - dolly_vector);
  m_view.m_target = target - dolly_vector;
  m_view.m_vp.SetCameraLocation( camLoc - dolly_vector );
}


- (void) mouseRotate: (CGPoint) location
{
	int port_left, port_right, port_top, port_bottom;
	m_view.m_vp.GetScreenPort( &port_left, &port_right, &port_bottom, &port_top, NULL, NULL );
	const int scr_width  = port_right - port_left;
  
	float f = ON_PI/scr_width;
	float horzDiff = gDollyRotateStartPoint.x - location.x;
	[self rotateLeftRight: m_view.m_vp angle: horzDiff * f];
	float vertDiff = gDollyRotateStartPoint.y - location.y;
	[self rotateUpDown: m_view.m_vp angle: vertDiff * f];
  
	gDollyRotateStartPoint = location;
}


- (bool) magnify: (double) magnification_factor 
          method: (int) method 
           point: (const CGPoint*) fixed_screen_point
{
  
  // method =
  // 0 performs a "dolly" magnification by moving the 
  //   camera along the camera direction vector so that
  //   the amount of the screen subtended by an object
  //   changes.
  // 1 performs a "zoom" magnification by adjusting the
  //   "lens" angle
  
  ON_3dmView& m_v = m_view;
  
  if( m_v.m_bLockedProjection )
    return false;
  
  
  int port_top, port_bottom, port_left, port_right;    
  m_v.m_vp.GetScreenPort( &port_left, &port_right, &port_bottom, &port_top, NULL, NULL );
  const int scr_width  = port_right - port_left;
  const int scr_height = port_bottom - port_top;
  
  
  //05_15_2008 TimH.  Fix for RR34223.  Check the value of these variables before using them with % below.
  if ( 1 > scr_width || 1 > scr_height)
    return false;
  
  CGPoint temp_fixed_screen_point;
  
  // move camera towards target to magnify
  bool bPushProjection = ( 0 == fixed_screen_point );
  if ( magnification_factor > 0.0 ) 
  {
    
    // olde method:
    // If the fixed point is not in the viewport, then ignore it.
    if ( fixed_screen_point )
    {
      if (   fixed_screen_point->x <= 0 
          || fixed_screen_point->x >= scr_width-1
          || fixed_screen_point->y <= 0 
          || fixed_screen_point->y >= scr_height-1 )
      {
        fixed_screen_point = 0;
      }
    }
    
    // get current frustum geometry
    double frus_left, frus_right, frus_bottom, frus_top, frus_near, frus_far;
    m_v.m_vp.GetFrustum( &frus_left, &frus_right, &frus_bottom, &frus_top, 
                        &frus_near, &frus_far );
    
    double w0 = frus_right - frus_left;
    double h0 = frus_top - frus_bottom;
    double d = 0.0;
    
    if ( m_v.m_vp.Projection() == ON::perspective_view && method == 0) 
    {
      const double min_target_distance = 1.0e-6;
      // dolly camera towards target point
      // 11 Sep 2002 - switch to V2 target based "zoom"
      ON_3dVector camZ = m_v.m_vp.CameraZ();
      ON_3dPoint camLoc = m_v.m_vp.CameraLocation();
      ON_3dPoint target = m_v.m_target;
      double target_distance = (camLoc - target)*camZ;
      if ( target_distance >= 0.0 )
      {
        double delta = (1.0 - 1.0/magnification_factor)*target_distance;
        if ( target_distance-delta > min_target_distance )
        {
          camLoc = camLoc - delta*camZ;
          m_v.m_vp.SetCameraLocation( camLoc );
          if ( fixed_screen_point )
          {
            d = target_distance/frus_near;
            w0 *= d;
            h0 *= d;
            d = (target_distance-delta)/target_distance;
          }
        }
      }
    }
    else  // parallel proj or "true" zoom
    {
      // apply magnification to frustum
      d = 1.0/magnification_factor;
      frus_left   *= d;
      frus_right  *= d;
      frus_bottom *= d;
      frus_top    *= d;
      m_v.m_vp.SetFrustum( frus_left, frus_right, frus_bottom, frus_top, frus_near, frus_far );
    }
    
    if ( fixed_screen_point && d != 0.0 ) 
    {
      // lateral dolly to keep fixed_screen_point 
      // in same location on screen
      
      
      // 22 May 2006 Dale Lear
      //     I added this block to handle non-uniform viewport scaling
      //     to fix RR 21165.
      ON_3dVector scale(1.0,1.0,0.0);
      m_v.m_vp.GetViewScale(&scale.x,&scale.y);
      
      double fx = ((double)fixed_screen_point->x)/((double)scr_width);
      double fy = ((double)fixed_screen_point->y)/((double)scr_height);
      double dx = (0.5 - fx)*(1.0 - d)*w0/scale.x;
      double dy = (fy - 0.5)*(1.0 - d)*h0/scale.y;
      ON_3dVector dolly_vector = dx*m_v.m_vp.CameraX() + dy*m_v.m_vp.CameraY();
      ON_3dPoint camLoc = m_v.m_vp.CameraLocation();
      ON_3dPoint target = m_v.m_target;
      m_v.m_target = target - dolly_vector;
      m_v.m_vp.SetCameraLocation( camLoc - dolly_vector );
    }
  }
  return true;
}

- (void) zoomExtents
{
  lastPosition = m_view.m_vp;
  ON_Viewport targetPosition = m_view.m_vp;
  
  double half_angle = 15*ON_PI/180.0;
  targetPosition.Extents( half_angle, m_bbox );
  targetPosition.SetTargetPoint(m_bbox.Center());
  
  [self startRestoreViewTo: targetPosition];
}

- (void) zoomHome
{
  lastPosition = m_view.m_vp;
  [self startRestoreViewTo: initialPosition];
}

#pragma mark ---- double tap tests ----

- (void) testDoubleTapBegin: (UITouch*) touch withEvent: (UIEvent *)event
{
  CGPoint location = [touch locationInView: self];

 // check for double tap
  if (doubleTapState == 0) {
    // Start of first tap.
    // Remember if the double tap started when the view was at the initial position.
    // Slight movements while tapping might take us off the initial position by the time the double tap is completed.
    startRestoreAtInitialPosition = atInitialPosition;
  }
  else if (doubleTapState == 2) {
    // start of second tap
    NSTimeInterval elapsed = [event timestamp] - doubleTapTimestamp;
    if (elapsed > 0.3)
      doubleTapState = 0;     // too long a tap; start over
    else
      [[self delegate] hideBars: self];
  }
 doubleTapState++;
 doubleTapTimestamp = [touch timestamp];
 doubleTapLocation = location;
}

- (BOOL) testDoubleTapEnd: (UITouch*) touch withEvent: (UIEvent *)event
{
  BOOL sawDoubleTap = NO;
  CGPoint location = [touch locationInView: self];
  
  // ensure the start and end tap points are close together
  if ([self distanceFromPoint: location toPoint: doubleTapLocation] > 35.0)
    doubleTapState = 0;   // dragged too much during the tap; start over
  
  NSTimeInterval elapsed = [event timestamp] - doubleTapTimestamp;
  if (elapsed > 0.25)
    doubleTapState = 0;     // too long a tap; start over
  
  if (doubleTapState == 1) {
    // end of first tap
    [[self delegate] startSingleTapTimer];
    doubleTapState++;       // continue to next state
  }
  else if (doubleTapState == 3) {
    // end of second tap
    ON_Viewport targetPosition;
    if (startRestoreAtInitialPosition) {
      // animate from current position (which is initial position) back to last position
      targetPosition = lastPosition;
    }
    else {
      // animate from current position to initial position
      targetPosition = initialPosition;
      lastPosition = m_view.m_vp;
    }
    sawDoubleTap = YES;
    [self startRestoreViewTo: targetPosition];
    doubleTapState = 0;
  }
  else
    doubleTapState = 0;
  
  doubleTapTimestamp = [event timestamp];
  return sawDoubleTap;
}


- (void) setTarget: (ON_3dPoint) target_location cameraLocation: (ON_3dPoint) camera_location cameraUp: (ON_3dVector) camera_up
{
//  DLog (@"  ");
//  DLog (@"m_view.m_vp.TargetPoint() %g %g %g", m_view.m_vp.TargetPoint().x, m_view.m_vp.TargetPoint().y, m_view.m_vp.TargetPoint().z);
//  DLog (@"m_view.m_vp.CameraLocation() %g %g %g", m_view.m_vp.CameraLocation().x, m_view.m_vp.CameraLocation().y, m_view.m_vp.CameraLocation().z);
  
  ON_3dVector camera_direction = target_location - camera_location;
  camera_direction.Unitize();

  if ( !camera_direction.IsTiny() )
  {
    ON_3dVector camera_dir0 = -m_view.m_vp.CameraZ();
    ON_3dVector camera_y = m_view.m_vp.CameraY();
    double tilt_angle = 0;

    m_view.m_vp.SetCameraLocation(camera_location);
    m_view.m_vp.SetCameraDirection(camera_direction);
    
    BOOL rc = false;
    
    rc = m_view.m_vp.SetCameraUp(camera_up);
    
    if ( !rc)
    {
      rc = m_view.m_vp.SetCameraUp(camera_y);
      camera_up = camera_y;
    }
    
    if ( !rc )
    {
      ON_3dVector rot_axis = ON_CrossProduct( camera_dir0, camera_direction );
      double sin_angle = rot_axis.Length();
      double cos_angle = camera_dir0*camera_direction;
      ON_Xform rot;
      rot.Rotation( sin_angle, cos_angle, rot_axis, ON_origin );
      camera_up = rot*camera_y;
      rc = m_view.m_vp.SetCameraUp(camera_up);
    }
    
    if ( rc )
    {
      // Apply tilt angle to new camera and target location
      if ( fabs(tilt_angle) > 1.0e-6)
      {
        ON_Xform rot;
        rot.Rotation( tilt_angle, -camera_dir0, camera_location);
        camera_up  = rot*camera_up;
        rc = m_view.m_vp.SetCameraUp(camera_up);
      }
      
      if ( rc)
      {
        m_view.m_target = target_location;
        m_view.m_vp.SetTargetPoint(target_location);
      }
    }
  }
//  DLog (@"m_view.m_vp.TargetPoint() %g %g %g", m_view.m_vp.TargetPoint().x, m_view.m_vp.TargetPoint().y, m_view.m_vp.TargetPoint().z);
//  DLog (@"m_view.m_vp.CameraLocation() %g %g %g", m_view.m_vp.CameraLocation().x, m_view.m_vp.CameraLocation().y, m_view.m_vp.CameraLocation().z);
}


#pragma mark ---- Stereo ----


- (void) startStereoMode
{
  RhinoApp.fastDrawing = NO;    // turn off antialiased drawing
  [self setNeedsDisplay];       // request one anti-aliased render
}


- (void) stopStereoMode
{
  RhinoApp.fastDrawing = NO;    // turn off antialiased drawing
  [self setNeedsDisplay];       // request one anti-aliased render
}


- (void) setStereoMode: (BOOL) newMode
{
  stereoMode = newMode;
  if (stereoMode) {
    [self startStereoMode];
  }
  else {
    [self stopStereoMode];
  }
}

#pragma mark ---- screen capture ----

- (void) setNeedsImageCapturedForDelegate: (id) aDelegate
{
  [renderer setNeedsImageCapturedForDelegate: aDelegate];
  [self setNeedsDisplay];
}

#pragma mark ---- drawing ----


- (void) clearView
{
  [renderer clearView];
}


- (void) drawView:(id)sender
{
  [super drawView: sender];
  
  // Change the projection matrix if the iPhone has been rotated
  CGRect bounds = [self bounds];
  if (!CGRectEqualToRect (bounds, lastBounds)) {
    [self reshape];
    lastBounds = bounds;
  }
  
  if (m_model && [rhinoModel isDownloaded] && [rhinoModel meshesInitialized]) {
    if (inAnimatedRestoreView)
      [self animateRestoreView];
    
    [self setFrustum: m_view.m_vp boundingBox: [rhinoModel boundingBox]];
    
    if (stereoMode) {
      [anaglyph calcAsymmetricView: m_view.m_vp target:m_view.m_target];
      [renderer renderModel: rhinoModel inLeftEye: [anaglyph LeftEye] inRightEye: [anaglyph RightEye]];
    }
    else {
      [renderer renderModel: rhinoModel inViewport: m_view.m_vp];
    }
  }
  else
    [renderer clearView];
}

- (UIImage*) imageFromView
{
  return [renderer capturedImage];
}

// capture a screen shot of the current model at full screen resolution and current orientation with a transparent background
- (UIImage*) previewImage
{
  return [renderer renderPreview: rhinoModel inViewport: m_view.m_vp];
}

- (void)displayLayer: (CALayer*) layer
{
  [super displayLayer: layer];
  [self drawView: self];
}

#pragma mark ---- Notifications ----

// sent by our controller
- (void) viewDidAppear
{
  // initialize current device orientation (needed to adjust compass heading)
  orientation = [[UIDevice currentDevice] orientation];
}

// sent by our controller
- (void) viewWillDisappear
{
  [self stopAnimation];
}


#pragma mark ---- touch events ----

- (void)touchesBegan: (NSSet *)touches withEvent: (UIEvent *)event
{
  [[self delegate] cancelSingleTapTimer];

  NSSet* allTouches = [event touchesForView: self];
//  DLog (@"allTouches:%d", allTouches.count);

  // ignore more than two touches
  if (allTouches.count > 2) {
    moreThanTwoTouches = true;
    doubleTapState = 0;   // more than two touches cancel any double tap checking
    return;
  }

  if (allTouches.count == 2)
  {
    doubleTapState = 0;   // two touches cancel any double tap checking
    [[self delegate] hideBars: self];

//    DLog (@"start double touch");
    // there are now a total of two touches.  Switch to two touch detect mode
    gRotate = false; 
    gTwoTouch = true;

    // started two touches.
    twoTouchStartPoint = [self midpointBetweenTouches: allTouches];
    twoTouchDistance = [self distanceBetweenTouches: allTouches];
    twoTouchAngle = [self angleBetweenTouches: allTouches];
    gDollyRotateStartPoint = twoTouchStartPoint;
  }

  else if (allTouches.count == 1) {
    UITouch* touch = [touches anyObject];
    CGPoint location = [touch locationInView: self];

    [self testDoubleTapBegin: touch withEvent: event];
        
    int port_top, port_bottom, port_left, port_right;    
		m_view.m_vp.GetScreenPort( &port_left, &port_right, &port_bottom, &port_top, NULL, NULL );
		const int scr_width  = port_right - port_left;
		const int scr_height = port_bottom - port_top;
    
    gRotate = true; 
    
    gDollyRotateStartPoint = location;
    oneTouchStartPoint = location;

    // capture camera orientation and target when rotate starts
    if ( m_model )
      rotateCenter = m_view.m_target;
    else
      m_view.m_vp.GetFrustumCenter( rotateCenter );
    m_view.m_vp.GetCameraFrame( NULL, rotateXAxis, rotateYAxis, NULL );
    rotateHorzAngle = rotateVertAngle = 0.0;
  }
}


- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
  RhinoApp.fastDrawing = YES;
  
  // ignore everything while more than two touches
  if (moreThanTwoTouches)
    return;
  
  UITouch *touch = [touches anyObject];
  CGPoint location = [touch locationInView: self];
//  DLog (@"moved to %g, %g", location.x, location.y);

  if (gTwoTouch) {
    NSSet* allTouches = [event touchesForView: self];
    if (allTouches.count == 2) {
      CGPoint newTwoTouchPoint = [self midpointBetweenTouches: allTouches];
      float newTwoTouchAngle = [self angleBetweenTouches: allTouches];
      
      // do drag
      [self mouseLateralDollyFromPoint: twoTouchStartPoint toPoint: newTwoTouchPoint];
      
      // do zoom
      float newTouchDistance = [self distanceBetweenTouches: allTouches];
      CGFloat power = newTouchDistance / twoTouchDistance;
      twoTouchDistance = newTouchDistance;
      [self magnify: power method: 0 point: &twoTouchStartPoint];
      twoTouchStartPoint = newTwoTouchPoint;    // NEW !!
      
      // do rotate
      if (0 /* NEVER */) {
        ON_3dVector camZ;
        m_view.m_vp.GetCameraFrame( NULL, NULL, NULL, camZ );
        ON_3dPoint center;
        if ( m_model )
          center = m_view.m_target;
        else
          m_view.m_vp.GetFrustumCenter( center );
        float twoTouchAngleDelta = twoTouchAngle - newTwoTouchAngle;
        [ self rotateView: m_view.m_vp axis: camZ center: center angle: twoTouchAngleDelta ];
        twoTouchAngle = newTwoTouchAngle;
      }
      [self setNeedsDisplay];
    }
  }
  else if (gRotate) {
    if ([self distanceFromPoint: location toPoint: oneTouchStartPoint] > 15.0) {
      // not single tap
      [[self delegate] hideBars: self];
    }
    [self mouseRotate: location];
    gDollyRotateStartPoint = location;
    [self setNeedsDisplay];
  }
  
  atInitialPosition = false;    // no longer at initial position
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{  
  NSSet* allTouches = [event touchesForView: self];
  int touchesLeft = allTouches.count-touches.count;
  
  if (touchesLeft > 0)
    RhinoApp.fastDrawing = YES;   // keep drawing fast

//  DLog (@"allTouches:%d touchesLeft:%d", allTouches.count, touchesLeft);

  gRotate = false;
  gTwoTouch = false;

  if (touchesLeft == 1) {
    // one of two fingers was lifted
    if (twoTouchDistance < 100) {
      // The two fingers were close together.  Perhaps the framework thinks one finger has lifted when in fact
      // two fingers are still down and they are just very close together.  If we treat this as a single touch
      // the action becomes very jerky.  We'll cancel any further touch activity by setting moreThanTwoTouches true.
      moreThanTwoTouches = true;
    }
    else {
//      DLog (@"end double touch, switch to single touch, twoTouchDistance %g", twoTouchDistance);
      gRotate = true; 
      // find the single touch that is left and initialize a rotate with its location
      for (UITouch* touch in allTouches) {
        if (![touches containsObject: touch]) {
          CGPoint location = [touch locationInView: self];
          gDollyRotateStartPoint = location;
        }
      }
    }
  }
  
  // The double tap detection offered by UIEvent is not sufficient when using multi-touch events.
  // We perform our own checks for a double tap.
  BOOL sawDoubleTap = NO;
  if (touchesLeft == 0 && touches.count == 1) {
    // look for double tap
    UITouch* touch = [touches anyObject];
    sawDoubleTap = [self testDoubleTapEnd: touch withEvent: event];
  }
  
  if (touchesLeft == 0) {
    if (!sawDoubleTap)
      [self performSelector: @selector(redrawSlow) withObject: nil afterDelay: 0.05];
    
    moreThanTwoTouches = false;
    gRotate = false; 
    gTwoTouch = false;
//    DLog (@"end all touches");
  }
  [self setNeedsDisplay];
}


- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
  RhinoApp.fastDrawing = 0;
  [self setNeedsDisplay];

  moreThanTwoTouches = false;
  doubleTapState = 0;
}


- (void) orientationChanged: (NSNotification*) notification
{
  UIDeviceOrientation newOrientation = [[UIDevice currentDevice] orientation];
  switch (newOrientation) {
    case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
    case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
    case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
    case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
      orientation = newOrientation;
      break;
    case UIDeviceOrientationFaceUp:              // Device oriented flat, face up
    case UIDeviceOrientationFaceDown:            // Device oriented flat, face down
    case UIDeviceOrientationUnknown:
    default:
      // do nothing
      break;
  }
}

@end
