#pragma once
#include <string>

namespace quest {
// The read must happen after the pending secondary/import work, on the control
// thread: queued requests can arrive in different drains while the live slot
// still owns the primary target. mpv can silently reject that collision.
template <class ReadSecondary, class ApplySecondary, class ImportSubtitle, class ApplyPrimary>
void apply_subtitle_selection(bool secondary_dirty, int secondary_id, bool primary_dirty,
                              int primary_id, ReadSecondary read_secondary,
                              ApplySecondary apply_secondary, ImportSubtitle import_subtitle,
                              ApplyPrimary apply_primary) {
  if (secondary_dirty)
    apply_secondary(secondary_id);
  import_subtitle();
  if (primary_dirty) {
    if (primary_id > 0 && read_secondary() == std::to_string(primary_id))
      apply_secondary(0);
    apply_primary(primary_id);
  }
}
} // namespace quest
