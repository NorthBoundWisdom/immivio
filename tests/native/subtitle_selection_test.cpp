#include <immivio/mpv/subtitle_selection.h>
#include <cassert>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

struct Slots {
  int primary = 2, secondary = 8;
  bool imported = false, reject_clear = false;
  std::vector<std::string> calls;
  void apply(bool secondary_dirty, int secondary_id, bool primary_dirty, int primary_id) {
    quest::apply_subtitle_selection(
        secondary_dirty, secondary_id, primary_dirty, primary_id,
        [&] { return secondary ? std::to_string(secondary) : "no"; },
        [&](int id) {
          calls.push_back("secondary=" + std::to_string(id));
          if (reject_clear && id == 0)
            throw std::runtime_error("clear failed");
          // Model mpv's selected-track guard, including success without a change.
          if (id == 0 || id != primary)
            secondary = id;
        },
        [&] { imported = true; },
        [&](int id) {
          assert(imported);
          calls.push_back("primary=" + std::to_string(id));
          if (id <= 0 || id != secondary)
            primary = id;
        });
  }
};

int main() {
  Slots same_drain;
  same_drain.apply(true, 0, true, 8);
  assert((same_drain.calls == std::vector<std::string>{"secondary=0", "primary=8"}));
  assert(same_drain.primary == 8 && same_drain.secondary == 0);

  Slots later_drain;
  later_drain.apply(false, 0, true, 8);
  assert((later_drain.calls == std::vector<std::string>{"secondary=0", "primary=8"}));
  assert(later_drain.primary == 8 && later_drain.secondary == 0);

  Slots changed_slot;
  changed_slot.apply(true, 9, true, 8);
  assert((changed_slot.calls == std::vector<std::string>{"secondary=9", "primary=8"}));
  assert(changed_slot.primary == 8 && changed_slot.secondary == 9);

  Slots conflicting_requests;
  conflicting_requests.secondary = 0;
  conflicting_requests.apply(true, 8, true, 8);
  assert((conflicting_requests.calls ==
          std::vector<std::string>{"secondary=8", "secondary=0", "primary=8"}));
  assert(conflicting_requests.primary == 8 && conflicting_requests.secondary == 0);

  for (const int id : {0, -1}) {
    Slots disabled_or_auto;
    disabled_or_auto.apply(false, 0, true, id);
    assert((disabled_or_auto.calls == std::vector<std::string>{"primary=" + std::to_string(id)}));
    assert(disabled_or_auto.secondary == 8);
  }

  Slots secondary_only;
  secondary_only.apply(true, 9, false, 8);
  assert((secondary_only.calls == std::vector<std::string>{"secondary=9"}));
  assert(secondary_only.primary == 2);

  Slots rejected;
  rejected.reject_clear = true;
  try {
    rejected.apply(true, 0, true, 8);
    assert(false);
  } catch (const std::runtime_error &) {
    assert((rejected.calls == std::vector<std::string>{"secondary=0"}));
    assert(!rejected.imported && rejected.primary == 2 && rejected.secondary == 8);
  }
  std::cout << "Subtitle selection: same-drain/cross-drain order, live-slot guard, off/auto and "
               "failure checks passed\n";
}
