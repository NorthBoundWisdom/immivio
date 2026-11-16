#pragma once
#include <stdint.h>
// Shared with the rebased libmpv AAudio patch; all positions are hardware frames.
static inline int64_t immivio_aaudio_played(int64_t *last_presented, int64_t *read_gap,
    int valid, int64_t presented, int64_t timestamp_ns, int64_t now_ns,
    int64_t started_ns, int64_t read, int64_t written, int64_t discarded, int rate) {
    if (!valid) {
        int64_t consumed = read - discarded - *read_gap;
        presented = consumed > *last_presented ? consumed : *last_presented;
        timestamp_ns = now_ns;
    }
    *last_presented = presented;
    int64_t age = now_ns - timestamp_ns;
    if (timestamp_ns < started_ns || age < -200000000LL || age > 200000000LL) age = 0;
    int64_t played = presented + age * rate / 1000000000LL;
    int64_t available = written > discarded ? written - discarded : 0;
    if (played > available) played = available;
    if (played < 0) played = 0;
    if (valid) {
        int64_t gap = read - (played + discarded);
        *read_gap = gap < 0 ? 0 : (gap > rate ? rate : gap);
    }
    return played;
}
