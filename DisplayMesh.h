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

//
// This class builds OpenGL vertex buffer objects for an ON_Mesh and draws the mesh when requested
//

#include "ESRenderer.h"

typedef struct {
  ON_3fPoint    vertex;
  ON_3fVector    normal;
} VertexData;

typedef struct {
  ON_3fPoint    vertex;
  ON_3fVector   normal;
  ON_4fPoint    color;
} VNCData;

typedef struct {
  ON_3fPoint    vertex;
  ON_4fPoint    color;
} VCData;



@interface DisplayMesh : NSObject {

  ON_Color pickColor;
  BOOL selected;

  ON_Material material;
  int partitionIndex;
  ON_BoundingBox boundingBox;
  BOOL hasVertexNormals;
  BOOL hasVertexColors;
  BOOL initializationFailed;
  unsigned int stride;
  
  unsigned int vertexIndexCount;
  unsigned int triangleCount;
  BOOL isClosed;
  
  // OpenGL vertex buffers
  unsigned int vertexBuffer;
  unsigned int normalBuffer;
  unsigned int indexBuffer;
  
  bool captureVBOData;
  NSData* vertexBufferData;
  NSData* normalBufferData;
  NSData* vertexAndNormalBufferData;
  NSData* indexBufferData;
}

@property (nonatomic, assign) bool captureVBOData;
@property (nonatomic, assign) unsigned int vertexBuffer;
@property (nonatomic, assign) unsigned int normalBuffer;
@property (nonatomic, assign) unsigned int indexBuffer;
@property (nonatomic, assign) ON_Material material;
@property (nonatomic, assign) BOOL isClosed;
@property (nonatomic, assign) BOOL hasVertexNormals;
@property (nonatomic, assign) BOOL hasVertexColors;
@property (nonatomic, assign) unsigned int Stride;

@property (nonatomic, assign) ON_Color pickColor;
@property (nonatomic, assign) BOOL selected;

- (id) initWithMesh: (const ON_Mesh*) mesh index: (int) index material: (const ON_Material&) material saveVBOData: (BOOL) saveVBOData;
- (void) restoreUsingMesh: (const ON_Mesh*) onMesh material: (const ON_Material&) onMaterial;

- (unsigned int) triangleCount;
- (BOOL) isOpaque;
- (BOOL) hasVertexNormals;
- (BOOL) hasVertexColors;
- (unsigned int) Stride;

// Encode / decode mesh VBOs using aCoder
- (void)encodeWithCoder: (NSCoder*) aCoder;
- (id)initWithCoder: (NSCoder *) decoder;

- (void) reloadVBOData;
- (void) deleteVBOData;

@end
