#include <mpv/client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void checked(int code, const char *action) {
    if (code < 0) { fprintf(stderr, "%s: %s\n", action, mpv_error_string(code)); exit(1); }
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    mpv_handle *core = mpv_create();
    if (!core) return 3;
    const char *options[][2] = {
        {"config", "no"}, {"terminal", "no"}, {"vo", "null"}, {"hwdec", "no"},
        {"ao", "aaudio"}, {"aaudio-performance-mode", "low-latency"},
        {"mute", "yes"}, {"pause", "yes"}, {"idle", "yes"}, {"keep-open", "yes"},
        {"gpu-dumb-mode", "yes"}, {"tls-verify", "yes"}, {"sub-visibility", "no"},
        {"secondary-sub-visibility", "no"}, {"secondary-sid", "no"},
        {"sub", "no"}, {"sub-auto", "no"}, {"audio-pitch-correction", "yes"},
        {"demuxer-max-bytes", "256MiB"}, {"demuxer-readahead-secs", "20"},
        {"network-timeout", "30"}, {"interpolation", "no"}, {"dither", "no"},
        {"scale", "bilinear"}, {"cscale", "bilinear"}, {"dscale", "bilinear"},
    };
    for (unsigned i = 0; i < sizeof(options) / sizeof(options[0]); ++i)
        checked(mpv_set_option_string(core, options[i][0], options[i][1]), options[i][0]);
    checked(mpv_initialize(core), "initialize");
    const char *load[] = {"loadfile", argv[1], NULL};
    checked(mpv_command(core, load), "loadfile");
    int loaded = 0;
    for (int i = 0; i < 100 && !loaded; ++i) {
        mpv_event *event = mpv_wait_event(core, 0.1);
        if (event->event_id == MPV_EVENT_FILE_LOADED) loaded = 1;
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *end = event->data;
            if (end->error < 0) checked(end->error, "open input");
        }
    }
    if (!loaded) return 4;
    char *version = mpv_get_property_string(core, "mpv-version");
    printf("runtime=%s\n", version ? version : "unknown");
    mpv_free(version);
    checked(mpv_set_property_string(core, "tone-mapping", "mobius"), "HDR curve");
    checked(mpv_set_property_string(core, "tone-mapping-param", "0.6"), "HDR parameter");
    checked(mpv_set_property_string(core, "gpu-dumb-mode", "no"), "HDR enable");
    checked(mpv_set_property_string(core, "gpu-dumb-mode", "yes"), "HDR disable");
    for (int i = 0; i < 8; ++i) {
        checked(mpv_set_property_string(core, "pause", "no"), "resume");
        struct timespec interval = {0, 100000000};
        nanosleep(&interval, NULL);
        const char *seek[] = {"seek", i % 2 ? "0.1" : "0.3", "absolute+exact", NULL};
        checked(mpv_command(core, seek), "seek");
        checked(mpv_set_property_string(core, "speed", i % 2 ? "1.5" : "1.0"), "speed");
        checked(mpv_set_property_string(core, "pause", "yes"), "pause");
    }
    checked(mpv_set_property_string(core, "pause", "no"), "final resume");
    struct timespec settle = {0, 200000000};
    nanosleep(&settle, NULL);
    char *output = mpv_get_property_string(core, "current-ao");
    printf("audio_output=%s\n", output ? output : "unavailable");
    int ok = output && strcmp(output, "aaudio") == 0;
    mpv_free(output);
    mpv_terminate_destroy(core);
    puts("Android runtime seek/pause/HDR option checks completed");
    return ok ? 0 : 5;
}
