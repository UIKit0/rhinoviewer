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


#import <Foundation/Foundation.h>

class EX_ONX_Model;
@class GDataEntryDocBase;

typedef enum {
  unknownSource = 0,
  bundleSource,                 // a McNeel sample model in the models.plist file
  lastSource
};
  
@interface RhModel : NSObject <NSCoding> {

  NSString* title;              // model title
  NSString* description;        // model description
  
  int source;                   // source of downloaded model
  
  NSString* urlString;          // URL for 3DM data file
  NSString* modelID;            // string derived from 3DM ON_3dmProperties, used to detect file changes
  
  // all data for this model (except the model itself) is stored in this directory inside the ~/Library/Caches directory.
  // This directory (and its contents) are deleted when iTunes performs a restore so be prepared for missing cache files.
  NSString* cachesDirectoryName;
  
  // Downloaded model contents are stored in this file in our Documents directory.  The Documents directory is visible
  // in the File Sharing section of iTunes, so it is possible for the user to delete this file.
  NSString* documentsFilename;
  
  NSString* previewFilename;    // preview image is stored in this file in our Documents subdirectory
  NSString* thumbnailFilename;  // thumbnail image is stored in this file in our Documents subdirectory
  UIImage* thumbnailImage;      // thumbnail image
  UIImage* previewImage;        // preview image (same dimension as UIScreen)
  
  NSString* bundleName;         // resource name if the model is available in the application bundle (used for sample files)
  BOOL isSample;                // YES for McNeel sample files
  BOOL downloaded;              // file exists in ~/Documents
  
  long fileSize;                // model statistics
  long meshObjectCount;
  long renderMeshCount;
  long geometryCount;
  long brepCount;
  long brepWithMeshCount;
  BOOL tumbling;
  
  BOOL outOfMemoryWarning;
  
  int continueReading;          // -1 = pause, 0 = stop, 1 = continue
  NSLock* continueReadingLock;
  
  BOOL readingModel;
  BOOL readSuccessfully;
  BOOL initializationFailed;    // the last attempt to read the model and initialize meshes failed
  BOOL preparationCancelled;

  id preparationDelegate;
  
  EX_ONX_Model* onMacModel;
  NSMutableArray* meshes;     // our DisplayMesh objects
  NSMutableArray* transmeshes;     // our DisplayMesh objects
}


@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy) NSString* description;
@property (nonatomic, copy) NSString* urlString;
@property (nonatomic, copy) NSString* cachesDirectoryName;
@property (nonatomic, copy) NSString* documentsFilename;
@property (nonatomic, readonly) NSString* bundleName;
@property (nonatomic, readonly) BOOL isSample;
@property (nonatomic, readonly) long fileSize;
@property (nonatomic, readonly) long meshObjectCount;
@property (nonatomic, readonly) long renderMeshCount;
@property (nonatomic, readonly) long polygonCount;
@property (nonatomic) long geometryCount;
@property (nonatomic) long brepCount;
@property (nonatomic) long brepWithMeshCount;
@property (nonatomic, assign, getter=isDownloaded) BOOL downloaded;
@property (nonatomic, assign) int source;

@property (assign) BOOL readingModel;
@property (assign) int continueReading;
@property (assign) NSLock* continueReadingLock;
@property (assign) BOOL readSuccessfully;
@property (assign) BOOL initializationFailed;
@property (assign) BOOL preparationCancelled;

@property (retain) NSArray* meshes;
@property (retain) NSArray* transmeshes;


- (void)encodeWithCoder:(NSCoder *)aCoder;
- (id)initWithCoder:(NSCoder *)aDecoder;
- (id)initWithDictionary: (NSDictionary*) dictionary;

- (void) initializeSampleModel;

- (EX_ONX_Model*) onMacModel;

- (ON_BoundingBox) boundingBox;

- (BOOL) becomeCurrentModel;
- (void) resignCurrentModel;

- (BOOL) needsPassword;

- (void) prepareModelWithDelegate: (id) delegate;
- (void) cancelModelPreparation;

- (NSString*) modelPath;              // full path of 3dm file on iPhone

- (BOOL) hasDocumentsName: (NSString*) aName;

- (BOOL) meshesInitialized;       // true if mesh VBOs are created
- (void) deleteAll;               // delete everything, including our model and all cached data
- (void) deleteCaches;            // delete all cached data but not the model

- (void) undownload;              // revert to undownloaded status

- (NSString*) cachesPathForName: (NSString*) fileOrDirectoryName;


@end
