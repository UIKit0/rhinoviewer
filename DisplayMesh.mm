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

#import "DisplayMesh.h"
#import "ESRenderer.h"

#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>



@implementation DisplayMesh

@synthesize captureVBOData;
@synthesize vertexBuffer, normalBuffer, indexBuffer, material, isClosed, hasVertexNormals, hasVertexColors, Stride;
@synthesize pickColor, selected;

- (void) deleteBuffers
{
  if (vertexBuffer)
    glDeleteBuffers (1, &vertexBuffer);
  if (normalBuffer)
    glDeleteBuffers (1, &normalBuffer);
  if (indexBuffer)
    glDeleteBuffers (1, &indexBuffer);
}

- (void) deleteVBOData
{
  [vertexBufferData release];
  vertexBufferData = nil;
  [normalBufferData release];
  normalBufferData = nil;
  [vertexAndNormalBufferData release];
  vertexAndNormalBufferData = nil;
  [indexBufferData release];
  indexBufferData = nil;
  
}

- (void) dealloc
{
  [self deleteBuffers];
  [self deleteVBOData];
  [super dealloc];
}


#pragma mark Accessors

- (BOOL) hasVertexNormals
{
  return hasVertexNormals;
}


- (BOOL) hasVertexColors
{
  return hasVertexColors;
}


- (unsigned int) triangleCount
{
  return triangleCount;
}

- (unsigned int) Stride
{
  return stride;
}


- (BOOL) isOpaque
{
  return material.Transparency() == 0;
}


#pragma mark Create VBOs

// Create a OpenGL VBO for the vertices of the ON_Mesh mesh object
- (bool) createVertexVBO: (const ON_Mesh*) mesh index: (int) idx
{
  const ON_MeshPartition* partition = mesh->Partition();
  const struct ON_MeshPart& part = partition->m_part[idx];

  while (glGetError())
    ;   // clear existing errors
  
  stride = sizeof(ON_3fPoint);
  glGenBuffers(1, &vertexBuffer);
  vertexIndexCount = part.vertex_count;
  glBindBuffer (GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData (GL_ARRAY_BUFFER, stride*vertexIndexCount, &mesh->m_V[part.vi[0]], GL_STATIC_DRAW);
  if (glGetError()) {
    if (vertexBuffer)
      glDeleteBuffers (1, &vertexBuffer);
    vertexBuffer = 0;
    return false;
  }
  if (captureVBOData)
    vertexBufferData = [[NSData alloc] initWithBytes: &mesh->m_V[part.vi[0]] length: stride*vertexIndexCount];
  return true;
}


// Create a OpenGL VBO for the vertices of the ON_Mesh mesh object
- (bool) createVertexVBO: (NSData*) vboData
{
  while (glGetError())
    ;   // clear existing errors
  
  stride = sizeof(ON_3fPoint);
  glGenBuffers (1, &vertexBuffer);
  glBindBuffer (GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData (GL_ARRAY_BUFFER, [vboData length], [vboData bytes], GL_STATIC_DRAW);
  if (glGetError()) {
    if (vertexBuffer)
      glDeleteBuffers (1, &vertexBuffer);
    vertexBuffer = 0;
    return false;
  }
  return true;
}


// Create a OpenGL VBO for the normals of the ON_Mesh mesh object
- (bool) createNormalVBO: (ON_Mesh*) mesh index: (int) idx
{
  const ON_MeshPartition* partition = mesh->Partition();
  const struct ON_MeshPart& part = partition->m_part[idx];
  
  while (glGetError())
    ;   // clear existing errors
  
  stride = sizeof(ON_3fVector);
  glGenBuffers (1, &normalBuffer);
  vertexIndexCount = part.vertex_count;
    
  glBindBuffer (GL_ARRAY_BUFFER, normalBuffer);
  glBufferData (GL_ARRAY_BUFFER, stride*vertexIndexCount, mesh->m_N[part.vi[0]], GL_STATIC_DRAW);
  if (glGetError()) {
    if (normalBuffer)
      glDeleteBuffers (1, &normalBuffer);
    normalBuffer = 0;
    return false;
  }
  if (captureVBOData)
    normalBufferData = [[NSData alloc] initWithBytes: &mesh->m_N[part.vi[0]] length: stride*vertexIndexCount];
  return true;
}


// Create a OpenGL VBO for the normals of the ON_Mesh mesh object
- (bool) createNormalVBO: (NSData*) vboData
{
  while (glGetError())
    ;   // clear existing errors
  
  stride = sizeof(ON_3fVector);
  glGenBuffers (1, &normalBuffer);
  glBindBuffer (GL_ARRAY_BUFFER, normalBuffer);
  glBufferData (GL_ARRAY_BUFFER, [vboData length], [vboData bytes], GL_STATIC_DRAW);
  if (glGetError()) {
    if (normalBuffer)
      glDeleteBuffers (1, &normalBuffer);
    normalBuffer = 0;
    return false;
  }
  return true;
}

// Create a OpenGL VBO containing both the vertices and the normals of the ON_Mesh mesh object
- (bool) createVertexAndNormalVBO: (ON_Mesh*) mesh index: (int) idx
{
  const ON_MeshPartition* partition = mesh->Partition();
  const struct ON_MeshPart& part = partition->m_part[idx];
  
  // Create a temporary buffer to hold the VertexData array
  stride = sizeof(VertexData);
  vertexIndexCount = part.vertex_count;
  VertexData* v = (VertexData*) calloc (vertexIndexCount, stride);
  if (v == NULL)
    return false;
  for (int idx=0; idx<vertexIndexCount; idx++) {
    v[idx].vertex = mesh->m_V[part.vi[0]+idx];
    v[idx].normal = mesh->m_N[part.vi[0]+idx];
  }

  // create VBO
  while (glGetError())
    ;   // clear existing errors
  
  glGenBuffers (1, &vertexBuffer);
  glBindBuffer (GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData (GL_ARRAY_BUFFER, stride*vertexIndexCount, v, GL_STATIC_DRAW);

  // check for errors
  if (glGetError()) {
    if (vertexBuffer)
      glDeleteBuffers (1, &vertexBuffer);
    vertexBuffer = 0;
    free (v);
    return false;
  }
  
  if (captureVBOData)
    vertexAndNormalBufferData = [[NSData alloc] initWithBytes: v length: stride*vertexIndexCount];
  free (v);
  return true;
}


// Create a OpenGL VBO containing both the vertices and the normals of the ON_Mesh mesh object
- (bool) createVertexAndNormalVBO: (NSData*) vboData
{
  while (glGetError())
    ;   // clear existing errors
  
  stride = sizeof(VertexData);
  glGenBuffers (1, &vertexBuffer);
  glBindBuffer (GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData (GL_ARRAY_BUFFER, [vboData length], [vboData bytes], GL_STATIC_DRAW);
  if (glGetError()) {
    if (vertexBuffer)
      glDeleteBuffers (1, &vertexBuffer);
    vertexBuffer = 0;
    return false;
  }
  return true;
}

// Create a OpenGL VBO containing vertices, normals and colors from the ON_Mesh mesh object
- (bool) createVNCvbo: (ON_Mesh*) mesh index: (int) idx
{
  const ON_MeshPartition* partition = mesh->Partition();
  const struct ON_MeshPart& part = partition->m_part[idx];
  
  // Create a temporary buffer to hold the VertexData array
  stride = sizeof(VNCData);
  vertexIndexCount = part.vertex_count;
  VNCData* v = (VNCData*) calloc (vertexIndexCount, stride);
  if (v == NULL)
    return false;
  for (int idx=0; idx<vertexIndexCount; idx++) {
    v[idx].vertex = mesh->m_V[part.vi[0]+idx];
    v[idx].normal = mesh->m_N[part.vi[0]+idx];
    
    ON_Color  c = mesh->m_C[part.vi[0]+idx];
    
    v[idx].color.x = c.FractionRed();
    v[idx].color.y = c.FractionGreen();
    v[idx].color.z = c.FractionBlue();
    v[idx].color.w = c.FractionAlpha();
  }
  
  // create VBO
  while (glGetError())
    ;   // clear existing errors
  
  glGenBuffers (1, &vertexBuffer);
  glBindBuffer (GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData (GL_ARRAY_BUFFER, stride*vertexIndexCount, v, GL_STATIC_DRAW);
  
  // check for errors
  if (glGetError()) {
    if (vertexBuffer)
      glDeleteBuffers (1, &vertexBuffer);
    vertexBuffer = 0;
    free (v);
    return false;
  }
  
  if (captureVBOData)
    vertexAndNormalBufferData = [[NSData alloc] initWithBytes: v length: stride*vertexIndexCount];
  free (v);
  return true;
}

// Create a OpenGL VBO containing vertices and colors from the ON_Mesh mesh object
- (bool) createVCvbo: (ON_Mesh*) mesh index: (int) idx
{
  const ON_MeshPartition* partition = mesh->Partition();
  const struct ON_MeshPart& part = partition->m_part[idx];
  
  // Create a temporary buffer to hold the VertexData array
  stride = sizeof(VCData);
  vertexIndexCount = part.vertex_count;
  VCData* v = (VCData*) calloc (vertexIndexCount, stride);
  if (v == NULL)
    return false;
  for (int idx=0; idx<vertexIndexCount; idx++) {
    v[idx].vertex = mesh->m_V[part.vi[0]+idx];
    
    ON_Color  c = mesh->m_C[part.vi[0]+idx];
    
    v[idx].color.x = c.FractionRed();
    v[idx].color.y = c.FractionGreen();
    v[idx].color.z = c.FractionBlue();
    v[idx].color.w = c.FractionAlpha();
  }
  
  // create VBO
  while (glGetError())
    ;   // clear existing errors
  
  glGenBuffers (1, &vertexBuffer);
  glBindBuffer (GL_ARRAY_BUFFER, vertexBuffer);
  glBufferData (GL_ARRAY_BUFFER, stride*vertexIndexCount, v, GL_STATIC_DRAW);
  
  // check for errors
  if (glGetError()) {
    if (vertexBuffer)
      glDeleteBuffers (1, &vertexBuffer);
    vertexBuffer = 0;
    free (v);
    return false;
  }
  
  if (captureVBOData)
    vertexAndNormalBufferData = [[NSData alloc] initWithBytes: v length: stride*vertexIndexCount];
  free (v);
  return true;
}


// Create a OpenGL VBO for the array indices of the ON_Mesh mesh object described by part idx.
- (bool) createIndexVBO: (const ON_Mesh*) mesh index: (int) idx
{
  int i0, i1, i2, j0, j1, j2;
  
  const ON_MeshPartition* partition = mesh->Partition();
  const struct ON_MeshPart& part = partition->m_part[idx];
  
  triangleCount = part.triangle_count;
  vertexIndexCount = part.vertex_count;
  
  int actualTriangleCount = 0;
  // allocate array of unsigned shorts for vertex indexes
  unsigned short* vertexIndexes = (unsigned short*) malloc (triangleCount * 3 * sizeof (unsigned short));
  if (vertexIndexes == NULL)
    return false;

  unsigned short* indexes = vertexIndexes;
  for (unsigned int fi = part.fi[0]; fi < part.fi[1]; fi++) {
    const ON_MeshFace& f = mesh->m_F[fi];
    if (f.IsValid (part.vi[1])) {
      if (f.IsQuad()) {
        // quadrangle - render as two triangles
        ON_3fPoint v[4];
        v[0] = mesh->m_V[f.vi[0]];
        v[1] = mesh->m_V[f.vi[1]];
        v[2] = mesh->m_V[f.vi[2]];
        v[3] = mesh->m_V[f.vi[3]];
        if (v[0].DistanceTo(v[2]) <= v[1].DistanceTo(v[3])) {
          i0 = 0; i1 = 1; i2 = 2;
          j0 = 0; j1 = 2; j2 = 3;
        }
        else {
          i0 = 1; i1 = 2; i2 = 3;
          j0 = 1; j1 = 3; j2 = 0;
        }
      }
      else {
        // single triangle
        i0 = 0; i1 = 1; i2 = 2;
        j0 = j1 = j2 = 0;
      }
      
      // first triangle
      *indexes++ = f.vi[i0]-part.vi[0];
      *indexes++ = f.vi[i1]-part.vi[0];
      *indexes++ = f.vi[i2]-part.vi[0];
      actualTriangleCount++;
      
      if ( j0 != j1 ) {
        // if we have a quad, second triangle
        *indexes++ = f.vi[j0]-part.vi[0];
        *indexes++ = f.vi[j1]-part.vi[0];
        *indexes++ = f.vi[j2]-part.vi[0];
        actualTriangleCount++;
      }
    }
  }

//  DLog (@"after short initialization, indexes:%p, &vertexIndexes[0]:%p &vertexIndexes[%d]:%p fits:%d actualTriangleCount:%d", indexes, vertexIndexes, 3*triangleCount, &vertexIndexes[3*(triangleCount)], indexes==&vertexIndexes[3*(triangleCount)], actualTriangleCount);

  while (glGetError())
    ;   // clear existing errors
  
  glGenBuffers (1, &indexBuffer);
  glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
  glBufferData (GL_ELEMENT_ARRAY_BUFFER, 3 * triangleCount * sizeof (unsigned short), vertexIndexes, GL_STATIC_DRAW);

  if (glGetError()) {
    if (indexBuffer)
      glDeleteBuffers (1, &indexBuffer);
    indexBuffer = 0;
    free (vertexIndexes);
    return false;
  }
  
  if (captureVBOData)
    indexBufferData = [[NSData alloc] initWithBytes: vertexIndexes length: 3 * triangleCount * sizeof (unsigned short)];
  free (vertexIndexes);
  return true;
}


// Create a OpenGL VBO for the array indices of the ON_Mesh mesh object described by part idx.
- (bool) createIndexVBO: (NSData*) vboData
{
  while (glGetError())
    ;   // clear existing errors
  
  glGenBuffers (1, &indexBuffer);
  glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
  glBufferData (GL_ELEMENT_ARRAY_BUFFER, [vboData length], [vboData bytes], GL_STATIC_DRAW);
  if (glGetError()) {
    if (indexBuffer)
      glDeleteBuffers (1, &indexBuffer);
    indexBuffer = 0;
    return false;
  }
  return true;
}

#pragma mark Interleaved Vertex Data version


- (void) makeVBOs: (NSValue*) meshValue
{
  ON_Mesh* mesh = (ON_Mesh*)[meshValue pointerValue];  
  
  bool rc = true;
  if ( mesh->HasVertexColors() )
  {
    if (mesh->HasVertexNormals())
      rc = [self createVNCvbo: mesh index: partitionIndex];
    else
      rc = [self createVCvbo: mesh index: partitionIndex];
  }
  else if (mesh->HasVertexNormals())
    rc = rc && [self createVertexAndNormalVBO: mesh index: partitionIndex];
  else  
    rc = rc && [self createVertexVBO: mesh index: partitionIndex];
  
  rc = rc && [self createIndexVBO: mesh index: partitionIndex];

  initializationFailed = ! rc;
  if (initializationFailed)
    [self deleteBuffers];
}


- (id) initWithMesh: (const ON_Mesh*) onMesh index: (int) index material: (const ON_Material&) onMaterial saveVBOData: (BOOL) saveVBOData
{
  self = [super init];
  if (self) {
    material = onMaterial;
    partitionIndex = index;
    boundingBox = onMesh->BoundingBox();
    hasVertexNormals = onMesh->HasVertexNormals();
    hasVertexColors = onMesh->HasVertexColors();
    initializationFailed = NO;
    captureVBOData = saveVBOData;
    isClosed = NO;
    // set our pick color to a random value (and hopefully different from every other mesh pickColor)
    pickColor.SetFractionalRGBA((float)rand()/RAND_MAX,(float)rand()/RAND_MAX,(float)rand()/RAND_MAX,1.0);
    if ( onMesh->IsClosed() )
      isClosed = YES;
    
    // OpenGL VBOs must be created on the main thread, so do that and wait for it to finish
    [self performSelectorOnMainThread: @selector(makeVBOs:) withObject: [NSValue valueWithPointer: onMesh] waitUntilDone: YES];

    if (initializationFailed) {
      [self release];
      return nil;
    }
    captureVBOData = NO;
  }
  return self;
}

- (void) restoreUsingMesh: (const ON_Mesh*) onMesh material: (const ON_Material&) onMaterial
{
  // these variables are hard to archive so we restore them when reloading the model
  material = onMaterial;
  boundingBox = onMesh->BoundingBox();
}

#pragma mark Archiving

- (void) encodeWithCoder:(NSCoder *)aCoder
{
  if (vertexBufferData)
    [aCoder encodeObject: vertexBufferData forKey: @"IRVertexBufferData"];
  if (normalBufferData)
    [aCoder encodeObject: normalBufferData forKey: @"IRNormalBufferData"];
  if (vertexAndNormalBufferData)
    [aCoder encodeObject: vertexAndNormalBufferData forKey: @"IRVertexAndNormalBufferData"];
  if (indexBufferData)
    [aCoder encodeObject: indexBufferData forKey: @"IRIndexBufferData"];
  [aCoder encodeInt32: vertexIndexCount forKey: @"IRVertexIndexCount"];
  [aCoder encodeInt32: triangleCount forKey: @"IRTriangleCount"];
  [aCoder encodeBool: hasVertexNormals forKey: @"IRHasVertexNormals"];
}


- (void) reloadVBOData
{
  if (vertexBufferData)
    [self createVertexVBO: vertexBufferData];
  if (normalBufferData)
    [self createNormalVBO: normalBufferData];
  if (vertexAndNormalBufferData)
    [self createVertexAndNormalVBO: vertexAndNormalBufferData];
  if (indexBufferData)
    [self createIndexVBO: indexBufferData];
}


- (id)initWithCoder: (NSCoder *) aDecoder
{
  self = [self init];
  if (self) {
    vertexBufferData = [[aDecoder decodeObjectForKey: @"IRVertexBufferData"] retain];
    normalBufferData = [[aDecoder decodeObjectForKey: @"IRNormalBufferData"] retain];
    vertexAndNormalBufferData = [[aDecoder decodeObjectForKey: @"IRVertexAndNormalBufferData"] retain];
    indexBufferData = [[aDecoder decodeObjectForKey: @"IRIndexBufferData"] retain];
    vertexIndexCount = [aDecoder decodeInt32ForKey: @"IRVertexIndexCount"];
    triangleCount = [aDecoder decodeInt32ForKey: @"IRTriangleCount"];
    hasVertexNormals = [aDecoder decodeBoolForKey: @"IRHasVertexNormals"];
    
    // OpenGL VBOs must be created on the main thread, so do that and wait for it to finish
    [self performSelectorOnMainThread: @selector(reloadVBOData) withObject: nil waitUntilDone: YES];
    
    [self deleteVBOData];
  }
  return self;
}

@end
