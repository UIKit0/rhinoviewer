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
#import <MessageUI/MessageUI.h>
#import <MessageUI/MFMailComposeViewController.h>

#import "RhModelView.h"

@class InfoViewController;


@interface RhModelViewController : UIViewController <UIActionSheetDelegate, MFMailComposeViewControllerDelegate> {

  RhModelView* glView;
  
  UIActionSheet* imageSheet;
  UIActionSheet* deleteSheet;
  
  int stereoIndex;
  UIButton* stereoButton;
  UIButton* notStereoButton;
  NSMutableArray* topToolbarItems;
  NSMutableArray* bottomToolbarItems;
    
  NSTimer* hidingTimer;
  int hidingTimerTickCount;
  
  NSTimer* singleTapTimer;
  
  RhModel* displayedModel;
  BOOL modelIsVisible;
}

@property (nonatomic, retain) IBOutlet RhModelView* glView;

@property (nonatomic, retain) NSMutableArray* topToolbarItems;
@property (nonatomic, retain) NSMutableArray* bottomToolbarItems;

@property (nonatomic, retain) NSTimer* hidingTimer;
@property (nonatomic, retain) NSTimer* singleTapTimer;

@property (nonatomic, retain) RhModel* displayedModel;

- (void) preparationDidSucceed;
- (void) preparationDidFailWithError: (NSError*) error;

- (IBAction) cancelModelPreparation: (id) sender;

- (UINavigationBar*) navigationBar;
- (void) showBars;
- (void) hideBars: (id) sender;
- (void) hideBarsAfterDelay: (NSTimeInterval) seconds;

- (void) startSingleTapTimer;
- (void) cancelSingleTapTimer;

@end
