#pragma once
#include <GLES3/gl3.h>
#include <jni.h>

namespace immivio::render {
enum class Phase { free, copying, held, retiring };
// A borrowed texture is never deleted by the consumer. Its producer stays leased
// until the owner's retirement acknowledgement observes the consumer fence.
struct Slot {
    GLuint color = 0, alpha = 0, borrowed = 0;
    GLsync fence = nullptr;
    bool alpha_valid = false, opaque_cached = false;
    Phase phase = Phase::free;
    jlong token = 0;
    GLuint source() const { return borrowed ? borrowed : color; }
};
} // namespace immivio::render
