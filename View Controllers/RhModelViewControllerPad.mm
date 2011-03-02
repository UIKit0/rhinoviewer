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

//
// This class adds iPad specific behavior to the main view controller class RhModelViewController
//

#import "RhModelViewControllerPad.h"
#import "TransparentToolbar.h"



@implementation RhModelViewControllerPad


- (void)dealloc
{
  [topToolbar release];
  [super dealloc];
}


- (BOOL) barsHidden
{
  return self.navigationBar.alpha == 0;
}


- (void) preparationDidSucceed
{
  [super preparationDidSucceed];
  
  if (topToolbar == nil) {
    topToolbar = [[TransparentToolbar alloc] initWithFrame:CGRectMake(0, 0, 300, 45)];
    [topToolbar setBarStyle: UIBarStyleBlack];
    [topToolbar setTranslucent: YES];
    [topToolbar setTintColor: [UIColor clearColor]];
    [topToolbar setBackgroundColor: [UIColor clearColor]];
    [topToolbar setItems: topToolbarItems animated: NO];
  }
  self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView: topToolbar] autorelease];
}


- (void) hideBars: (id) sender
{
  UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
  
  [UIView beginAnimations: nil context: nil];
  [UIView setAnimationDuration: 0.25];
  [UIView setAnimationDelegate: self];
  self.navigationBar.alpha = 0;
  [UIView commitAnimations];
}


- (void) showBars
{
  [super showBars];
  self.navigationBar.alpha = 1;
}


- (void) updateStereoButton
{
  if (glView.stereoMode)
    [topToolbarItems replaceObjectAtIndex: stereoIndex withObject: stereoButton];
  else
    [topToolbarItems replaceObjectAtIndex: stereoIndex withObject: notStereoButton];
  [topToolbar setItems: topToolbarItems animated: NO];
}

@end
