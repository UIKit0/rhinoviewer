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
#include <iostream>

#include "RhGLShaderProgram.h"

CRhGLShaderProgram::CRhGLShaderProgram()

  : m_hProgram( 0 )
{
}

CRhGLShaderProgram::~CRhGLShaderProgram()
{
  if ( m_hProgram != 0 )
  {
    glDeleteProgram( m_hProgram );
    m_hProgram = 0;
  }
}

///////////////////////////////////////////////////////////////////////////
//
static void Mat4Dto4F(double* d, float* f)
{
  f[0]  = d[0];  f[1]  = d[1];  f[2]  = d[2];  f[3]  = d[3];
  f[4]  = d[4];  f[5]  = d[5];  f[6]  = d[6];  f[7]  = d[7];
  f[8]  = d[8];  f[9]  = d[9];  f[10] = d[10]; f[11] = d[11];
  f[12] = d[12]; f[13] = d[13]; f[14] = d[14]; f[15] = d[15];
}

////////////////////////////////////////////////////////////////////////////
//
static void Mat4Dto3F(double* d, float* f)
{
  f[0] = d[0]; f[1] = d[1]; f[2] = d[2];
  f[3] = d[4]; f[4] = d[5]; f[5] = d[6];
  f[6] = d[8]; f[7] = d[9]; f[8] = d[10];
}

//////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::Enable(void)
{
  glUseProgram( m_hProgram );
  PreRun();
}

//////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::Disable(void)
{
  PostRun();
  glUseProgram( 0 );
}

//////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::SetupViewport(const ON_Viewport& vp)
{
  ON_Xform  mv;
  bool      bHaveModeView = false;
  
  if ( m_Uniforms.rglModelViewProjectionMatrix >= 0 )
  {
    float    ModelViewProjection[16];
    ON_Xform mvp;
    
    vp.GetXform( ON::world_cs, ON::clip_cs, mvp );
    mvp.Transpose();
    
    Mat4Dto4F( &mvp.m_xform[0][0], ModelViewProjection );
    glUniformMatrix4fv( m_Uniforms.rglModelViewProjectionMatrix, 1, GL_FALSE, ModelViewProjection );
  }
    
  if ( m_Uniforms.rglModelViewMatrix >= 0 )
  {
    float  ModelView[16];
    
    vp.GetXform( ON::world_cs, ON::camera_cs, mv );
    mv.Transpose();
    bHaveModeView = true;
    
    Mat4Dto4F( &mv.m_xform[0][0], ModelView );
    glUniformMatrix4fv( m_Uniforms.rglModelViewMatrix, 1, GL_FALSE, ModelView );
  }

  if ( m_Uniforms.rglProjectionMatrix >= 0 )
  {
    float     Projection[16];
    ON_Xform  pr;
  
    vp.GetXform( ON::camera_cs, ON::clip_cs,  pr );
    pr.Transpose();
 
    Mat4Dto4F( &pr.m_xform[0][0], Projection );
    glUniformMatrix4fv( m_Uniforms.rglProjectionMatrix, 1, GL_FALSE, Projection );
  }
 
  if ( m_Uniforms.rglNormalMatrix >= 0 )
  {
    float    NormalMatrix[9];
    
    if ( !bHaveModeView )
    {
      vp.GetXform( ON::world_cs, ON::camera_cs, mv );
      mv.Transpose();
      bHaveModeView = true;
    }
    
    Mat4Dto3F( &mv.m_xform[0][0], NormalMatrix );
    glUniformMatrix3fv( m_Uniforms.rglNormalMatrix, 1, GL_FALSE, NormalMatrix );
  }
}

//////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::SetupLight(const ON_Light& light)
{
  GLfloat amb[4]  = { light.Ambient().FractionRed(),  light.Ambient().FractionGreen(),  light.Ambient().FractionBlue(),  1.0f };
  GLfloat diff[4] = { light.Diffuse().FractionRed(),  light.Diffuse().FractionGreen(),  light.Diffuse().FractionBlue(),  1.0f };
  GLfloat spec[4] = { light.Specular().FractionRed(), light.Specular().FractionGreen(), light.Specular().FractionBlue(), 1.0f };
  float   pos[3]  = { light.Direction().x, light.Direction().y, light.Direction().z };
  
  if ( m_Uniforms.rglLightAmbient >= 0 )
    glUniform4fv( m_Uniforms.rglLightAmbient, 1, amb );
  if ( m_Uniforms.rglLightDiffuse >= 0 )
    glUniform4fv( m_Uniforms.rglLightDiffuse, 1, diff );
  if ( m_Uniforms.rglLightSpecular >= 0 )
    glUniform4fv( m_Uniforms.rglLightSpecular, 1, spec );
  if ( m_Uniforms.rglLightPosition >= 0 )
    glUniform3fv( m_Uniforms.rglLightPosition, 1, pos );
}

//////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::SetupMaterial(const ON_Material& mat)
{
  ON_Color dcolor  = mat.Diffuse();
  ON_Color scolor  = mat.Specular();
  ON_Color ecolor  = mat.Emission();
  
  GLfloat alpha    = (GLfloat)(1.0 - mat.Transparency());
  GLfloat shine    = 128.0*(mat.Shine() / ON_Material::MaxShine());
  GLfloat black[4] = {0.0,0.0,0.0,1.0};
  GLfloat ambi[4]  = { mat.Ambient().FractionRed(), mat.Ambient().FractionGreen(), mat.Ambient().FractionBlue(), mat.m_ambient.FractionAlpha() };
  GLfloat diff[4]  = { dcolor.FractionRed(), dcolor.FractionGreen(), dcolor.FractionBlue(), alpha };
  GLfloat spec[4]  = { scolor.FractionRed(), scolor.FractionGreen(), scolor.FractionBlue(), 1.0f };
  GLfloat emmi[4]  = { ecolor.FractionRed(), ecolor.FractionGreen(), ecolor.FractionBlue(), 1.0f };
  GLfloat* pspec   = shine?spec:black;
  
  if ( m_Uniforms.rglLightAmbient >= 0) {
    if (mat.m_ambient.Alpha() > 0)
      glUniform4fv( m_Uniforms.rglLightAmbient, 1, ambi );
    else
      glUniform4fv( m_Uniforms.rglLightAmbient, 1, black );
  }
  if ( m_Uniforms.rglDiffuse >= 0 )
    glUniform4fv( m_Uniforms.rglDiffuse, 1, diff );
  if ( m_Uniforms.rglSpecular >= 0 )
    glUniform4fv( m_Uniforms.rglSpecular, 1, pspec );
  if ( m_Uniforms.rglEmission >= 0 )
    glUniform4fv( m_Uniforms.rglEmission, 1, emmi );
  if ( m_Uniforms.rglShininess >= 0 )
    glUniform1f( m_Uniforms.rglShininess,  shine );
  if ( m_Uniforms.rglUsesColors >= 0 )
    glUniform1i( m_Uniforms.rglUsesColors,  0 );
  
  if (alpha < 1.0)
    glEnable( GL_BLEND );
  else
    glDisable( GL_BLEND );
}

//////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::EnableColorUsage(bool  bEnable)
{
  if ( m_Uniforms.rglUsesColors >= 0 )
    glUniform1i( m_Uniforms.rglUsesColors,  bEnable?1:0 );
}

///////////////////////////////////////////////////////////////////////////
//
bool CRhGLShaderProgram::BuildProgram(const GLchar* VertexShader, const GLchar* FragmentShader)
{
  // Shaders MUST consist of both a vertex AND a fragment shader in 2.0...
  if ( (VertexShader == NULL) || (FragmentShader == NULL) )
    return false;
  
  PreBuild();
  
  GLuint  hVsh = BuildShader( VertexShader, GL_VERTEX_SHADER );
  GLuint  hFsh = BuildShader( FragmentShader, GL_FRAGMENT_SHADER );
  
  if ( (hVsh == 0) || (hFsh == 0) )
    return false;
  
  m_hProgram = glCreateProgram();
  if ( m_hProgram == 0 )
    return false;
  
  glAttachShader( m_hProgram, hVsh );
  glAttachShader( m_hProgram, hFsh );

  // These bindings are forced here so that mesh drawing can enable the
  // appropriate vertex array based on the same binding values. 
  // Note: These must be done before we attempt to link the program...
  // Note2: Rhino supports multiple textures but for now we'll only
  //        provide for a single set of texture coordinates.
  glBindAttribLocation( m_hProgram, ATTRIB_VERTEX,    "rglVertex" );
	glBindAttribLocation( m_hProgram, ATTRIB_NORMAL,    "rglNormal" );
	glBindAttribLocation( m_hProgram, ATTRIB_TEXCOORD0, "rglTexCoord0" );
	glBindAttribLocation( m_hProgram, ATTRIB_COLOR,     "rglColor"  );
  
  glLinkProgram( m_hProgram );

  GLint Success;
  
  glGetProgramiv( m_hProgram, GL_LINK_STATUS, &Success );
  if ( Success == GL_FALSE ) 
  {
#if defined(_DEBUG)
    GLint logLength;
    glGetProgramiv( m_hProgram, GL_INFO_LOG_LENGTH, &logLength );
    if (logLength > 0)
    {
      GLchar *log = (GLchar *)malloc(logLength);
      glGetProgramInfoLog( m_hProgram, logLength, &logLength, log);
      std::cout << "Program link log:\n" << log;
      free(log);
    }
#endif
    glDetachShader( m_hProgram, hVsh );
    glDetachShader( m_hProgram, hFsh );
    glDeleteProgram( m_hProgram );
    m_hProgram = 0;
  }
  
  glDeleteShader( hVsh );
  glDeleteShader( hFsh );
  
  if ( m_hProgram == 0 )
    return false;
  
  PostBuild();
  
  return true;
}

///////////////////////////////////////////////////////////////////////////
//
GLuint CRhGLShaderProgram::BuildShader(const GLchar* Source, GLenum Type)
{
  GLuint hShader = glCreateShader( Type );
  
  glShaderSource( hShader, 1, &Source, 0 );
  glCompileShader( hShader );

  GLint Success;
  glGetShaderiv( hShader, GL_COMPILE_STATUS, &Success );

  if ( Success == GL_FALSE ) 
  {
#if defined(_DEBUG)
    GLint logLength;
    glGetShaderiv( hShader, GL_INFO_LOG_LENGTH, &logLength );
    if (logLength > 0)
    {
      GLchar *log = (GLchar *)malloc(logLength);
      glGetShaderInfoLog( hShader, logLength, &logLength, log);
      std::cout << "Shader compile log:\n" << log;
      free(log);
    }
#endif
    glDeleteShader( hShader );
    hShader = 0;
  }

  return hShader;
}

///////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::PreBuild(void)
{
}

///////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::PostBuild(void)
{
  ResolvePredefines();
}

///////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::PreRun(void)
{
}

///////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::PostRun(void)
{
}


///////////////////////////////////////////////////////////////////////////
//
void CRhGLShaderProgram::ResolvePredefines(void)
{
  m_Attributes.rglVertex    = glGetAttribLocation( m_hProgram, "rglVertex" );
  m_Attributes.rglNormal    = glGetAttribLocation( m_hProgram, "rglNormal" );
  m_Attributes.rglTexCoord0 = glGetAttribLocation( m_hProgram, "rglTexCoord0" );
  m_Attributes.rglColor     = glGetAttribLocation( m_hProgram, "rglColor" );

  m_Uniforms.rglModelViewMatrix           = glGetUniformLocation( m_hProgram, "rglModelViewMatrix" );
  m_Uniforms.rglProjectionMatrix          = glGetUniformLocation( m_hProgram, "rglProjectionMatrix" );
  m_Uniforms.rglNormalMatrix              = glGetUniformLocation( m_hProgram, "rglNormalMatrix" );
  m_Uniforms.rglModelViewProjectionMatrix = glGetUniformLocation( m_hProgram, "rglModelViewProjectionMatrix" );
  
  m_Uniforms.rglDiffuse   = glGetUniformLocation( m_hProgram, "rglDiffuse" );
  m_Uniforms.rglSpecular  = glGetUniformLocation( m_hProgram, "rglSpecular" );
  m_Uniforms.rglEmission  = glGetUniformLocation( m_hProgram, "rglEmission" );
  m_Uniforms.rglShininess = glGetUniformLocation( m_hProgram, "rglShininess" );
  m_Uniforms.rglUsesColors = glGetUniformLocation( m_hProgram, "rglUsesColors" );
  
  m_Uniforms.rglLightAmbient  = glGetUniformLocation( m_hProgram, "rglLightAmbient" );
  m_Uniforms.rglLightDiffuse  = glGetUniformLocation( m_hProgram, "rglLightDiffuse" );
  m_Uniforms.rglLightSpecular = glGetUniformLocation( m_hProgram, "rglLightSpecular" );
  m_Uniforms.rglLightPosition = glGetUniformLocation( m_hProgram, "rglLightPosition" );
}
