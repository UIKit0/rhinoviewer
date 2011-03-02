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

//
// Support routines for the DLog debugging print routines
//


#pragma mark -
#pragma mark debug output routines used by DLog

#if __LITTLE_ENDIAN__
#define kRhinoCFwcharEncoding kCFStringEncodingUTF32LE
#endif
#if __BIG_ENDIAN__
#define kRhinoCFwcharEncoding kCFStringEncodingUTF32BE
#endif

#define kRhinoNSwcharEncoding (CFStringConvertEncodingToNSStringEncoding(kRhinoCFwcharEncoding))

size_t	wcslen(const wchar_t *str)
{
  size_t len = 0;
  while (*str++ != 0)
    len++;
  return len;
}


NSString* w2ns(const wchar_t* inStr)
{
  if (inStr == NULL)
    return nil;
  
  NSString* outStr = [[NSString alloc] initWithBytes:inStr
                                              length:wcslen(inStr)*sizeof(wchar_t)
                                            encoding:kRhinoNSwcharEncoding];
  [outStr autorelease];
  return outStr;
}


// convert ON_UUID to NSString*
NSString* uuid2ns(ON_UUID uuid)
{
  ON_wString s;
  return w2ns (ON_UuidToString(uuid, s));
}

void MRLogv (const char* func, const char* filePath, unsigned int line, NSString* fmt, va_list argList)
{
  NSString* msg = [[[NSString alloc] initWithFormat: fmt arguments: argList] autorelease];
  NSLog (@"[%@:%d  %s] %@", [[NSString stringWithUTF8String: filePath] lastPathComponent], line, func, msg);
}

void MRLog (const char* func, const char* filePath, unsigned int line, NSString* fmt, ...)
{
  va_list arguments;
  va_start (arguments, fmt);
  MRLogv (func, filePath, line, fmt, arguments);
}

void MRLog (const char* func, const char* filePath, unsigned int line, const char* fmt, ...)
{
  va_list arguments;
  va_start (arguments, fmt);
  MRLogv (func, filePath, line, [NSString stringWithUTF8String: fmt], arguments);
}

void MRLog (const char* func, const char* filePath, unsigned int line, const wchar_t* fmt, ...)
{
  va_list arguments;
  va_start (arguments, fmt);
  MRLogv (func, filePath, line, w2ns(fmt), arguments);
}
