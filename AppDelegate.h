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

#import <UIKit/UIKit.h>
#import "RhModelView.h"
#import "RhModel.h"


@class EAGLView;
@class ModelListViewController;
@class RhModelViewController;
@class UISplitViewController;


// global pointer to our singleton AppDelegate instance
@class AppDelegate;
extern AppDelegate* RhinoApp;



@interface AppDelegate : NSObject <UIApplicationDelegate> {
  UIWindow *window;
  UINavigationController* navigationController;
  RhModelViewController* rhinoModelViewController;
    
  RhModel* currentModel;
  NSMutableArray* models;       // array of RhModel objects
  
  BOOL fastDrawing;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet UINavigationController *navigationController;

@property (nonatomic, readonly) RhModel *currentModel;
@property (nonatomic, readonly) NSArray* models;

@property (assign) BOOL fastDrawing;

- (NSString*) newUUID;

- (ON_Color) backgroundColor;           // default background color

- (UIColor*) backgroundTopColor;        // background gradient color at top of screen
- (UIColor*) backgroundBottomColor;     // background gradient color at bottom of screen

- (CGFloat) screenScale;

@end

