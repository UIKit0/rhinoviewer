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

#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

//////////////////////////////////////////////////////////////
struct RhGLPredefinedUniforms
{
  GLint   rglModelViewMatrix;
  GLint   rglProjectionMatrix;
  GLint   rglNormalMatrix;
  GLint   rglModelViewProjectionMatrix;
  
  GLint   rglDiffuse;
  GLint   rglSpecular;
  GLint   rglEmission;
  GLint   rglShininess;
  GLint   rglUsesColors;
  
  GLint   rglLightAmbient;
  GLint   rglLightDiffuse;
  GLint   rglLightSpecular;
  GLint   rglLightPosition;
};


//////////////////////////////////////////////////////////////
struct RhGLPredefinedAttributes
{
  GLint   rglVertex;
  GLint   rglNormal;
  GLint   rglTexCoord0;
  GLint   rglColor;
};

enum 
{
	ATTRIB_VERTEX,
  ATTRIB_NORMAL,
  ATTRIB_TEXCOORD0,
	ATTRIB_COLOR,
	NUM_ATTRIBUTES
};


//////////////////////////////////////////////////////////////
class CRhGLShaderProgram
{
public:
    CRhGLShaderProgram();
   ~CRhGLShaderProgram();
  
public:
  void   Enable(void);
  void   Disable(void);
  GLuint Handle(void) { return m_hProgram; }
  void   SetupViewport(const ON_Viewport&);
  void   SetupLight(const ON_Light&);
  void   SetupMaterial(const ON_Material&);
  void   EnableColorUsage(bool bEnable);
  
public:
  bool  BuildProgram(const GLchar* VertexShader, const GLchar* FragmentShader);
  
  virtual
  void  PreBuild(void);
  
  virtual
  void  PostBuild(void);
  
  virtual 
  void  PreRun(void);
  
  virtual
  void  PostRun(void);
  
protected:
  GLuint                    m_hProgram;
  RhGLPredefinedAttributes  m_Attributes;
  RhGLPredefinedUniforms    m_Uniforms;

protected:
  GLuint  BuildShader(const GLchar* Source, GLenum  Type);
  void    ResolvePredefines(void);
};