# Runtime models

No model weights are stored in this Git repository. Models are selected at build time through a versioned model pack. Public upstream weights and custom/distilled weights use the same task contracts and integrity checks. Model licenses remain in `models/licenses`.

The RVM converter and full AI build default to `upstream`: the public MobileNetV3 weights, adapted to the existing GPU pipeline without student training. `--variant distilled` / `-RvmVariant distilled` explicitly selects the historical pinned student. `models/manifest/runtime-assets.json` remains the historical student's exact catalog; it is not relabeled as the upstream model.

## Model pack and adapter boundaries

`tools/model_assets.py` validates/imports a pack. The installed `ai-models/manifest.json` selects exactly one model per task and records the schema, runtime ABI, ID, version, adapter, dimensions, bytes, SHA256, source and license. The supported runtime ABI is `mnn-3.6.1-vrpp-opencl-v1`.

| Task | Adapter | Runtime asset | Dimensions |
| --- | --- | --- | --- |
| `matting` | `rvm-rgba-recurrent-v1` | `rvm-mnn/rvm.mnn` | Dynamic allowlisted profiles; width/height `0` in the descriptor |
| `video-depth` | `relative-inverse-depth-v1` | `depth-mnn/depth.mnn` | 252×140 |
| `photo-depth` | `relative-inverse-depth-v1` | `depth-mnn/photo_depth.mnn` | 518×518 |

Pack source paths may differ; import normalizes them to these adapter asset names. Models with a different network structure can reuse an adapter only if they honor its tensor semantics. Merely being an ONNX/MNN file is insufficient:

- RVM: `src` RGB/RGBA in the uint8 numeric range; `pha` in 0..1; `pha_u8` for rounded GPU export; four named recurrent inputs/outputs, independently maintained for each eye/scout stream. Channel counts may differ for a student model and are read from the model.
- Depth: `src` RGB float32 CHW in 0..1; ImageNet normalization folded into the graph; single-channel `depth` at the fixed input dimensions, relative inverse depth with larger values nearer. Existing video stabilization and photo normalization remain in the effect pipeline.
- Both adapters require the project's compatible MNN OpenCL runtime and retain GPU placement auditing; there is no automatic CPU fallback.

`ModelRepository` validates the entire metadata contract and lazily verifies a model's actual size/hash before its first use on a preparation worker. `MattingRuntime` separates the video effect queue from the concrete RVM session. Native adapters still check actual tensor shapes. Compiled-program caches include graph bytes and a runtime ABI suffix; photo depth, stereo and portrait caches include model hashes. No frame identity, GPU lease or generation gate is bypassed.

This phase supports build-time selection only. There is no user-facing model selector, runtime download/import or hot switching. Adding another inference engine or incompatible model family requires a new adapter and its own device validation.

## Public upstream configuration

On a host with Python 3.13 and the prepared Android SDK, `python3 tools/prepare_public_ai.py` downloads checksum-pinned public weights and native dependencies, prepares the patched MNN Android library, converts the three task models and installs their selected pack. `--models-only` skips Android runtime compilation. See [portable AI builds](BUILD.md#build-modes-and-compatibility) for packaging with source-frame mpv.

Prepare the AI toolchain described in [BUILD.md](BUILD.md), the pinned depth ONNX listed below and two sample images for its numerical conversion checks. The public path does not read `rvm_student.json` or require a private student checkpoint:

```powershell
./tools/models/Prepare-RvmReference.ps1
./.venv/Scripts/python.exe tools/models/specialize_rvm_ratio_one.py
./.venv/Scripts/python.exe tools/models/prepare_rvm_mnn.py --variant upstream
./.venv/Scripts/python.exe tools/models/prepare_depth_mnn.py --install
./.venv/Scripts/python.exe tools/models/prepare_depth_mnn.py --photo --install
./.venv/Scripts/python.exe tools/model_assets.py --from-directory android/player-plugin/src/main/assets --record-converted upstream
./tools/Build-Player.ps1 -UsePreparedModelAssets -XrVendor Quest
```

`--record-converted` verifies the prepared models against their conversion manifests and the pinned public source hashes, records their actual output hashes under distinct model IDs, and installs support metadata/profile contracts. It does not claim the output matches the historical student. With full reference/oracle dependencies prepared, `Build-Player.ps1 -RvmVariant upstream` also selects this variant through the historical full conversion path. Model conversion and successful packaging do not certify headset throughput or matting quality.

## Custom/private configuration

Supply an explicit pack manifest and the three task model files:

```sh
python3 tools/model_assets.py --from-directory external-model-assets/custom \
  --manifest external-model-assets/custom/model-pack.json
python3 tools/model_assets.py --verify-only \
  --manifest external-model-assets/custom/model-pack.json
```

The manifest root contains `schema_version: 1`, `runtime: "mnn-3.6.1-vrpp-opencl-v1"` and a `models` array with the three tasks above. Each entry provides `id`, `version`, `task`, `adapter`, `path`, `width`, `height`, `bytes`, `sha256`, `license` and `source`. Use your own model ID/version and actual bytes/SHA256; optional `conversion` stores conversion provenance. Hashes are supplied by a trusted build input, not learned from an arbitrary downloaded model during import. A custom pack can reuse public depth models while changing only matting weights. Keep additional applicable model notices with your distribution.

Build the imported selection with `Build-Player.ps1 -UsePreparedModelAssets -ModelManifest external-model-assets/custom/model-pack.json`. The explicit manifest is checked against the installed selection. Direct AI Gradle builds also verify the selected pack before asset staging (`THRU3D_PYTHON` can select the Python 3.11+ interpreter). No-AI builds exclude the model catalog as well as weights and inference libraries.

## Historical pinned student configuration

Normal playback expects:

```text
external-model-assets/
  rvm-mnn/rvm.mnn       modified/distilled RVM, RGBA uint8-range input
  depth-mnn/depth.mnn   Depth Anything V2 Small, 252×140 input
  depth-mnn/photo_depth.mnn   Independent still-photo Depth Anything V2 Small, 518×518 input
```

Import without trusting the supplied files' own metadata:

```powershell
./tools/Import-ModelAssets.ps1 -FromDirectory ./external-model-assets
./tools/Import-ModelAssets.ps1 -VerifyOnly
```

Without an explicit `-Manifest` / `--manifest`, import checks every model against the committed historical catalog before copying, constructs the runtime pack and installs support metadata/license notices. Models land in ignored Android assets. Do not commit them. The prepared-assets build mode supports ordinary Debug/Release builds; full numerical diagnostics require additional reference models and generated oracles.

**There is no hosted download for the project-distilled student in this initial source release.** A matching, independently obtained model directory is required for this historical configuration. The public upstream configuration above does not require it. Do not invent a release URL or substitute an upstream file while retaining the student's checksums. The importer fails explicitly if the files are missing or wrong. Source-only tests do not need these files.

## Source and transformations

| Model | Source | Project transformations |
| --- | --- | --- |
| RVM MobileNetV3 | [RVM v1.0.0](https://github.com/PeterL1n/RobustVideoMatting/releases/tag/v1.0.0); pinned ONNX in `rvm_mobilenetv3.json` | Ratio=1 specialization, unused output pruning, 0..255/RGBA input handling, operator fusion, MNN conversion; optional sliced decoder and recurrent student distillation. |
| Depth Anything V2 Small | [ONNX model](https://huggingface.co/onnx-community/depth-anything-v2-small); source SHA256 in the runtime conversion manifest | Video: 252×140. Photos: independent 518×518 model, aspect-preserving letterbox, content-only normalization. Both fold input normalization, rewrite patch embedding/attention, and use MNN FP16 weights. |

RVM uses four recurrent states independently for each eye. Runtime models are not generic arbitrary ONNX/MNN files; tensor names, dimensions, conventions and the patched MNN kernels are part of the interface contract.

Relevant tools:

- `Prepare-RvmReference.ps1`: retrieve/import the pinned upstream ONNX with hash verification.
- `specialize_rvm_ratio_one.py`, `fuse_rvm_graph.py`, `slim_rvm_decoder.py`: graph modifications.
- `distill_rvm_decoder.py`: train/export a student using explicitly supplied, licensed media. `data --sources` takes a JSON array of `{ "file": "path/to/your-video.mp4", "exclude_seconds": [[0, 5]] }`; no original training filenames are built in.
- `prepare_rvm_mnn.py --variant upstream` (default): convert the public upstream graph using `MNNCONVERT`; `--variant distilled` additionally requires the pinned student. Changing variants invalidates the conversion cache.
- `prepare_depth_mnn.py`: convert/check the video depth source with two user-provided sample images under `build/depth/sample_a.png` and `sample_b.png`. Run again with `--photo --install` to install the separate photo model; it never replaces the video asset.
- `tools/mnn/patch_mnn_vrpp.py`: reproduce the MNN OpenCL HardSwish changes required by the matting graph.

RVM conversion records both FP32 graph error and 8-bit quantization checks. A one-level quantized difference is accepted only at a rounding threshold explained by measured FP32 error; the exported Alpha must independently quantize its own floating Alpha exactly. `tools/models/test_rvm_quantization.py` exercises these boundaries in the AI Python environment. It does not relax the existing graph error limits.

For example, graph preparation begins with:

```powershell
./tools/models/Prepare-RvmReference.ps1
./.venv/Scripts/python.exe tools/models/specialize_rvm_ratio_one.py
$env:MNNCONVERT = (Get-Command mnnconvert).Source
```

Re-training on other media will generally produce different student weights and cannot reproduce the pinned student checksum. A compatible replacement gets its own pack ID/version/hashes, conversion evidence and runtime validation; changing tensor semantics additionally requires a new adapter contract. Do not disable hash checks to imply equivalence.

## Licenses

The upstream RVM code is GPL-3.0; the project records its reused/sliced student weights as GPL-derived. The actual weight grant and appropriate modifiable form must be considered when distributing them. Depth Anything V2 **Small** weights are Apache-2.0; Base/Large/Giant have different terms. Excluding weights from Git does not settle obligations for APKs that embed them. See [licensing scope](LICENSING.md).
