---
name: immivio-device-install
description: "將 Immivio 目前工作目錄編譯、打包並安裝到已連線的 PICO、Meta Quest 或 Android OpenXR 真機，確認版本與啟動狀態。用於要求真機安裝、更新或部署最新版；不包含商店提交、GitHub 發布或單純模擬器截圖。"
---

# Immivio 真機安裝

使用倉庫既有的 `configs/android_workflow.py`，把使用者指定的版本安裝到指定真機。「最新版」預設指目前工作目錄，包含尚未提交的修改及新增素材；不自行切換分支、拉取遠端、修改版本號或提交程式碼。

以下命令在倉庫根目錄執行。先閱讀 [建置說明](../../../docs/BUILD.md)；來源、簽章與輸出目錄規則以該文件和目前腳本為準。這份 skill 記錄操作流程，不取代既有建置工具。

## 1. 確認來源與裝置

```sh
git status --short
git log -1 --format='%h %s'
rg -n 'config/version' app/godot/project.godot
adb devices -l
```

- 記下這次修改與新增素材。版本號相同不代表已安裝內容相同；不要拿上一次的 APK 當成本次最新版本。
- 從本次 `adb devices -l` 選出實際目標，把序號存入 `DEVICE_SERIAL`，並 `export ANDROID_SERIAL="$DEVICE_SERIAL"`。後續直接操作 adb 時一律使用 `-s "$DEVICE_SERIAL"`，不沿用歷史序號。
- 只有一台已授權真機且符合使用者要求時直接使用；多台裝置而目標不明時再請使用者選擇。`unauthorized`、`offline` 或無裝置時，說明需要在頭顯允許 USB 偵錯或重新連線，等待恢復後繼續。
- 依裝置設定 `DEVICE_VENDOR` 為 `Pico`、`Quest` 或 `OpenXR`。不明時以 `adb -s "$DEVICE_SERIAL" shell getprop ro.product.manufacturer` 等裝置資訊確認，避免把 Quest 預設建置裝到 PICO。
- 一般本機驗證設定 `BUILD_TYPE=Debug`、`DIST_CHANNEL=appstore`；依使用者指定保留 Release、web 或既有開發包選擇。每個階段使用相同參數。`appstore` 是發行通道，不代表本次要上架；Debug 包不是商店提交包。
- 一般應用 ID 為 `com.northboundwisdom.immivio`，將它存入 `APP_ID`。若使用者指定獨立開發包，所有階段都設定 `IMMIVIO_DEVELOPMENT_PACKAGE=1`、使用 Debug，並改用 `com.northboundwisdom.immivio.dev`（顯示名稱為 Immivio Dev）。

## 2. 使用已準備好的環境與快取

沿用使用者的環境變數。這台 macOS 開發機曾驗證以下快取可用；只有目錄存在且未指定其他位置時才採用，不把它們視為其他機器的必備路徑：

```sh
if [ -z "${IMMIVIO_MPV_LIB_DIR:-}" ] && [ -d "$HOME/.cache/immivio/android-mpv" ]; then
  export IMMIVIO_MPV_LIB_DIR="$HOME/.cache/immivio/android-mpv"
fi
if [ -z "${GRADLE_USER_HOME:-}" ] && [ -d "$PWD/.cache/gradle/caches" ]; then
  export GRADLE_USER_HOME="$PWD/.cache/gradle"
fi
python3 configs/check_environment.py
```

- `IMMIVIO_MPV_LIB_DIR` 必須指向準備好的 Android ARM64 媒體函式庫，不能用 Homebrew 的桌面 mpv 代替；既有腳本會驗證 checksum。
- 本機的 `.cache/gradle` 與 `~/.gradle` 是不同快取。若離線編譯報找不到 AGP、Kotlin 或其他套件，先確認選到已準備好的快取，不要直接降版、改 lockfile 或略過依賴驗證。
- Configure、Build、Package 都是離線流程。只有確實缺少快取時，才依 `docs/BUILD.md` 使用 `prepare_assets.py --download` 或同一組參數的 `prepare-packages`。缺少主機工具時明確指出項目，不在編譯階段暗中安裝整套工具。
- 使用 Immivio 現有持久簽章，通常位於 `~/.config/immivio/signing/`；不輸出密碼、不複製其他專案的金鑰，也不藉由重建金鑰修復簽章不一致。

## 3. 編譯與打包當前內容

依序執行；任何階段失敗都先處理該階段，不繼續安裝之前留下的 APK：

```sh
python3 configs/android_workflow.py configure --vendor "$DEVICE_VENDOR" --build-type "$BUILD_TYPE" --channel "$DIST_CHANNEL"
python3 configs/android_workflow.py build --vendor "$DEVICE_VENDOR" --build-type "$BUILD_TYPE" --channel "$DIST_CHANNEL"
python3 configs/android_workflow.py package --vendor "$DEVICE_VENDOR" --build-type "$BUILD_TYPE" --channel "$DIST_CHANNEL"
```

Configure 的來源簽章包含 GDScript；只改腳本也可能需要重新 Configure。Package 負責驗證實際 APK 的簽章、ARM64、native 依賴、對齊、應用身分與通道。不要以「Gradle 成功」代替整個 Package 成功。

建置日誌在 `artifacts/logs/build/<平台>/<通道>/<類型>/`；APK 與 `.build.json` 在 `artifacts/packages/<平台>/<通道>/<類型>/`。用 workflow 查找實際輸出，不手寫版本、日期或猜測 APK 名稱：

```sh
python3 configs/android_workflow.py locate --vendor "$DEVICE_VENDOR" --build-type "$BUILD_TYPE" --channel "$DIST_CHANNEL"
```

只有 `locate` 成功後，才將其輸出存入 `APK`；它會比對 APK 與 receipt 的 SHA-256。確認 receipt 的應用 ID、平台與通道符合本次選擇。本次新增背景等素材時，可用 Python `zipfile` 檢查實際 APK 內包含對應資源。

若建置期間另有工作持續修改來源，安裝前比對建置前後的內容；必要時對本次修改檔與新增資源記錄並重查 SHA-256。JSON、圖片等資源不一定都在 workflow 的來源簽章中，不能只靠版本號或 receipt 的 commit 判斷。來源已變時重新建置。

### 專案鎖被占用時

`Workspace is busy` 表示另一個程序持有 `.immivio.workspace.lock`。在 macOS 可用 `lsof .immivio.workspace.lock` 與 `ps` 查看持有者和進度。不要刪掉鎖檔、略過鎖或終止其他工作。

先等待短時間並觀察日誌；若需繼續且原目錄仍被占用，可在 `build/intermediates/` 建立隔離的 Git worktree。帶入當前所有修改和必要的 untracked 素材，不只複製已追蹤的差異。重用已驗證的依賴快取，讓隔離目錄自己產生設定與建置結果。安裝前比對隔離來源與原工作目錄，並把成功產物連同 receipt 保存在倉庫規定的輸出目錄；遇到不同內容的既有產物時先保留到 `artifacts/archive/`，不要悄悄覆寫。

## 4. 安裝並啟動

預設保留應用資料更新：

```sh
adb -s "$DEVICE_SERIAL" install -r "$APK"
```

安裝回報 `Success` 後，重新啟動應用，避免驗證到舊程序：

```sh
adb -s "$DEVICE_SERIAL" shell am force-stop "$APP_ID"
adb -s "$DEVICE_SERIAL" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1
```

`android_workflow.py run` 也能安裝與啟動；它使用 adb 的預設目標，所以使用前必須設定本次的 `ANDROID_SERIAL`，而且不應把仍在執行的舊程序當作新版本啟動證據。

### 簽章不一致

`INSTALL_FAILED_UPDATE_INCOMPATIBLE` 通常代表已安裝包與新包簽章不同。先確認應用 ID 與現有專案金鑰，必要時用 `apksigner verify --print-certs` 比對公開憑證。不要自動改用其他金鑰。

- 使用者本次或既有對話已明確授權卸載舊版時，完成並驗證新 APK 後再卸載，然後立即安裝新包；告知舊版應用資料會清除，不重複索取同一授權。
- 尚未授權清除資料時，說明實際簽章衝突與卸載的資料影響，確認後再卸載。使用者若選擇保留舊版並存驗證，再以 `IMMIVIO_DEVELOPMENT_PACKAGE=1` 重新 Configure、Build、Package，安裝 Immivio Dev；不能只更名既有 APK。說明開發包不會自動繼承原設定。

獲得卸載授權時：

```sh
adb -s "$DEVICE_SERIAL" uninstall "$APP_ID"
adb -s "$DEVICE_SERIAL" install "$APK"
```

卸載成功後若安裝失敗，優先解決安裝，不把工作回報為已完成。其他安裝錯誤依實際原因處理，不因一次失敗就清除資料或換應用 ID。

## 5. 驗證與回報

```sh
adb -s "$DEVICE_SERIAL" shell dumpsys package "$APP_ID"
adb -s "$DEVICE_SERIAL" shell pidof "$APP_ID"
```

只擷取驗證需要的資訊：`versionName`、`versionCode`、`lastUpdateTime` 與新啟動的 PID。初始化後用 `adb -s "$DEVICE_SERIAL" logcat -d --pid="$APP_PID" -v brief` 查看該程序的 `FATAL EXCEPTION`、`Fatal signal`、`SCRIPT ERROR`、`SHADER ERROR` 及相關 OpenXR 錯誤；不清空全機 logcat，也不輸出無關使用者資料。若程序很快退出，查看本次啟動時段的崩潰日誌，不能僅以安裝成功結案為啟動正常。

回報裝置、實際版本與建置類型、是否包含目前修改、安裝及啟動結果、資料是否保留，以及實際發現的阻礙。進程存活或未見致命錯誤不代表頭顯畫面、立體顯示與播放表現已驗證；必要時請使用者戴上頭顯確認。不要將系統選單蓋住畫面、未戴頭顯或 OpenXR 尚未進入顯示狀態，直接描述成畫面正常。保留本機日誌以便排查，不提交 APK、簽章或裝置私有日誌。
