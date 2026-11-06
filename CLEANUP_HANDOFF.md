# Immivio 盤點清理：外部執行任務書

2026-11-06 · 基線 `main` @ `3e878b7`

本輪要清理盤點中確認的死代碼、失效測試、AI 推理殘留和無用依賴。只改工作區，不提交，做完交回 review。本文件本身也不要提交、不要刪除。

## 背景與硬性約束

- **不提交、不推送、不打 tag。** 不執行 `git commit`、`git push`、`git stash`，也不切分支。所有改動留在工作區。
- **FreeCM 配置不得刪除或修改。** `configs/freecm.commands.jsonc`，以及 `.gitignore`、`.prettierignore` 中的 FreeCM 條目全部保留。
- **不改 `.vscode/`。** 這部分由所有者自行處理。
- **遵守 `CONTRIBUTING.md`：**
  - 只格式化你改過的文件，使用倉庫根目錄的配置；
  - 不改 vendored 代碼（`native/mpv/include/mpv/`），lockfile 以外的生成資產和簽名材料也不要動；
  - 生成的輸出放到 `artifacts/` 或 `build/` 下對應的目錄。
- **不新增功能，不順手重構。** 每個任務只動任務裡列出的範圍。遇到範圍外的問題，寫進回報，不要修。
- **如實回報。**
  - 沒跑的檢查寫「未執行」並說明原因；
  - 需要頭顯才能驗證的寫「待設備驗收」，不能用主機測試代替。
- **拿不準就停。** 如果某項刪除的依據和本文不符（例如發現了生產代碼的引用），就跳過這一項，並在回報裡寫明證據。

## A 組：低風險清理

這四項不改變播放行為，先做。每項的驗收都包括「改動後主機測試通過」，具體命令見最後一節。

### A1：修正「關於」頁的授權致謝

- **問題：** `app/godot/scripts/library_menu.gd:1149-1152` 仍列出 RVM MobileNetV3、MNN、ncnn、Depth Anything V2 Small。這些組件已經不在產品裡，這屬於錯誤的授權聲明。
- **做法：**
  - 刪掉這四行，其他致謝保持不變。
  - 在 `app/godot/i18n/translations.json` 刪除已無引用的條目：這四個組件名（如果有），以及三個語言下的 `"RVM smooth"` 和 `"RVM quality"`。刪除前用 `git grep` 確認沒有任何腳本引用它們。
  - 對照 `third_party/player-licenses/` 和 `LicenseCatalog.kt`，確認關於頁剩下的每一項都有對應的授權文件。不一致的地方只回報，不要自行補授權文本。
- **驗收：**
  - `git grep -nE "RVM|MNN|ncnn|Depth Anything" -- app/godot` 沒有命中；
  - 如果有測試斷言了關於頁的行數，同步更新。

### A2：移除已廢棄的 `recent_menu.gd`

- **問題：** `main.gd:288` 的 `recent_menu` 現在是 `LibraryMenu.new()`。`scripts/recent_menu.gd`（113 行）在生產代碼中已經沒有引用，只剩下測試還在 preload 它。
- **受影響的測試（路徑相對 `app/godot/`）：**

| 文件 | 行數 | 處理方式 |
| --- | --- | --- |
| `tests/test_recent_files.gd` | 418 | 逐個判斷斷言：涉及最近文件存儲、去重、持久化的，改成針對生產路徑（`LibraryMenu` 或對應的狀態類）斷言；只測舊菜單佈局的，刪除 |
| `tests/test_recent_pointer.gd` | 263 | 同上。如果 `LibraryMenu` 已有對應的射線/扳機選擇測試，整個文件刪除 |
| `tests/test_player_menu.gd` | 第 4、316、336 行 | 把 `Recent` 實例改成生產中實際使用的菜單對象，保留「點擊後播放器菜單可見、最近菜單隱藏」這條斷言 |
| `tests/render_recent_menu.gd` | 131 | 刪除 |

- **做法：**
  - 刪除 `scripts/recent_menu.gd` 及其 `.uid`，以及被刪測試對應的 `.uid`。
  - 每刪掉一條斷言，都要在回報裡說明理由：要麼已被其他測試覆蓋（寫出測試名），要麼只測舊實現。
- **驗收：**
  - `git grep -n "recent_menu.gd"` 沒有結果；
  - Godot import 步驟沒有 `SCRIPT ERROR`。

### A3：刪除失效的 `benchmarks/mpv_shared_probe.py`

- **問題：** 該腳本第 195–297 行檢查 `model_code_rgb`、`alpha_pixels_checked`、`profile_key == "384x216"`、`model_generation` 等推理字段。這些字段在 `PlaybackFrameContract.kt:10-23` 中已經退休，生產代碼不再輸出，所以這個腳本不可能通過。
- **做法：** 刪除該文件，並清理所有引用它的地方。目前 `git grep mpv_shared_probe` 沒有其他命中；如果你那邊查到了，寫進回報。
- **另外檢查其他 13 個 benchmark（只報告，不修改）：**
  - 它們最後一次修改都在 2026-10-14，早於 R2–R5 重構。
  - 對每個腳本，對照它讀取的 JSON 字段和廣播 action，確認在 `android/` 或 `app/godot/scripts/` 中仍有對應的生產者。例如 `mpv_seek_hold_device.py:68-129` 用到的 `alpha_enabled`。
  - 結果整理成表格：腳本 · 失效字段或 action · 證據（文件:行號）。

### A4：移除無用的 Python 依賴

- **問題：** `requirements-media-tools.txt` 中的 `onnxruntime`、`flatbuffers`、`protobuf` 沒有任何代碼 import，是推理時代的殘留（後兩個是 onnxruntime 的依賴）。
- **做法：**
  - 刪除這三行。
  - `packaging` 也沒有被直接 import。先查它是不是 `opencv-python-headless`、`pillow` 或 `numpy` 的必需依賴：是就保留，不是就一併刪除。
  - 其餘依賴的版本號不要改。
- **驗收：**
  - 在 `build/` 下建一個臨時 venv，`pip install -r requirements-media-tools.txt` 成功；
  - 用 `python -c` 逐一 import `cv2`、`numpy`、`PIL`，都不報錯；
  - 沒有網絡就寫「未執行」。

## B 組：依賴升級

一次只升一個依賴，每升一個就跑一次對應的驗證。失敗就還原這一項，記下錯誤，然後繼續下一個。下表的目標版本是 2026-11-06 從 Maven Central、Google Maven 和 Gradle 官網查到的最新穩定版。

通用要求：

- 版本號在 `android/gradle/libs.versions.toml` 中修改。
- 同步更新以下文件（見 `docs/BUILD.md` 的「Dependency ownership」）：
  - `android/gradle.lockfile`
  - `android/settings-gradle.lockfile`
  - `android/export-locks/`
  - `android/gradle/verification-metadata.xml`
- 不要手改 checksum，一律用 Gradle 的 `--write-locks` 和 `--write-verification-metadata sha256` 生成。
- 這一步需要聯網下載依賴。無法聯網就停止整個 B 組，並回報原因。
- 改完後檢查 `git diff`：verification-metadata 只應新增預期的構件，不應混入意外的傳遞依賴。如果有新增的傳遞依賴，在回報中列出。

| # | 依賴 | 當前 → 目標 | 額外要求 | 需設備驗收 |
| --- | --- | --- | --- | --- |
| B1 | Kotlin | 2.3.21 → 2.4.21 | 遇到新的編譯警告，只記錄，不要順手重寫代碼 | 否 |
| B2 | AGP | 9.2.0 → 9.5.1 | `aapt2` 必須同步改為配套版本；確認 AGP 9.5 要求的最低 Gradle 和 build-tools 版本，以及與 `configs/ci_toolchain.json` 是否相容 | 是（打包產物會變） |
| B3 | Gradle | 9.8.1 → 9.8.2 | 更新 `configs/ci_toolchain.json` 中的 URL、fileName 和 sha256；sha256 必須取自官方的 `.sha256` 文件 | 否 |
| B4 | Media3 ExoPlayer | 1.10.1 → 1.11.1 | 閱讀 1.11 的 release notes，列出與本專案所用 API 相關的行為變化 | 是 |
| B5 | OpenXR loader | 1.1.54 → 1.1.65 | 先確認 Godot OpenXR Vendors 5.1.0 自帶或要求的 loader 版本。如果兩者需要對齊，就不升，只回報 | 是 |
| B6 | ICU4J（字幕編碼偵測） | 78.1 → 79.1 | 同步更新 `third_party/icu-charset/distribution.json` 的 `upstream_jar_sha256`（`build.gradle` 會校驗它），並檢查 `LICENSE.txt` 是否需要更新 | 否（但 JVM 字幕編碼測試必須通過） |
| B7 | org.json（僅測試用） | 20240303 → 20260814 | 無 | 否 |

**以下不要升級：**

- **slf4j-api 1.7.36 和 bcprov-jdk18on 1.85：** `build.gradle` 刻意與 jcifs 3.0.4 的 pom 對齊（已核實 pom 中正是這兩個版本）。bcprov 1.86 是否值得脫離對齊，由所有者決定。
- **androidx.fragment 1.8.6：** 與 Godot 導出模板對齊。
- **Godot 4.7.2、OpenXR Vendors 5.1.0、mpv-android 2026-09-17、jcifs 3.0.4：** 已經是最新版。
- **Pillow 12.3 → 13.0：** 大版本升級，本輪不動。
- **GitHub Actions：** 升級後要推送才能驗證，而本輪不提交，留到以後。

## C 組：推理殘留

C1 可以直接改。C2 只調查、不改代碼，因為 alpha 封裝魚眼（`_alpha` 文件名）可能仍是現行功能。

### C1：移除沒有作用的推理配置

| 位置 | 內容 | 處理 |
| --- | --- | --- |
| `android/player-plugin/build.gradle:6-8` | 傳入 `enableAi=true` 就報錯 | 刪除 |
| `android/player-plugin/src/main/AndroidManifest.xml:34-36` | 為 MNN 聲明的 `libOpenCL.so` | 刪除前先驗證：對打好的 Quest Debug APK 中每個 `lib/arm64-v8a/*.so` 執行 `strings`，確認沒有任何一個引用 `libOpenCL`。如果有引用，就保留聲明，只把註釋改成真實的使用者 |
| `build.gradle:14,26,47-51`、`configs/player_build.py:625`、`tools/Analyze-ApkSize.py:39`，以及 `.gitignore` 中的 rvm/mnn 條目 | 排除、校驗舊的推理資產 | **保留不動。** 這些是防止舊構建目錄把已移除的庫帶進 APK 的保護，成本很低 |

### C2：調查 `alpha_requested` 是否仍在使用（只報告）

矛盾點：`PlaybackFrameContract.kt:19` 把 `alpha_requested` 列為退休字段，但 `MpvVideoBridge.kt:818` 仍在寫入它。Godot 側也還在使用：

- `mpv_video_display.gd:42,580-617,718,775,781`
- `file_mode_memory.gd:53`
- `main.gd:1153`（診斷狀態文字 "Preparing Alpha"）
- `media_naming.gd:41`（註釋寫著「其他 alpha 名稱要求 live matting」）

請回答以下問題，並附上證據（文件:行號）：

1. `MpvVideoBridge.kt:818` 寫入的是哪個消息？這個消息是否經過 `PlaybackFrameContract` 的退休字段過濾？
2. 對一個非封裝的 `_alpha` 文件，當 `alpha_requested` 為 true 時，現在實際會發生什麼？會不會卡在 "Preparing Alpha"？
3. 哪些代碼路徑屬於封裝 alpha（應保留），哪些屬於 live matting（可以移除）？
4. 建議的移除範圍是什麼？受影響的持久化設定（`file_mode_memory`）是否需要遷移？

## 不在本輪範圍

以下問題已經確認存在，但本輪不處理，請勿動手：

- **FreeCM 配置和 `.vscode/`：** 保留，由所有者決定。
- **coordinator 對 `main.gd` 私有狀態的耦合：** 共有 589 處 `host._xxx`，其中 `input_coordinator.gd` 佔 228 處，需要單獨設計。
- **Godot 測試對私有成員的依賴：** 95 個測試中有 79 個，共 1668 處，要和上一項一起逐步處理。
- **在 CI 中加入 `render_*.gd` 和 benchmarks 的加載檢查：** 需要推送才能驗證。
- **文檔中的歷史記錄：** `ACCEPTANCE.md` 中的「Go `cloudcore` 測試通過」和 `REFACTOR_PLAN.md` 中的行數，都是當時（基線 `41f48d5`）的真實記錄，不要改。

## 驗證命令與交付回報

### 每組做完後執行

以下命令都在倉庫根目錄執行：

```sh
python3 -m unittest discover -s tests/workflow -v
python3 -m unittest discover -s tests/website -v
python3 tools/test_prepare_android_release.py
python3 tools/Check-PublicSource.py
git diff --check
```

涉及 Godot、Android 或依賴改動的（A1、A2、B、C1），還要執行：

```sh
python3 configs/android_workflow.py test --vendor Quest --build-type Debug --level all
python3 configs/android_workflow.py build --vendor Quest --build-type Debug
python3 configs/android_workflow.py package --vendor Quest --build-type Debug
```

如果本機沒有 Godot，或環境沒有按 `docs/BUILD.md` 準備好，就在回報中寫明哪一個 level 沒有跑。測試日誌留在 `artifacts/tests/` 下。

### 回報格式

完成後在你的最終回覆中提供以下內容（不要寫進倉庫）：

1. **任務狀態表**：任務 · 狀態（完成／部分／跳過／未執行）· 改動的文件 · 執行過的驗證命令及結果（通過數／失敗數）· 備註。
2. **A2 被刪斷言清單**：斷言 · 刪除理由 · 覆蓋它的測試名（如果有）。
3. **A3 benchmark 失效表**，以及 **C2 的四個問題的回答**。
4. **B 組**：新增的傳遞依賴；失敗後被還原的升級項及錯誤摘要。
5. **待設備驗收的項目清單**。
6. **範圍外發現**：只列出，沒有修改。
7. 最後附上 `git status --short` 和 `git diff --stat` 的完整輸出。
