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

#import "RhModel.h"
#import "DisplayMesh.h"


@interface RhModel ()
- (void) meshPreparationProgress: (NSNumber*) progress;
- (void) meshPreparationDidSucceed;
- (void) meshPreparationDidFailWithError: (NSError*) error;
@end


@implementation RhModel

@synthesize title, description, source, urlString, cachesDirectoryName, documentsFilename, bundleName, isSample;
@synthesize fileSize, meshObjectCount, renderMeshCount, geometryCount, brepCount, brepWithMeshCount, downloaded;
@synthesize preparationCancelled, readingModel, continueReading, continueReadingLock, readSuccessfully, initializationFailed, meshes, transmeshes;


// Helper method for creating a full path from a file name that is in the ~/Library/Caches directory
- (NSString*) cachesPathFromDirectory: (NSString*) directory filename: (NSString*) filename
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains (NSCachesDirectory, NSUserDomainMask, YES); 
  NSString* filePath = [paths objectAtIndex:0];
  if (directory.length > 0)
    filePath = [filePath stringByAppendingPathComponent: directory];
  if (filename.length > 0)
    filePath = [filePath stringByAppendingPathComponent: filename];
  return filePath;
}


// Helper method for creating a full path for one of our files that is in our ~/Library/Caches subdirectory
- (NSString*) cachesPathForName: (NSString*) fileOrDirectoryName
{
  if (cachesDirectoryName == nil) {
    self.cachesDirectoryName = RhinoApp.newUUID;
    NSString* cachesDirectoryPath = [self cachesPathFromDirectory: cachesDirectoryName filename: nil];
    BOOL rc = [[NSFileManager defaultManager] createDirectoryAtPath: cachesDirectoryPath
                                        withIntermediateDirectories: YES
                                                         attributes: nil
                                                              error: nil];
  }
  return [self cachesPathFromDirectory: cachesDirectoryName filename: fileOrDirectoryName];
}


#pragma mark Initialization


- (id) init
{
  self = [super init];
  if (self) {
    continueReadingLock = [[NSLock alloc] init];
  }
  return self;
}


- (id) initWithDictionary: (NSDictionary*) dictionary
{
  self = [self init];
  if (self) {
    NSString* str;
    str = [dictionary objectForKey: @"IRModelTitle"];
    title = [[[NSBundle mainBundle] localizedStringForKey: str value: str table: nil] copy];
    str = [dictionary objectForKey: @"IRModelDescription"];
    description = [[[NSBundle mainBundle] localizedStringForKey: str value: str table: nil] copy];
    urlString = [[dictionary objectForKey: @"IRModelURL"] copy];
    modelID = [[dictionary objectForKey: @"IRModelID"] copy];
    cachesDirectoryName = [[dictionary objectForKey: @"IRCachesDirectory"] copy];
    documentsFilename = [[dictionary objectForKey: @"IRDocumentsFilename"] copy];
    previewFilename = [[dictionary objectForKey: @"IRPreviewFilename"] copy];
    bundleName = [[dictionary objectForKey: @"IRBundleName"] copy];
    isSample = [[dictionary objectForKey: @"IRIsSample"] boolValue];
    downloaded = [[dictionary objectForKey: @"IRDownloaded"] boolValue];
    if (bundleName != nil)
      downloaded = YES;
    source = [[dictionary objectForKey: @"IRModelSource"] intValue];
  }
  return self;
}


- (void) dealloc
{
  [continueReadingLock release];
  delete onMacModel;
  [meshes release];
  [transmeshes release];

  [title release];
  [description release];
  [urlString release];
  [modelID release];
  [thumbnailImage release];
  [previewImage release];
  [cachesDirectoryName release];
  [documentsFilename release];
  [previewFilename release];
  [thumbnailFilename release];
  [bundleName release];
  [super dealloc];
}

// This model has just been created by a reset.  Set up our disk data
- (void) initializeSampleModel
{
  if (bundleName) {
    self.documentsFilename = [[NSBundle mainBundle] pathForResource: bundleName ofType:@"3dm"];
    self.downloaded = YES;
  }
}

#pragma mark NSCoding

- (void)encodeWithCoder:(NSCoder *) coder
{
  //  [super encodeWithCoder: coder];
  [coder encodeObject: title forKey: @"IRModelTitle"];
  [coder encodeObject: description forKey: @"IRModelDescription"];
  [coder encodeObject: urlString forKey: @"IRModelURL"];
  [coder encodeObject: modelID forKey: @"IRModelID"];
  [coder encodeObject: cachesDirectoryName forKey: @"IRCachesDirectory"];
  [coder encodeObject: documentsFilename forKey: @"IRDocumentsFilename"];
  [coder encodeObject: previewFilename forKey: @"IRPreviewFilename"];
  [coder encodeObject: thumbnailFilename forKey: @"IRThumbnailFilename"];
  [coder encodeObject: bundleName forKey: @"IRBundleName"];
  [coder encodeObject: [NSNumber numberWithBool: isSample] forKey: @"IRIsSample"];
  [coder encodeObject: [NSNumber numberWithBool: downloaded] forKey: @"IRDownloaded"];
  [coder encodeObject: [NSNumber numberWithInt: source] forKey: @"IRModelSource"];
  if (thumbnailImage) {
    if (thumbnailFilename == nil) {
      NSData* pngData = UIImagePNGRepresentation (thumbnailImage);
      [coder encodeObject: pngData forKey: @"IRModelThumbnailImage"];
    }
    if ([thumbnailImage respondsToSelector: @selector(scale)]) {
      CGFloat thumbnailScale = [thumbnailImage scale];
      [coder encodeObject: [NSNumber numberWithFloat: thumbnailScale] forKey: @"IRThumbnailScale"];
    }
  }
}

- (id)initWithCoder: (NSCoder *) decoder
{
  self = [self init];
  if (self) {
    title = [[decoder decodeObjectForKey: @"IRModelTitle"] copy];
    description = [[decoder decodeObjectForKey: @"IRModelDescription"] copy];
    urlString = [[decoder decodeObjectForKey: @"IRModelURL"] copy];
    modelID = [[decoder decodeObjectForKey: @"IRModelID"] copy];
    cachesDirectoryName = [[decoder decodeObjectForKey: @"IRCachesDirectory"] copy];
    documentsFilename = [[decoder decodeObjectForKey: @"IRDocumentsFilename"] copy];
    previewFilename = [[decoder decodeObjectForKey: @"IRPreviewFilename"] copy];
    thumbnailFilename = [[decoder decodeObjectForKey: @"IRThumbnailFilename"] copy];
    bundleName = [[decoder decodeObjectForKey: @"IRBundleName"] copy];
    isSample = [[decoder decodeObjectForKey: @"IRIsSample"] boolValue];
    downloaded = [[decoder decodeObjectForKey: @"IRDownloaded"] boolValue];
    source = [[decoder decodeObjectForKey: @"IRModelSource"] intValue];
    NSData* pngData = [decoder decodeObjectForKey: @"IRModelThumbnailImage"];
    if (pngData)
      thumbnailImage = [[UIImage imageWithData: pngData] retain];
    if (thumbnailFilename != nil) {
      NSString* thumbnailPath = [self cachesPathForName: thumbnailFilename];
      if ([[NSFileManager defaultManager] fileExistsAtPath: thumbnailPath]) {
        [thumbnailImage release];
        thumbnailImage = [[UIImage imageWithContentsOfFile: thumbnailPath] retain];
      }
    }
    if ([thumbnailImage respondsToSelector: @selector(scale)]) {
      // fix up thumbnail scale
      CGFloat thumbnailScale = [[decoder decodeObjectForKey: @"IRThumbnailScale"] floatValue];
      if (thumbnailScale != 0.0 && thumbnailScale != thumbnailImage.scale) {
        [thumbnailImage release];
        thumbnailImage = [[UIImage imageWithCGImage: thumbnailImage.CGImage scale: [RhinoApp screenScale] orientation: UIImageOrientationUp] retain];
      }
    }
  }
  return self;
}

#pragma mark Utilities

- (EX_ONX_Model*) onMacModel
{
  return onMacModel;
}

- (ON_BoundingBox) boundingBox
{
  if (onMacModel)
    return onMacModel->BoundingBox();
  return ON_BoundingBox::EmptyBoundingBox;
}

- (NSString*) debugDescription
{
  return [NSString stringWithFormat: @"RhModel %p %@ meshes:%@", self, title, [meshes description]];
}


// return full pathname of 3dm file
- (NSString*) modelPath
{
  if (documentsFilename) {
    return documentsFilename;
  }
  return nil;
}

- (NSString*) basename
{
  return title;
}

- (BOOL) hasDocumentsName: (NSString*) aName
{
  if (aName != nil && documentsFilename != nil)
    return [documentsFilename localizedCaseInsensitiveCompare: aName] == NSOrderedSame;
  return NO;
}

- (BOOL) needsPassword
{
  return NO;
}

- (BOOL) meshesInitialized
{
  return (meshes != nil || transmeshes != nil) || !initializationFailed;
}

// delete all cached data but not the model
- (void) deleteCaches
{
  if (cachesDirectoryName)
    [[NSFileManager defaultManager] removeItemAtPath: [self cachesPathForName: nil] error: nil];
  self.cachesDirectoryName = nil;
}

// delete everything, including our containing directory
- (void) deleteAll
{
  [self deleteCaches];
  downloaded = NO;
}

- (void) cleanUp
{
  delete onMacModel;
  onMacModel = nil;
  [meshes release];
  meshes = nil;
  [transmeshes release];
  transmeshes = nil;
}

// revert to undownloaded status
- (void) undownload
{
  [self deleteAll];
  [self cleanUp];
}

- (void)alertView: (UIAlertView*) alertView willDismissWithButtonIndex:(NSInteger) buttonIndex
{
  if (buttonIndex == 0)
    self.continueReading = 1;   // 1 = continue
  else
    self.continueReading = 0;   // 0 = stop
  
  // unblock the reading thread
  [continueReadingLock unlock];
}

#pragma mark Accessors

- (long) polygonCount
{
  long triangles = 0;
  for (DisplayMesh* me in meshes)
    triangles += [me triangleCount];
  for (DisplayMesh* me in transmeshes)
    triangles += [me triangleCount];
  return triangles;
}

- (NSString*) modelID
{
  return [modelID copy];
}

- (void) setModelID: (NSString*) newValue
{
  if (![modelID isEqualToString: newValue]) {
    // If the modelID has changed, the user likely modified a file in the Documents folder.
    // Invalidate any cached data.
    [self deleteCaches];
    [modelID release];
    modelID = [newValue copy];
  }
}


#pragma mark Mesh Caches

//
// Models with large meshes must partition the meshes before displaying them on the iPhone.
// Partitioning meshes is a lengthy process and can take > 80% of the model loading time.
// We save the raw VBO data of a mesh in an archive after a mesh has been partitioned
// and use that archive to create the VBOs next time we display the model.
//

- (BOOL) loadMeshCaches: (ON_Mesh*) mesh withAttributes: (ON_3dmObjectAttributes&) attr withMaterial: (ON_Material&) material
{
  NSString* meshUUIDStr = uuid2ns(attr.m_uuid);
  NSString* meshCachePath = [self cachesPathForName: [meshUUIDStr stringByAppendingPathExtension: @"meshes"]];
  NSArray* displayMeshes = [NSKeyedUnarchiver unarchiveObjectWithFile: meshCachePath];
  if (displayMeshes == nil)
    return NO;
  for (DisplayMesh* me in displayMeshes)
    [me restoreUsingMesh: mesh material: material];

  if ( material.Transparency() == 0 )
    [meshes addObjectsFromArray: displayMeshes];
  else
    [transmeshes addObjectsFromArray: displayMeshes];
  return YES;
}

- (void) saveDisplayMeshes: (NSArray*) cachedMeshes forMesh: (ON_Mesh*) mesh withAttributes: (ON_3dmObjectAttributes&) attr withMaterial: (ON_Material&) material
{
  NSString* meshUUIDStr = uuid2ns(attr.m_uuid);
  NSString* meshCachePath = [self cachesPathForName: [meshUUIDStr stringByAppendingPathExtension: @"meshes"]];
  [NSKeyedArchiver archiveRootObject: cachedMeshes toFile: meshCachePath];
}

#pragma mark Meshes

-(NSError*) meshError: (NSString*) errorStr
{
  NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                            NSLocalizedString(@"Cannot initialize model", @"title for warning dialog"), NSLocalizedDescriptionKey,
                            errorStr, NSLocalizedFailureReasonErrorKey,
                            nil];
  return [NSError errorWithDomain: @"com.yourcompany.rhinoviewer" code: 33 userInfo: userInfo];
}
  
- (void) createDisplayMeshes: (ON_Mesh*) mesh withAttributes: (ON_3dmObjectAttributes&) attr withMaterial: (ON_Material&) material
{
  // will we create more than one partition?
  int vertex_count = mesh->VertexCount();
  const int triangle_count = mesh->TriangleCount() + 2*mesh->QuadCount();
  BOOL multipleMeshPartitions = vertex_count > USHRT_MAX-3 || triangle_count > INT_MAX-3;
  if (multipleMeshPartitions && [self loadMeshCaches: mesh withAttributes: attr withMaterial: material])
    return;       // successfully created DisplayMesh objects from the cache.  We are done.
  
  const ON_MeshPartition* partition = mesh->CreatePartition(USHRT_MAX-3, INT_MAX-3);
  if (partition == NULL)
    return;     // invalid mesh, ignore
  int partCount = partition->m_part.Count();
  
  NSMutableArray* displayMeshes = [[NSMutableArray alloc] initWithCapacity: partCount];
  
//  DLog (@"  ");
//  DLog (@"mesh %p VertexCount %d, triangleCount %d vertexIndexCount %d FaceCount %d", mesh, mesh->VertexCount(), mesh->TriangleCount(), mesh->TriangleCount()*3 + mesh->QuadCount()*6, mesh->FaceCount());
//  DLog (@"partition has %d parts", partition->m_part.Count());
    
  for (int idx=0; idx<partCount; idx++) {
    
    const struct ON_MeshPart& part = partition->m_part[idx];
//    DLog (@"m_V[%d] -> m_V[%d], m_F[%d] -> m_F[%d] vertexCount %d, triangleCount %d", part.vi[0], part.vi[1], part.fi[0], part.fi[1], part.vertex_count, part.triangle_count);
    DisplayMesh* me = [[DisplayMesh alloc] initWithMesh: mesh index: idx material: material saveVBOData: multipleMeshPartitions];
    if (me) {
      if ( [me isOpaque] )
        [meshes addObject: me];
      else
        [transmeshes addObject: me];
      [displayMeshes addObject: me];
      [me release];
    }
  }
  if (multipleMeshPartitions) {
    [self saveDisplayMeshes: displayMeshes forMesh: mesh withAttributes: attr withMaterial: material];
    for (DisplayMesh* me in displayMeshes)
      [me deleteVBOData];
  }
  [displayMeshes release];
}

- (void) addAnyMesh: (const ON_Mesh*) mesh withAttributes: (ON_3dmObjectAttributes&) attr
{
  [self meshPreparationProgress: [NSNumber numberWithFloat: -1.0]];

  ON_Material material;
  onMacModel->GetRenderMaterial ( attr, material );
  
  // If our render material is the default material, modify our material to match the Rhino default material
  if (material.MaterialIndex() < 0)
    material.SetDiffuse( ON_Color( 255, 255, 255));
  
  [self createDisplayMeshes: const_cast<ON_Mesh*> (mesh) withAttributes: attr withMaterial: material];    // cast away const
}


- (void) addRenderMesh: (const ON_Mesh*) mesh withAttributes: (ON_3dmObjectAttributes&) attr
{
  renderMeshCount++;
  [self addAnyMesh: mesh withAttributes: attr];
}


- (void) addMeshObject: (const ON_Mesh*) mesh withAttributes: (ON_3dmObjectAttributes&) attr
{
  meshObjectCount++;
  [self addAnyMesh: mesh withAttributes: attr];
}


// This potentially long-running process is run in a separate thread
- (void) prepareMeshes
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  self.readingModel = YES;
  [self.continueReadingLock lock];
  self.continueReading = 1;
  [self.continueReadingLock unlock];
  NSError* prepareMeshesError = nil;
  
  if ([self isDownloaded]) {
    // Use a helper class to read the 3DM file
    if (onMacModel == nil) {
      
      self.meshes = [NSMutableArray array];
      self.transmeshes = [NSMutableArray array];
      renderMeshCount = 0;
      meshObjectCount = 0;
      brepCount = 0;
      brepWithMeshCount = 0;
      
      // get the file size
      NSDictionary * attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: [self modelPath] error:nil];
      NSNumber *theFileSize;
      if (theFileSize = [attributes objectForKey: NSFileSize])
        fileSize = [theFileSize intValue];
      
      // show we have started reading the meshes
      [self meshPreparationProgress: [NSNumber numberWithFloat: -1.0]];

      // The initWithFilename call will read the OpenNURBS file.  As each object is read,
      // the EX_ONX_Model::ShouldKeepObject() function in this source file is called to
      // inspect and perform any operations on the object.
      onMacModel = new EX_ONX_Model;
      ON_BOOL32 rc = onMacModel->initWithFilename ([[self modelPath] UTF8String]);
      
      if (rc) {
        // look for models that cannot be displayed
        if ((meshes.count == 0) && (transmeshes.count == 0)) {
          if (brepCount > 0 && brepWithMeshCount == 0)
            prepareMeshesError = [self meshError: NSLocalizedString(@"This model is only wireframes and cannot be displayed.  Save the model in shaded mode and download again.",@"error message when reading 3DM file")];
          else if (geometryCount > 0 && brepWithMeshCount == 0)
            prepareMeshesError = [self meshError: NSLocalizedString(@"This model has no renderable geometry.",@"error message when reading 3DM file")];
          else
            prepareMeshesError = [self meshError: NSLocalizedString(@"This model is empty.", @"error message when reading 3DM file")];
          
          rc = 0;
        }
      }

      if (!rc) {
        self.meshes = nil;
        self.transmeshes = nil;
        delete onMacModel;
        onMacModel = nil;
        if (preparationCancelled)
          prepareMeshesError = [self meshError: NSLocalizedString(@"Initialization cancelled.", @"error message when reading 3DM file")];
        else if (prepareMeshesError == nil)
          prepareMeshesError = [self meshError: NSLocalizedString(@"This model is corrupt and cannot be displayed.", @"error message when reading 3DM file")];
      }
      
      self.readingModel = NO;
      self.readSuccessfully = rc;
    }
  }
  if (prepareMeshesError)
    [self meshPreparationDidFailWithError: prepareMeshesError];
  else
    [self meshPreparationDidSucceed];
  [pool release];
}


- (void) cancelMeshInitialization
{
  preparationCancelled = YES;
}

- (void) meshPreparationProgress: (NSNumber*) progress
{
  // pass the message to the preparationDelegate
  if ([preparationDelegate respondsToSelector: @selector(meshPreparationProgress:)])
    [preparationDelegate performSelectorOnMainThread: @selector(meshPreparationProgress:) withObject: progress waitUntilDone: NO];
}

- (void) meshPreparationDidSucceed
{
  if ([preparationDelegate respondsToSelector: @selector(preparationDidSucceed)])
    [preparationDelegate performSelectorOnMainThread: @selector(preparationDidSucceed) withObject: nil waitUntilDone: NO];
  preparationDelegate = nil;
}

- (void) meshPreparationDidFailWithError: (NSError*) error
{
  if ([preparationDelegate respondsToSelector: @selector(preparationDidFailWithError:)])
    [preparationDelegate performSelectorOnMainThread: @selector(preparationDidFailWithError:) withObject: error waitUntilDone: NO];
  preparationDelegate = nil;
  initializationFailed = YES;
}


#pragma mark Prepare Model

- (void) prepareModelWithDelegate: (id) delegate
{
  preparationCancelled = NO;
  preparationDelegate = delegate;

  self.downloaded = YES;
  
  // Start mesh initialization in a second thread.  We need the UI to stay alive so we can
  // cancel the mesh preparation and so we can receive low memory warnings.
  [NSThread detachNewThreadSelector: @selector(prepareMeshes) toTarget: self withObject: nil];
}

- (void) cancelModelPreparation
{
  // The preparation commands will check this variable and return a NSError
  preparationCancelled = YES;
}


- (void) cancelModelPreparationSilently
{
  // The preparation commands will check this variable and return a NSError
  preparationCancelled = YES;
}


#pragma mark Current model

// we are becoming the current model
- (BOOL) becomeCurrentModel
{
  return [self isDownloaded];
}

// We are no longer the current model
- (void) resignCurrentModel
{
  [self cancelModelPreparationSilently];
  [self performSelector: @selector(cleanUp) withObject: nil afterDelay: 0.1];
}

@end


// This function is called right after reading the 3DM properties.  We construct a
// modelID string from the ON_3dmRevisionHistory and ON_3dmApplication objects with
// the hope that this will uniquely identify the file contents.  If the user changes
// the file contents, we should be able to detect this because the constructed modelID
// string will also change.
void EX_ONX_Model::InspectProperties (ON_3dmProperties& properties)
{
  ON_wString revisionIDString;
  ON_TextLog revisionIDLog ( revisionIDString );
  properties.m_RevisionHistory.Dump(revisionIDLog);
  NSString* revisionID = w2ns(revisionIDString);
  
  ON_wString appIDString;
  ON_TextLog appIDLog ( appIDString );
  properties.m_Application.Dump(appIDLog);
  NSString* appID = w2ns(appIDString);
  if (appID == nil)
    appID = @"Name: Unknown\n";
  
  RhModel* currentModel = RhinoApp.currentModel;
  [currentModel setModelID: [revisionID stringByAppendingString: appID]];
}


//
// We create a DisplayMesh object for each render mesh object we find.  If we encounter an ON_Mesh object,
// we create a DisplayMesh object from the ON_Mesh. For any ON_Brep objects, we create Displaymesh objects
// from the render mesh.  To conserve memory, we always return 0 which tells the object reading code
// to discard the object it has just read.
//
// This function returns +1 to keep object; 0 to discard object; -1 to stop reading file
//
int EX_ONX_Model::ShouldKeepObject (ON_Object* pObject, ON_3dmObjectAttributes& attr)
{
  RhModel* currentModel = RhinoApp.currentModel;
  [currentModel.continueReadingLock lock];
  int shouldContinue = currentModel.continueReading;
  [currentModel.continueReadingLock unlock];
  
  if (shouldContinue == 0) {
    DLog (@"saw outOfMemoryWarning, quitting ShouldKeepObject");
    return -1;
  }
  
  if ([currentModel preparationCancelled])
    return -1;
  
  // ensure the object is visible
  if (!attr.IsVisible())
    return 0;
  
  // ensure the object's layer is visible
  int layerIndex = attr.m_layer_index;
  if (layerIndex >= 0 && layerIndex < m_layer_table.Count()) {
    ON_Layer& layer =  m_layer_table[layerIndex];
    if (!layer.IsVisible())
      return 0;
  }
  
  // calculate bounding box as we read objects
  const ON_Geometry* geo = ON_Geometry::Cast(pObject);
  if ( geo ) {
    currentModel.geometryCount++;
    m__object_table_bbox.Union(geo->BoundingBox());
  }
  
  if (pObject->ObjectType() == ON::mesh_object) {
    ON_Mesh* mesh = (ON_Mesh*) pObject;
    if ( 0 == mesh->HiddenVertexCount() )
      mesh->DestroyHiddenVertexArray();
    
    if ( !mesh->HasVertexNormals() && mesh->m_V.Count() > 0 && mesh->m_F.Count() > 0) {
      // 26 September 2003 Dale Lear - 
      //   Some 3dm files have meshes with no normals and this messes up the shading code.
      mesh->ComputeVertexNormals();
    }
    
    [currentModel addMeshObject: mesh withAttributes: attr];
    return 0;       // do not keep ON::mesh_object
  }
  else if (pObject->ObjectType() == ON::brep_object) {
    currentModel.brepCount++;
    ON_Brep* pBrep = (ON_Brep*) pObject;
    ON_SimpleArray< const ON_Mesh* > meshes;
    int count = pBrep->GetMesh( ON::render_mesh, meshes );
    if (count > 0)
      currentModel.brepWithMeshCount++;
    
    if ( count == 1 )
    {
      if ( meshes[0] && meshes[0]->VertexCount() )
        [currentModel addRenderMesh: meshes[0] withAttributes: attr];
    }
    else
    {
      ON_Mesh  m;
      
      // Sometimes it's possible to have lists of NULL ON_Meshes...Rhino
      // can put them there as placeholders for badly formed/meshed breps.
      // Therefore, we need to always make sure we're actually looking at
      // a mesh that contains something and/or is not NULL.
      for (int i = 0; i < count; i++)
      {
        // If we have a valid pointer, append the mesh to our accumulator mesh...
        if ( meshes[i] )
          m.Append( *meshes[i] );
      }
      
      // See if the end result actually contains anything and add it to
      // our model if it does...
      if ( m.VertexCount() > 0 )
        [currentModel addRenderMesh: &m withAttributes: attr];
    }

    return 0;       // do not keep ON::brep_object
  }
  else if (pObject->ObjectType() == ON::extrusion_object) {
    // extrusion objects do not have a mesh
    return 0;       // do not keep ON::extrusion_object
  }
  else {
    return 0;       // do not keep anything else
  }
}

