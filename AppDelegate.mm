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

#import "AppDelegate.h"
#import "EAGLView.h"
#import "RhModelViewController.h"
#import "RhModelViewControllerPad.h"
#import "RhModel.h"



// global pointer to our singleton AppDelegate instance
AppDelegate* RhinoApp;


@implementation AppDelegate

@synthesize window, currentModel, fastDrawing;
@synthesize navigationController;

- (id)init
{
  self = [super init];
  if (self)
  {
    RhinoApp = self;
  }
  return self;
}

- (void) dealloc
{
  [window release];
  [navigationController release];
  [currentModel release];
  [models release];
  [super dealloc];
}

// Read the models.plist and build the list of default RhModel objects
- (NSMutableArray*) modelsFromBundle
{
  NSMutableArray* sampleModels = [NSMutableArray array];
  NSString *path = [[NSBundle mainBundle] pathForResource: @"models" ofType: @"plist"];
  NSDictionary* outlineData = [NSDictionary dictionaryWithContentsOfFile: path];
  NSArray* bundleModels = [outlineData objectForKey: @"models"];
  for (NSDictionary* modelData in bundleModels) {
    RhModel* md = [[[RhModel alloc] initWithDictionary: modelData] autorelease];
    [sampleModels addObject: md];
    [md initializeSampleModel];
  }
  return sampleModels;
}

#pragma mark settings methods

- (void) loadModels
{
  [models release];
  models = [[self modelsFromBundle] retain];
}

#pragma mark application delegate methods

- (BOOL)application: (UIApplication*) application didFinishLaunchingWithOptions: (NSDictionary*) launchOptions
{
  BOOL rc = YES;      // assume success
  
  // initialize OpenNURBS
  ON::Begin();
  
  // finish initialization
  [self loadModels];
  
  currentModel = [models objectAtIndex: 0];
    
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    [application setStatusBarStyle: UIStatusBarStyleBlackTranslucent];
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    [application setStatusBarStyle: UIStatusBarStyleBlackOpaque];
    
	[window makeKeyAndVisible];
  
  [window addSubview: [navigationController view]];

  return rc;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
  return NO;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
  return [self application: application handleOpenURL: url];
}

- (void)applicationDidFinishLaunching: (UIApplication*) application
{
  [self application: application didFinishLaunchingWithOptions: nil];
}

#pragma mark utility methods

- (NSArray*) models
{
  return [[models retain] autorelease];
}

- (NSString*) newUUID
{
  ON_UUID uuid;
  
  ON_CreateUuid (uuid);
  return uuid2ns (uuid);
}

// default background color
- (ON_Color) backgroundColor
{
  return ON_Color(220,220,220,255);
}


// background gradient color at top of screen
- (UIColor*) backgroundTopColor
{
  return [UIColor colorWithRed: 0.556 green: 0.815 blue: 0.922 alpha: 1.0];
  return [UIColor colorWithWhite: 0.915 alpha: 1.0];                            // slight gray gradient
}


// background gradient color at bottom of screen
- (UIColor*) backgroundBottomColor
{  
  return [UIColor colorWithRed: 0.286 green: 0.427 blue: 0.518 alpha: 1.0];
  return [UIColor colorWithWhite: 0.715 alpha: 1.0];                            // slight gray gradient

}

- (CGFloat) screenScale
{
  if([[UIScreen mainScreen] respondsToSelector: @selector(scale)])
    return [[UIScreen mainScreen] scale];
  return 1.0;
}

@end

