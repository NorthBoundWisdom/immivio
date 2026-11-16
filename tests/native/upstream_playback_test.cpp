#include <immivio/mpv/aaudio_clock.h>
#include <immivio/mpv/source_limits.h>
#include <cassert>
int main() {
  assert(immivio::source_dimensions_supported(8192,4320));
  assert(!immivio::source_dimensions_supported(8193,1));
  assert(!immivio::source_dimensions_supported(8192,8192));
  assert(!immivio::source_dimensions_supported(INT64_MAX,INT64_MAX));
  int64_t last=0,gap=0;
  auto played=immivio_aaudio_played(&last,&gap,1,48000,1000000000LL,1050000000LL,900000000LL,51000,96000,0,48000);
  assert(played==50400 && gap==600);
  // Timestamp gaps advance from frames consumed rather than freezing the clock.
  played=immivio_aaudio_played(&last,&gap,0,0,0,1060000000LL,900000000LL,52000,96000,0,48000);
  assert(played==51400);
  // A stale pre-resume timestamp must not project paused time into playback.
  played=immivio_aaudio_played(&last,&gap,1,100,1000000000LL,1100000000LL,1050000000LL,200,500,0,48000);
  assert(played==100);
  // Extrapolation cannot claim samples which have not been submitted.
  played=immivio_aaudio_played(&last,&gap,1,400,1000000000LL,1100000000LL,0,500,500,0,48000);
  assert(played==500);
}
