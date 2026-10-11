#include "../seek_trace.h"
#include <cassert>
#include <iostream>

int main() {
    quest::SeekTrace trace;
    trace.consume("ffmpeg/video", "Queued input buffer 0 size=42 ts=10", 1);
    assert(trace.messages == 0);
    trace.started = 1000000;
    trace.consume("demux", "execute seek (to 10 flags 0)", 1001000);
    trace.consume("demux", "seek done", 1002000);
    trace.consume("demux", "append packet to video: size=42 pts=10 dts=9 pos=123", 1003000);
    trace.consume("ffmpeg/video", "hevc_mediacodec: Queued input buffer 3 size=42 ts=10000000", 1010000);
    trace.consume("ffmpeg/video", "hevc_mediacodec: Got output buffer 2 offset=0 size=1 ts=10000000 flags=0", 1120000);
    trace.consume("ffmpeg/video", "No input buffer available, try again later", 1130000);
    trace.consume("ffmpeg/video", "No output buffer available, try again later", 1140000);
    trace.consume("ffmpeg/audio", "Queued input buffer 3 size=99 ts=10000000", 1150000);
    trace.consume("ffmpeg/video", "Queued input buffer invalid size=-1 ts=0", 1160000);
    trace.consume("cplayer", "PRIVATE TITLE AND SUBTITLE TEXT", 1170000);
    assert(trace.demux_start == 1001000 && trace.demux_done == 1002000);
    assert(trace.inputs == 1 && trace.outputs == 1 && trace.input_bytes == 42 && trace.demux_packets == 1);
    assert(trace.no_input == 1 && trace.no_output == 1);
    assert(trace.bins[0].inputs == 1 && trace.bins[1].outputs == 1);
    assert(trace.first_input == 1010000 && trace.first_output == 1120000);
    trace.render_start(1121000, 16000); trace.render_done(1130000, 9000, true, false);
    trace.acquire(1140000); trace.clock(1150000, 10000000, 9990000, false);
    assert(trace.bins[1].render_starts == 1 && trace.bins[1].renders == 1 && trace.bins[1].acquires == 1);
    assert(trace.bins[1].presents == 1 && trace.bins[1].redraws == 0 && trace.bins[1].render_call_us == 9000);
    assert(trace.bins[1].position_us == 10000000 && trace.bins[1].audio_pts_us == 9990000 && trace.bins[1].paused == 0);
    trace.consume("lavf", "append packet to video: size=99 pts=11 dts=10 pos=456", 1200000);
    assert(trace.demux_packets == 2 && trace.bins[2].demux_packets == 1);
    trace.consume("client", "log message buffer overflow", 1201000);
    assert(trace.queue_overflows == 1);
    trace.consume("ffmpeg/video", "Got output buffer 1 offset=0 size=1 ts=20000000 flags=0", 21000000);
    assert(trace.overflow == 1 && trace.outputs == 2);
    trace.finished = 21000000;
    trace.consume("ffmpeg/video", "Got output buffer 1 offset=0 size=1 ts=21000000 flags=0", 21000001);
    assert(trace.outputs == 3); // queued log tail may follow RESTART
    trace.consume("ffmpeg/video", "Queued input buffer 1 size=999 ts=1", 21250001);
    assert(trace.inputs == 1);
    const auto json = trace.json();
    assert(json.find("PRIVATE") == std::string::npos && json.find("hevc_mediacodec") == std::string::npos);
    assert(json.find("\"input_first_pts_us\":10000000") != std::string::npos);
    quest::SeekTrace continuity; continuity.started = 1000000; continuity.finished = 2000000; continuity.tail_us = 4000000;
    continuity.consume("ffmpeg/video", "Got output buffer 1 offset=0 size=1 ts=21000000 flags=0", 5000000);
    continuity.consume("ffmpeg/video", "Got output buffer 1 offset=0 size=1 ts=21000000 flags=0", 6000001);
    assert(continuity.outputs == 1 && continuity.overflow == 0);
    std::cout << "Numeric seek trace: passed\n";
}
