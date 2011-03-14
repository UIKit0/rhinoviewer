//
//  ScreenBitmap.mm
//  iRhino3D
//
//  Created by Mac Rhino on 3/4/11.
//  Copyright 2011 Robert McNeel & Associates. All rights reserved.
//

#import "ScreenBitmap.h"


@implementation ScreenBitmap

- (id) initWithWidth: (NSInteger) w height: (NSInteger) h
{
  self = [super init];
  if (self) {
    width = w;
    height = h;
    NSInteger bufferLength = width * height * 4;
    buffer = (unsigned char*) malloc (bufferLength);
  }
  return self;
}


- (void) dealloc
{
  free(buffer);
  [super dealloc];
}

- (unsigned char*) buffer
{
  return buffer;
}

- (unsigned int) pixelAt: (CGPoint) pt
{
  unsigned int x = pt.x * [RhinoApp screenScale];
  unsigned int y = pt.y * [RhinoApp screenScale];
  if (buffer && x >= 0 && x < width && y >= 0 && y < height)
    return *(unsigned int*)(buffer + 4*width*(height-y) + x*4);
  return 0;
}

@end
