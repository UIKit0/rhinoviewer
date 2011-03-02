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

#import "RhModelViewController.h"
#import "RhModelView.h"
#import "RhModel.h"


// forward declarations
@interface RhModelViewController ()
- (void) updateStereoButton;
@end


@implementation RhModelViewController

@synthesize glView, topToolbarItems, bottomToolbarItems, displayedModel;
@synthesize hidingTimer, singleTapTimer;


- (void) stopTimers
{
  [hidingTimer invalidate];
  self.hidingTimer = nil;
  [singleTapTimer invalidate];
  self.singleTapTimer = nil;
}


- (void)dealloc
{
  [self stopTimers];
  
  [displayedModel release];
  [stereoButton release];
  [notStereoButton release];
  [topToolbarItems release];
  [bottomToolbarItems release];
  [imageSheet release];
  [deleteSheet release];
    
  [glView release];

  [super dealloc];
}


// The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
    // Custom initialization
  }
  return self;
}


// iPhone bottom toolbar
- (void) initBottomToolbar
{
  if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPhone)
    return;

  // build the toolbar items
  self.bottomToolbarItems = [NSMutableArray array];
  
  stereoIndex = [bottomToolbarItems count];
  if (stereoButton == nil)
    stereoButton = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"stereo2.png"] style: UIBarButtonItemStylePlain target: self action: @selector(stereo:)];
  if (notStereoButton == nil)
    notStereoButton = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"stereo1.png"] style: UIBarButtonItemStylePlain target: self action: @selector(stereo:)];
  [bottomToolbarItems addObject: notStereoButton];
  if (glView.stereoMode)
    glView.stereoMode = NO;
  
  [bottomToolbarItems addObject: [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target:nil action: nil] autorelease]];
  
  UIButton* viewButton = [[[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"zoomExtents.png"] style: UIBarButtonItemStylePlain target: self action: @selector(zoomExtents:)] autorelease];
  [bottomToolbarItems addObject: viewButton];
}


- (UIBarButtonItem*) spacer
{
  UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFixedSpace target:nil action: nil];
  spacer.width = 25;
  return [spacer autorelease];
}

// iPad top toolbar
- (void) initTopToolbar
{
  if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad)
    return;
  
  // build the toolbar items
  self.topToolbarItems = [NSMutableArray array];
  
  [topToolbarItems addObject: [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target:nil action: nil] autorelease]];

  stereoIndex = [topToolbarItems count];
  if (stereoButton == nil)
    stereoButton = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"stereo2.png"] style: UIBarButtonItemStylePlain target: self action: @selector(stereo:)];
  if (notStereoButton == nil)
    notStereoButton = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"stereo1.png"] style: UIBarButtonItemStylePlain target: self action: @selector(stereo:)];
  [topToolbarItems addObject: notStereoButton];
  if (glView.stereoMode)
    glView.stereoMode = NO;
  
  [topToolbarItems addObject: [self spacer]];

  UIButton* viewButton = [[[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"zoomExtents.png"] style: UIBarButtonItemStylePlain target: self action: @selector(zoomExtents:)] autorelease];
  [topToolbarItems addObject: viewButton];
  
  UIBarButtonItem *edgeSpacer = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFixedSpace target:nil action: nil] autorelease];
  edgeSpacer.width = 10;
  [topToolbarItems addObject: edgeSpacer];
}

#pragma mark Showing and hiding navigation and toolbar

- (UINavigationBar*) navigationBar
{
  return RhinoApp.navigationController.navigationBar;
}

- (BOOL) barsHidden
{
  return [UIApplication sharedApplication].isStatusBarHidden;
}

- (void) hideBars: (id) sender
{
  [hidingTimer invalidate];
  self.hidingTimer = nil;

  UIApplication* application = [UIApplication sharedApplication];

  if (application.isStatusBarHidden)
    return;     // nothing to do
  
  [application setStatusBarHidden: YES withAnimation: UIStatusBarAnimationFade];

  [UIView beginAnimations: nil context: nil];
  [UIView setAnimationDuration: 0.25];
  [UIView setAnimationDelegate: self];
  self.navigationBar.alpha = 0;
  RhinoApp.navigationController.toolbar.alpha = 0;
  [UIView setAnimationDidStopSelector: @selector(finishHidingBars:)];
  [UIView commitAnimations];
  
}

- (void) finishHidingBars: (id) sender
{
  [self.navigationController setNavigationBarHidden: YES];
  self.navigationBar.alpha = 1;
  [self.navigationController setToolbarHidden: YES];
  self.navigationController.toolbar.alpha = 1;
}


- (void) hideBarsAfterDelay: (NSTimeInterval) seconds
{
  if (self.navigationController.isNavigationBarHidden)
    return;     // nothing to do
  
  [hidingTimer invalidate];
  self.hidingTimer = [NSTimer scheduledTimerWithTimeInterval: seconds target: self selector: @selector(hideBars:) userInfo: nil repeats: NO];
}

// Hide toolbars after "standard" delay amount.  Will also reset the delay time to full delay amount if called when
// a delay timer is already in effect.
- (void) hideBarsAfterDelay
{
  [self hideBarsAfterDelay: 4.0];
}

// Make the navigation bar and toobar visible.  Hide them again after a while.
- (void) showBars
{
  [hidingTimer invalidate];
  self.hidingTimer = nil;
  
  UIApplication* application = [UIApplication sharedApplication];
  
  // if navigation bar is already visible, do nothing
  if (![RhinoApp.navigationController isNavigationBarHidden])
    return;
  
  [application setStatusBarHidden: NO withAnimation: UIStatusBarAnimationNone];
  self.navigationBar.alpha = 0;
  [RhinoApp.navigationController setNavigationBarHidden: NO];
  RhinoApp.navigationController.toolbar.alpha = 0;
  [RhinoApp.navigationController setToolbarHidden: NO];

  [UIView beginAnimations: nil context: nil];
  [UIView setAnimationDuration: 0.1];
  [UIView setAnimationDelegate: self];
  self.navigationBar.alpha = 1;
  RhinoApp.navigationController.toolbar.alpha = 1;
  [UIView commitAnimations];

  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    [self hideBarsAfterDelay];
}

#pragma mark Single tap

- (void) startSingleTapTimer
{
  // Ignore single taps until the model is visible and the downloading view is gone
  if (! modelIsVisible)
    return;
  
  [singleTapTimer invalidate];
  self.singleTapTimer = [NSTimer scheduledTimerWithTimeInterval: 0.5 target: self selector: @selector(singleTap:) userInfo: nil repeats: NO];
}

- (void) cancelSingleTapTimer
{
  [singleTapTimer invalidate];
  self.singleTapTimer = nil;
}

// A single tap has happened
- (void) singleTap: (id) sender
{
  [singleTapTimer invalidate];
  self.singleTapTimer = nil;
  UIApplication* application = [UIApplication sharedApplication];
  if ([self barsHidden])  
    [self showBars];
  else
    [self hideBars: self];
}


#pragma mark View controller overrides

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad
{
  [super viewDidLoad];
  [glView clearView];
  self.wantsFullScreenLayout = YES;
}

- (void) clearEntireView
{
  modelIsVisible = NO;
  [self initTopToolbar];
  [self initBottomToolbar];
  self.navigationItem.rightBarButtonItem = nil;
  self.toolbarItems = [NSArray array];
  [glView clearView];
}

- (void) viewWillAppear: (BOOL) animated
{
  [self initTopToolbar];
  [self initBottomToolbar];
  self.navigationItem.rightBarButtonItem = nil;
  
  // navigation controller is translucent on iPhone and opaque on iPad
  self.navigationBar.translucent = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone;
  
  RhModel* currentModel = RhinoApp.currentModel;
  
  if (currentModel != nil && displayedModel != currentModel) {
    [self clearEntireView];
  }
  
  self.title = [currentModel title];
  
  self.displayedModel = currentModel;
  
  [self updateStereoButton];
}


- (void) viewDidAppear: (BOOL) animated
{
  if (RhinoApp.currentModel != nil) {
    [RhinoApp.currentModel prepareModelWithDelegate: self];
    [glView viewDidAppear];
    [glView setNeedsDisplay];
  }
}


- (void)viewWillDisappear:(BOOL)animated
{
  [self stopTimers];
  [RhinoApp.currentModel cancelModelPreparation];  
	[glView viewWillDisappear];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
  return YES;
}

#pragma mark Image Capture

- (void) didCaptureImage: (UIImage*) image
{
  // cancel view capture
}


#pragma mark Actions


- (void) updateStereoButton
{
  if (glView.stereoMode)
    [bottomToolbarItems replaceObjectAtIndex: stereoIndex withObject: stereoButton];
  else
    [bottomToolbarItems replaceObjectAtIndex: stereoIndex withObject: notStereoButton];
  if (modelIsVisible)
    [self setToolbarItems: [NSArray arrayWithArray: bottomToolbarItems] animated: NO];
}

- (void) stereo: (id) sender
{
  glView.stereoMode = ! glView.stereoMode;
  [self updateStereoButton];
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    [self hideBarsAfterDelay];      // reset hiding delay
}


- (IBAction) zoomExtents: (id) sender
{
  [glView zoomExtents];
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    [self hideBarsAfterDelay];      // reset hiding delay
}


- (IBAction) zoomHome: (id) sender
{
  [glView zoomHome];
}


- (IBAction) cancelModelPreparation: (id) sender
{
  [self.displayedModel cancelModelPreparation];
}

#pragma mark RhModel preparation delegate methods


- (void) preparationDidFailWithError: (NSError*) error
{
  if (error) {
    // model did not load correctly
  }
}


- (void) preparationDidSucceed
{
  RhModel* currentModel = RhinoApp.currentModel;
  if (currentModel == nil)
    return;
  
  // final initialization
  if ([glView model] != currentModel)
    [glView prepareForDisplay: currentModel];
  
  modelIsVisible = YES;
  
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
    [self setToolbarItems: [NSArray arrayWithArray: bottomToolbarItems] animated: NO];
    [self hideBarsAfterDelay];
  }
  
  [glView setNeedsDisplay];
}


#pragma mark MFMailComposeViewControllerDelegate methods

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
  [self dismissModalViewControllerAnimated: YES];
}

@end
