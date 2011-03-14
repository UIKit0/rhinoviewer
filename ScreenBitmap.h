//
//  ScreenBitmap.h
//  iRhino3D
//
//  Created by Mac Rhino on 3/4/11.
//  Copyright 2011 Robert McNeel & Associates. All rights reserved.
//



@interface ScreenBitmap : NSObject {

  NSInteger width;
  NSInteger height;
  unsigned char* buffer;
}

- (id) initWithWidth: (NSInteger) backingWidth height: (NSInteger) backingHeight;
- (unsigned char*) buffer;
- (unsigned int) pixelAt: (CGPoint) pt;

@end
