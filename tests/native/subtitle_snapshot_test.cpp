#include <immivio/mpv/subtitle_snapshot.h>
#include <cassert>
#include <iostream>
int main() {
  using quest::subtitle_cue_json;
  for (const auto *codec : {"subrip", "ass", "webvtt", "mov_text"}) assert(quest::text_subtitle_codec(codec));
  for (const auto *codec : {"hdmv_pgs_subtitle", "dvd_subtitle", ""}) assert(!quest::text_subtitle_codec(codec));
  const auto first = subtitle_cue_json(8, 3, "2", "0.500", "Primary", "1", "2", true);
  const auto second = subtitle_cue_json(8, 7, "4", "0.500", "第二字幕\nEnglish", "1", "3", true);
  assert(first.find("\"command_id\":3") != std::string::npos);
  assert(second.find("\"command_id\":7") != std::string::npos);
  assert(second.find("\"track_id\":\"4\"") != std::string::npos);

  assert(first.find("\"subtitle_delay_seconds\":\"0.500\"") != std::string::npos);
  const auto invalid = subtitle_cue_json(9, 7, "4", "0.500", "stale", "1", "3", false);
  assert(invalid.find("stale") == std::string::npos);
  assert(invalid.find("\"text\":\"\"") != std::string::npos);
  assert(invalid.find("\"sequence\":9") != std::string::npos);
  std::cout << first << "\n" << second << "\n" << invalid << "\n";
}
