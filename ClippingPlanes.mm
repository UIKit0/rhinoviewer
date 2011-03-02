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

#import "ClippingPlanes.h"



static 
void GetBoundingBoxNearFarHelper(
                                 const ON_BoundingBox& bbox, 
                                 ON::view_projection   projection,
                                 const ON_3dVector&    camLoc, 
                                 const ON_3dVector&    camZ,
                                 double*               box_near, 
                                 double*               box_far)
{
  double n = 0.005;
  double f = 1000.0;
  if (bbox.IsValid())
  {
    ON_3dPoint p;
    double d;
    bool bFirstPoint = true;
    int i,j,k;
    
    for ( i = 0; i < 2; i++ )
    {
      p.x = bbox[i].x;
      for ( j = 0; j < 2; j++)
      {
        p.y = bbox[j].y;
        for ( k = 0; k < 2; k++)
        {
          p.z = bbox[k].z;
          d = (camLoc-p)*camZ;
          if ( bFirstPoint )
          {
            n=d;
            f=d;
            bFirstPoint=false;
          }
          else
          {
            if (d < n)
              n = d;
            else if(d > f)
              f = d;
          }
        }
      }
    }
    
    if ( !ON_IsValid(n) || !ON_IsValid(f) || f < n )
    {
      n = 0.005;
      f = 1000.0;
    }
    else
    {
      // Bump things out just a bit so objects right on 
      // the edge of the bounding box do not land
      // on the near/far plane.
      if ( ON::perspective_view == projection )
      {
        // perspective projection
        if ( f <= ON_ZERO_TOLERANCE )
        {
          // everything is behind camera
          n = 0.005;
          f = 1000.0;
        }
        else if ( n <= 0.0 )
        {
          // grow f and handle n later
          f *= 1.01;
        }
        else if ( f <= n + ON_SQRT_EPSILON*n )
        {
          // 0 < n and f is nearly equal to n
          n *= 0.675;
          f *= 1.125;
          if ( f < 1.0e-6 )
            f = 1.0e-6;
        }
        else 
        {
          n *= 0.99;
          f *= 1.01;
        }
      }
      else // parallel projection
      {
        // 14 May 2003 Dale Lear RR 10601
        // with a parallel projection, we just add a 5% buffer.
        // The next step will move the camera back if n is negative.
        d = 0.05*fabs(f-n);
        if ( d < 0.5 )
          d = 0.5;
        n -= d;
        f += d;
      }
    }
  }
  
  if ( box_near )
    *box_near = n;
  if ( box_far )
    *box_far = f;
}

/////////////////////////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////////////////////////


static void NegativeNearClippingHelper( double& near_dist, double& far_dist, ON_Viewport& vp )
{
  double n = near_dist;
  double f = far_dist;
  double min_near_dist = vp.PerspectiveMinNearDist();
  if ( !ON_IsValid(min_near_dist) || min_near_dist < 1.0e-6 )
    min_near_dist = 1.0e-6;
  if ( ON::parallel_view == vp.Projection() && n < min_near_dist )
  {
    // move camera back in ortho projection so everything shows
    double d = 1.00001*min_near_dist - n;
    if ( d < 0.005 )
      d = 0.005;
    n += d;
    f  += d;
    if (   !ON_IsValid(d)
        || d <= 0.0
        || !ON_IsValid(n)
        || !ON_IsValid(f)
        || n < min_near_dist 
        || f <= n
        )
    {
      // Just give up but ... refuse to accept garbage
      n = 0.005;
      f  = 1000.0;
    }
    else
    {
      ON_3dPoint new_loc = vp.CameraLocation() + d*vp.CameraZ();          
      vp.SetCameraLocation( new_loc );
    }
    near_dist = n;
    far_dist = f;
  }
}

/////////////////////////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////////////////////////

static void CalcClippingPlanesHelper( double& near_dist, double& far_dist, ON_Viewport& vp )
{
  // The only thing this function should do is make sure ortho cameras are
  // moved so near is > 0.  Everything else should be considered and emergency
  // fix for garbage input.
  double n = near_dist;
  double f = far_dist;
  double min_near_dist = vp.PerspectiveMinNearDist();
  if ( !ON_IsValid(min_near_dist) || min_near_dist < 1.0e-6 )
    min_near_dist = 1.0e-6;
  
  if ( ON_IsValid(n) && ON_IsValid(f) )
  {
    ::NegativeNearClippingHelper(n,f,vp);
    if ( n < min_near_dist )
      n = min_near_dist;
    if ( f <= 1.00001*n )
      f = 10.0 + 100.0*n;
  }
  else
  {
    // If being nice didn't work - refuse to accept garbage
    n = 0.005;
    f = 1000.0;
  }
  
  near_dist = n;
  far_dist = f;
}

/////////////////////////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////////////////////////

bool CalcClippingPlanes(ON_Viewport& vp, ClippingInfo& clipping)
{
  ON::view_projection projection = vp.Projection();
  
  // iCalcBoundingBox() has set clipping.bbox and it cannot
  // be changed or ignored.
  ::GetBoundingBoxNearFarHelper(
                                clipping.bbox, 
                                projection,
                                vp.CameraLocation(),
                                vp.CameraZ(), 
                                &clipping.bbox_near,
                                &clipping.bbox_far 
                                );
  
  // Do sanity checks and update ON_Viewport frustum if it uses
  // parallel projection and near <= 0.0
  ::CalcClippingPlanesHelper(clipping.bbox_near,clipping.bbox_far,vp);
  
  // Set target_dist
  clipping.target_dist = (vp.CameraLocation() - vp.TargetPoint())*vp.CameraZ();
  if ( !ON_IsValid(clipping.target_dist) )
    clipping.target_dist = 0.5*(clipping.bbox_near + clipping.bbox_far);
  
  return true;
}

/////////////////////////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////////////////////////

bool iCalcClippingPlanes (ON_Viewport& vp, ClippingInfo& m_Clipping)
{
  // Initialize m_Clipping frustum info. 
  // (left,right,top,bottom are not used but should be initialized).
  const ON::view_projection projection = vp.Projection();
  vp.GetFrustum(
                &m_Clipping.left,      &m_Clipping.right,
                &m_Clipping.bottom,    &m_Clipping.top,
                &m_Clipping.bbox_near, &m_Clipping.bbox_far
                );
  m_Clipping.min_near_dist     = vp.PerspectiveMinNearDist();
  m_Clipping.min_near_over_far = vp.PerspectiveMinNearOverFar();
  m_Clipping.target_dist = (vp.CameraLocation() - vp.TargetPoint())*vp.CameraZ();
  
  // Call virtual function that looks at m_Clipping.bbox and sets
  // m_Clipping.bbox_near and m_Clipping.bbox_far
  if ( !CalcClippingPlanes( vp, m_Clipping ) )
    return false;  
  
  if (    !ON_IsValid(m_Clipping.bbox_far) 
      || !ON_IsValid(m_Clipping.bbox_near)
      || m_Clipping.bbox_far <= m_Clipping.bbox_near
      || (ON::perspective_view == vp.Projection() && m_Clipping.bbox_near <= ON_ZERO_TOLERANCE)
      || (ON::perspective_view == vp.Projection() && m_Clipping.bbox_far > 1.0e16*m_Clipping.bbox_near)
      || m_Clipping.bbox_near > 1.0e30
      || m_Clipping.bbox_far  > 1.0e30
      )
  {
    //   The frustum near/far settings are nonsense.
    //   If you make a perspective projection matrix using 
    //   these numbers, then many opengl drivers crash.
    
    // Restore settings to something more sane
    vp.GetFrustum(
                  &m_Clipping.left,      &m_Clipping.right,
                  &m_Clipping.bottom,    &m_Clipping.top,
                  &m_Clipping.bbox_near, &m_Clipping.bbox_far
                  );
    m_Clipping.min_near_dist     = vp.PerspectiveMinNearDist();
    m_Clipping.min_near_over_far = vp.PerspectiveMinNearOverFar();
    m_Clipping.target_dist = (vp.CameraLocation() - vp.TargetPoint())*vp.CameraZ();
  }
  
  return true;
}


bool SetupFrustum (ON_Viewport& vp, const ClippingInfo&  clipping)
{
  vp.SetFrustumNearFar( vp.FrustumNear()*0.1, vp.FrustumFar()*10 );
  return true;
}

/////////////////////////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////////////////////////

bool iSetupFrustum (ON_Viewport& vp, ClippingInfo& m_Clipping)
{
  double    n0 = vp.FrustumNear();
  double    f0 = vp.FrustumFar();
  
  ClippingInfo m_SavedClipping = m_Clipping;
  vp.SetFrustumNearFar( 
                         m_Clipping.bbox_near, m_Clipping.bbox_far, 
                         m_Clipping.min_near_dist, m_Clipping.min_near_over_far, 
                         m_Clipping.target_dist 
                         );
  vp.GetFrustum(
                  &m_SavedClipping.left, &m_SavedClipping.right, 
                  &m_SavedClipping.bottom, &m_SavedClipping.top, 
                  &m_SavedClipping.bbox_near, &m_SavedClipping.bbox_far 
                  );
    
  // Next, set the values that the pipeline will actually use...  
  if ( !SetupFrustum( vp, m_Clipping ) )
    return false;
  
  return true;
}

