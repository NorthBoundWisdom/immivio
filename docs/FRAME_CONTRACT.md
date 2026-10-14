# Playback frame contract

The Kotlin producer and Godot consumer use **contract version 2**. A playback frame contains source color plus a numeric R8 mask; its texture names are borrowed until display detach and native retirement complete. A frozen transition owns independent copies and is released separately.

| Group | Fields and rules |
| --- | --- |
| Version | `contract_version = 2`; other versions are rejected |
| Ownership | Positive `session_id`, `logical_session_id`, `generation`, `source_epoch`, `slot_token` |
| Source identity | Nonnegative integral `frame_id`, `pts_us`; an explicitly identified libmpv playback-clock estimate |
| Presentation | Positive `format_revision`, `presentation_revision`; revisions cannot relabel a source frame |
| Color | Positive `color_texture_id`, width/height within supported native limits, `color_target = texture` |
| Mask | Positive distinct `alpha_texture_id`, even `alpha_width`, positive `alpha_height`, `alpha_texture_format = GL_R8_numeric`; `mask_kind` is `opaque` or `numeric` |
| Pair identity | `alpha_slot_token`, `alpha_frame_id`, `alpha_pts_us` equal the color identity |
| Completion | Explicit boolean `immutable_color_frame`, `pair_identity_verified`, `consumer_copy_fence_ready`, `alpha_fence_ready`, `alpha_gpu_uploaded` |
| Layout | Boolean `stereo_sbs` and `top_bottom`, legal rotation, even dimensions along the packed stereo axis |
| Mask coordinates | Finite four-element `mask_content_rect`, a nonempty in-bounds rectangle containing a mask texel |

Godot accepts only exact integral JSON numbers within ±(2^53−1) for identity/timestamp fields. EGL/decoder pointers are not transmitted by this playback contract. Diagnostic clocks that are not identities may use separate representations. Native source status and subtitle messages retain their own formats.

The removed version-1 model fields (`model_generation`, `effect_revision`, input/profile/layout fields, inference/depth flags and warp texture IDs) are rejected. The producer removes them before publishing. No implicit adapter translates an old frame into a current one. Kotlin/Godot must be rebuilt together; existing persisted audio, subtitle, queue and mode preferences are independent of this transport version.

`PlaybackFrameContract.kt` owns publication and Kotlin identity decoding. `playback_frame_contract.gd` owns consumer validation and stable rejection codes (`FRAME_CONTRACT_VERSION`, `FRAME_RETIRED_FIELD`, `FRAME_INTEGER_ID`, `FRAME_TIMESTAMP`, `FRAME_FENCE`, `FRAME_MASK_IDENTITY`, and layout/format/coordinate errors). `pair_texture_binding.gd` only creates/frees Godot wrappers and sets material parameters; it never releases the producer lease.

The native bridge creates opaque masks on the GPU during the same capture transaction. It no longer uploads inference planes or creates decoder AHardwareBuffer imports. Cached borrowed color/mask handoff avoids extra GL work; copy capture still has a completion fence. The seven-slot capacity and producer retirement acknowledgement remain unchanged pending device measurements.
