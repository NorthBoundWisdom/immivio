#pragma once
#include <immivio/mpv/json_quote.h>
#include <cstdint>
#include <string>

namespace quest {
inline bool text_subtitle_codec(const std::string &codec) {
  for (const char *name : {"subrip", "ass", "ssa", "webvtt", "mov_text", "text", "sami", "microdvd",
                           "subviewer", "ttml"})
    if (codec == name)
      return true;
  return false;
}
// Shared by both channels. A seek/epoch invalidation must blank text before publication.
inline std::string subtitle_cue_json(uint64_t sequence, uint64_t command, const std::string &track,
                                     const std::string &delay, const std::string &text,
                                     const std::string &start, const std::string &end,
                                     bool timeline_valid) {
  return "{\"sequence\":" + std::to_string(sequence) +
         ",\"command_id\":" + std::to_string(command) + ",\"track_id\":" + json_quote(track) +
         ",\"subtitle_delay_seconds\":" + json_quote(delay) +
         ",\"text\":" + json_quote(timeline_valid ? text : "") +
         ",\"start_seconds\":" + json_quote(start) + ",\"end_seconds\":" + json_quote(end) + "}";
}
} // namespace quest
