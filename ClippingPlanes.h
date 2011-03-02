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


struct ClippingInfo
{
  // CRhinoDisplayPipeline::iCalcBoundingBox sets
  // bbox.  Often it is too big, but generally contains
  // everything core Rhino knows needs to be drawn.
  ON_BoundingBox    bbox;
  
  // CRhinoDisplayPipeline::iCalcClippingPlanes sets 
  // min_near_dist and min_near_over_far based on 
  // video hardware capabilities.   If you want high 
  // quality display, make sure your code sets near 
  // and far so that
  //    bbox_near >= min_near_dist
  //    bbox_near >= min_near_over_far*bbox_far
  double            min_near_dist;
  double            min_near_over_far;
  
  // Rhino sets this to be the distance from the camera
  // to the target.  It can generally be ignored.
  // In situations where bbox_near and bbox_far are too
  // far apart, target_dist can be used as a hint about
  // what area of the frustum is the most important to
  // show.
  double            target_dist;
  
  // You can override the virtual function
  // CRhinoDisplayPipeline::CalcClippingPlanes() 
  // and adjust the values of
  //   m_Clipping.bbox_near
  //   m_Clipping.bbox_far
  // If you set them incorrectly, Rhino will ignore 
  // your request.
  //    bbox_near >  0
  //    bbox_far  >  bbox_near
  double            bbox_near;
  double            bbox_far;
  
  // These fields are set but not used.
  // Changing them does not change the
  // the view projection.
  double            left,right;
  double            top,bottom;
};



bool iCalcClippingPlanes (ON_Viewport& vp, ClippingInfo& m_Clipping);
bool iSetupFrustum (ON_Viewport& vp, ClippingInfo& m_Clipping);

