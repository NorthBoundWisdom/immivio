#pragma once
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

namespace quest {
// Debug-only numeric reduction of MPV/FFmpeg messages. Never retain log text,
// filenames, titles, subtitle text or packet contents. Times are event-receipt
// times on the client thread, not timestamps inside the decoder.
struct SeekTrace {
    struct Bin { uint64_t inputs = 0, outputs = 0, input_bytes = 0, demux_packets = 0; };
    std::array<Bin, 128> bins{}; // bounded 100 ms buckets
    int64_t started = -1, finished = -1, demux_start = -1, demux_done = -1;
    int64_t first_input = -1, last_input = -1, first_output = -1, last_output = -1;
    int64_t input_first_pts = -1, input_last_pts = -1, output_first_pts = -1, output_last_pts = -1;
    uint64_t messages = 0, inputs = 0, outputs = 0, input_bytes = 0;
    uint64_t no_input = 0, no_output = 0, demux_packets = 0, overflow = 0, queue_overflows = 0;
    bool timed_out = false;

    void consume(const char* prefix, const char* text, int64_t now) {
        // MPV's event and log queues are separate: RESTART can be delivered
        // before the final decoder messages. Reduce their numeric tail before
        // changing the subscription level, which destroys MPV's pending buffer.
        if (started < 0 || (finished >= 0 && now > finished + 250000)) return;
        ++messages;
        if (std::strstr(text, "log message buffer overflow")) ++queue_overflows;
        const auto index = static_cast<uint64_t>(now >= started ? now - started : 0) / 100000;
        Bin* bin = index < bins.size() ? &bins[index] : nullptr;
        if (!bin) ++overflow;
        if (std::strncmp(prefix, "demux", 5) == 0 || std::strcmp(prefix, "lavf") == 0) {
            if (std::strncmp(text, "execute seek (", 14) == 0 && demux_start < 0) demux_start = now;
            if (std::strncmp(text, "seek done", 9) == 0 && demux_done < 0) demux_done = now;
            if (std::strncmp(text, "append packet to video:", 23) == 0) {
                ++demux_packets; if (bin) ++bin->demux_packets;
            }
        }
        if (std::strncmp(prefix, "ffmpeg/video", 12) != 0) return;
        const char* input = std::strstr(text, "Queued input buffer ");
        const char* output = std::strstr(text, "Got output buffer ");
        long long id = 0, size = 0, pts = 0, offset = 0; unsigned flags = 0;
        if (input && std::sscanf(input, "Queued input buffer %lld size=%lld ts=%lld", &id, &size, &pts) == 3 && size >= 0) {
            if (first_input < 0) { first_input = now; input_first_pts = pts; }
            last_input = now; input_last_pts = pts; ++inputs; input_bytes += size;
            if (bin) { ++bin->inputs; bin->input_bytes += size; }
        } else if (output && std::sscanf(output, "Got output buffer %lld offset=%lld size=%lld ts=%lld flags=%u", &id, &offset, &size, &pts, &flags) == 5 && size > 0) {
            if (first_output < 0) { first_output = now; output_first_pts = pts; }
            last_output = now; output_last_pts = pts; ++outputs;
            if (bin) ++bin->outputs;
        } else if (std::strstr(text, "No input buffer available, try again later")) ++no_input;
        else if (std::strstr(text, "No output buffer available, try again later")) ++no_output;
    }
    std::string json() const {
        std::string result = "{\"scope\":\"client_log_receipt_times_not_decoder_timestamps\"";
        const auto field = [&](const char* name, auto value) { result += std::string(",\"") + name + "\":" + std::to_string(value); };
        field("started_us", started); field("finished_us", finished);
        field("drain_until_us", finished < 0 ? -1 : finished + 250000);
        field("demux_start_us", demux_start); field("demux_done_us", demux_done);
        field("first_input_us", first_input); field("last_input_us", last_input);
        field("first_output_us", first_output); field("last_output_us", last_output);
        field("input_first_pts_us", input_first_pts); field("input_last_pts_us", input_last_pts);
        field("output_first_pts_us", output_first_pts); field("output_last_pts_us", output_last_pts);
        field("messages", messages); field("inputs", inputs); field("outputs", outputs); field("input_bytes", input_bytes);
        field("no_input", no_input); field("no_output", no_output); field("demux_packets", demux_packets); field("overflow", overflow);
        field("queue_overflows", queue_overflows); field("timed_out", timed_out ? 1 : 0);
        result += ",\"bins\":[";
        bool comma = false;
        for (size_t i = 0; i < bins.size(); ++i) {
            const auto& bin = bins[i];
            if (!bin.inputs && !bin.outputs && !bin.demux_packets) continue;
            if (comma) result += ',';
            comma = true;
            result += "{\"offset_ms\":" + std::to_string(i * 100) + ",\"inputs\":" + std::to_string(bin.inputs) +
                ",\"outputs\":" + std::to_string(bin.outputs) + ",\"input_bytes\":" + std::to_string(bin.input_bytes) +
                ",\"demux_packets\":" + std::to_string(bin.demux_packets) + "}";
        }
        return result + "]}";
    }
};
}
