#pragma once
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <android/log.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <stdexcept>

namespace immivio::render {
inline void check_gl(const char* operation) {
    const auto error = glGetError();
    if (error == GL_NO_ERROR) return;
    char message[160];
    std::snprintf(message, sizeof(message), "%s: GL error 0x%04x", operation, error);
    throw std::runtime_error(message);
}
// Godot and this bridge share a context, hence also a GL error queue. Attribute errors
// at the interop boundary: report inherited errors separately, then check our own work.
// A stale engine/probe error must not turn a no-op borrowed capture into a copy failure.
inline thread_local uint64_t owner_gl_errors = 0;
inline thread_local GLenum owner_gl_last_error = GL_NO_ERROR;
inline void isolate_owner_errors() {
    for (int i = 0; i < 8; ++i) {
        const auto error = glGetError();
        if (error == GL_NO_ERROR) return;
        if (error == GL_CONTEXT_LOST_KHR) throw std::runtime_error("Render bridge GL context lost");
        ++owner_gl_errors; owner_gl_last_error = error;
#ifndef NDEBUG
        if (owner_gl_errors <= 4 || (owner_gl_errors & (owner_gl_errors - 1)) == 0)
            __android_log_print(ANDROID_LOG_WARN, "QuestGlOwner", "Inherited owner GL error 0x%04x (count=%llu)",
                error, static_cast<unsigned long long>(owner_gl_errors));
#endif
    }
    throw std::runtime_error("Render bridge owner GL error queue did not clear");
}
// Touch only private objects and unit zero; restore Godot's actual GL state.
struct State final {
    GLint program, vao, draw_fbo, read_fbo, active, tex2d, oes, sampler, pack, unpack;
    GLint viewport[4];
    GLint pack_alignment, pack_row_length, pack_skip_rows, pack_skip_pixels;
    GLint unpack_alignment, unpack_row_length, unpack_skip_rows, unpack_skip_pixels, unpack_image_height, unpack_skip_images;
    GLboolean mask[4];
    static constexpr std::array<GLenum, 10> toggles{{GL_BLEND, GL_DEPTH_TEST, GL_CULL_FACE, GL_SCISSOR_TEST,
        GL_STENCIL_TEST, GL_DITHER, GL_RASTERIZER_DISCARD, GL_SAMPLE_ALPHA_TO_COVERAGE, GL_SAMPLE_COVERAGE,
        GL_POLYGON_OFFSET_FILL}};
    std::array<GLboolean, toggles.size()> enabled;
    State() {
        isolate_owner_errors();
        glGetIntegerv(GL_CURRENT_PROGRAM, &program); glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw_fbo); glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fbo);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &active); glActiveTexture(GL_TEXTURE0);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &tex2d); glGetIntegerv(GL_TEXTURE_BINDING_EXTERNAL_OES, &oes);
        glGetIntegerv(GL_SAMPLER_BINDING, &sampler); glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack);
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpack);
        glGetIntegerv(GL_VIEWPORT, viewport); glGetBooleanv(GL_COLOR_WRITEMASK, mask);
        glGetIntegerv(GL_PACK_ALIGNMENT, &pack_alignment); glGetIntegerv(GL_PACK_ROW_LENGTH, &pack_row_length);
        glGetIntegerv(GL_PACK_SKIP_ROWS, &pack_skip_rows); glGetIntegerv(GL_PACK_SKIP_PIXELS, &pack_skip_pixels);
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpack_alignment); glGetIntegerv(GL_UNPACK_ROW_LENGTH, &unpack_row_length);
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &unpack_skip_rows); glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &unpack_skip_pixels);
        glGetIntegerv(GL_UNPACK_IMAGE_HEIGHT, &unpack_image_height); glGetIntegerv(GL_UNPACK_SKIP_IMAGES, &unpack_skip_images);
        for (size_t i = 0; i < toggles.size(); ++i) enabled[i] = glIsEnabled(toggles[i]);
        glBindSampler(0, 0); glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
        glPixelStorei(GL_PACK_ALIGNMENT, 1); glPixelStorei(GL_PACK_ROW_LENGTH, 0);
        glPixelStorei(GL_PACK_SKIP_ROWS, 0); glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1); glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0); glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
        glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, 0); glPixelStorei(GL_UNPACK_SKIP_IMAGES, 0);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        for (auto toggle : toggles) glDisable(toggle);
    }
    ~State() {
        glUseProgram(program); glBindVertexArray(vao);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw_fbo); glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fbo);
        glViewport(viewport[0], viewport[1], viewport[2], viewport[3]); glColorMask(mask[0], mask[1], mask[2], mask[3]);
        for (size_t i = 0; i < toggles.size(); ++i) { if (enabled[i]) glEnable(toggles[i]); else glDisable(toggles[i]); }
        glBindBuffer(GL_PIXEL_PACK_BUFFER, pack); glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack);
        glPixelStorei(GL_PACK_ALIGNMENT, pack_alignment); glPixelStorei(GL_PACK_ROW_LENGTH, pack_row_length);
        glPixelStorei(GL_PACK_SKIP_ROWS, pack_skip_rows); glPixelStorei(GL_PACK_SKIP_PIXELS, pack_skip_pixels);
        glPixelStorei(GL_UNPACK_ALIGNMENT, unpack_alignment); glPixelStorei(GL_UNPACK_ROW_LENGTH, unpack_row_length);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, unpack_skip_rows); glPixelStorei(GL_UNPACK_SKIP_PIXELS, unpack_skip_pixels);
        glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, unpack_image_height); glPixelStorei(GL_UNPACK_SKIP_IMAGES, unpack_skip_images);
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, tex2d); glBindTexture(GL_TEXTURE_EXTERNAL_OES, oes);
        glBindSampler(0, sampler); glActiveTexture(active);
    }
};
struct CaptureTiming final {
    uint64_t &calls, &total_us, &max_us;
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    CaptureTiming(uint64_t& count, uint64_t& total, uint64_t& maximum) : calls(count), total_us(total), max_us(maximum) {}
    ~CaptureTiming() {
        const auto us = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - start).count());
        ++calls; total_us += us; max_us = std::max(max_us, us);
    }
};
} // namespace immivio::render
