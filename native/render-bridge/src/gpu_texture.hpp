#pragma once
#include "gl_state.hpp"
#include <string>

namespace immivio::render {
constexpr const char *vertex = R"(#version 300 es
out highp vec2 uv;
void main() {
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    uv = p; gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
})";
constexpr const char *copy_2d_fragment = R"(#version 300 es
precision highp float;
uniform sampler2D source;
in highp vec2 uv; out vec4 result;
void main() { result = vec4(texture(source, uv).rgb, 1.0); }
)";
// Canonical decoder rows, unlike the Android SurfaceTexture transform above.
inline GLuint shader(GLenum kind, const char *source) {
  const GLuint id = glCreateShader(kind);
  glShaderSource(id, 1, &source, nullptr);
  glCompileShader(id);
  GLint passed = 0;
  glGetShaderiv(id, GL_COMPILE_STATUS, &passed);
  if (!passed) {
    char log[1024]{};
    glGetShaderInfoLog(id, sizeof(log), nullptr, log);
    glDeleteShader(id);
    throw std::runtime_error(std::string("Render bridge shader: ") + log);
  }
  return id;
}
inline GLuint program(const char *fragment) {
  const auto vs = shader(GL_VERTEX_SHADER, vertex);
  GLuint fs = 0;
  try {
    fs = shader(GL_FRAGMENT_SHADER, fragment);
  } catch (...) {
    glDeleteShader(vs);
    throw;
  }
  const auto id = glCreateProgram();
  glAttachShader(id, vs);
  glAttachShader(id, fs);
  glLinkProgram(id);
  glDeleteShader(vs);
  glDeleteShader(fs);
  GLint passed = 0;
  glGetProgramiv(id, GL_LINK_STATUS, &passed);
  if (!passed) {
    glDeleteProgram(id);
    throw std::runtime_error("Render bridge program linking failed");
  }
  return id;
}
inline void image(GLuint &id, int width, int height, GLenum format = GL_RGBA8) {
  glGenTextures(1, &id);
  glBindTexture(GL_TEXTURE_2D, id);
  glTexStorage2D(GL_TEXTURE_2D, 1, format, width, height);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}
} // namespace immivio::render
