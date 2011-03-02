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

#import <UIKit/UIKit.h>


extern "C" {
  void* GetCurrentThreadId()
  {
    return 0;
  }
}

int main(int argc, char *argv[]) {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    int retVal = UIApplicationMain(argc, argv, nil, nil);
    [pool release];
    return retVal;
}
