# Internal: Godot export, Android JNI build and verified APK packaging.
"""Build the Android player on macOS, Linux or Windows.

Tools/SDKs and Android libmpv are supplied by the host.
Only project source roots and the OpenXR addon use FreeCM.
"""

from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import re
import secrets
import signal
import shutil
import subprocess
import sys
import time
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache"
PROJECT = ROOT / "app/godot"
BIN = PROJECT / "addons/quest_player/bin"
LOGS = ROOT / "artifacts/logs"
from configs.dependencies import (
    TOOLCHAIN,
    digest,
    go_environment,
    openlist_workspace,
    export_dependencies,
)
from repomgrandroid.workflow import android_environment

LOCK = {**TOOLCHAIN, **TOOLCHAIN["android"]}


def stop_process(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass  # The command may exit between poll() and killpg().
    process.wait(timeout=15)


def run(
    args, *, cwd=ROOT, env=None, log=None, timeout=1800, fail_on_engine_error=False
):
    if log:
        LOGS.mkdir(parents=True, exist_ok=True)
        path = LOGS / log
        with path.open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(
                [str(x) for x in args],
                cwd=cwd,
                env=env,
                stdout=stream,
                stderr=subprocess.STDOUT,
                start_new_session=os.name != "nt",
            )
            deadline = time.monotonic() + timeout
            try:
                while process.poll() is None:
                    if fail_on_engine_error:
                        text = path.read_text(encoding="utf-8", errors="replace")
                        if re.search(
                            r"(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)", text
                        ):
                            raise RuntimeError(
                                f"Godot reported an error; see artifacts/logs/{log}"
                            )
                    if time.monotonic() >= deadline:
                        raise RuntimeError(
                            f"Command timed out after {timeout}s; see artifacts/logs/{log}"
                        )
                    time.sleep(0.2)
            finally:
                stop_process(process)
        if process.returncode:
            raise RuntimeError(f"Command failed; see artifacts/logs/{log}")
    else:
        subprocess.run(
            [str(x) for x in args], cwd=cwd, env=env, check=True, timeout=timeout
        )


def patch_export_path(config):
    """Godot emits opaque file:D:/ URIs which Gradle 9 no longer accepts."""
    needle = "    return exportPath\n"
    if config.count(needle) != 1:
        raise RuntimeError(
            "Godot export-path configuration changed; review the template"
        )
    return config.replace(
        needle,
        """    if (System.getProperty("os.name").startsWith("Windows") && exportPath.matches("file:[A-Za-z]:/.*")) {
        exportPath = new File(new URI("file:/" + exportPath.substring(5))).getPath()
    }
    return exportPath
""",
        1,
    )


def export_executable(godot):
    executable = Path(shutil.which(str(godot)) or godot)
    if os.name == "nt" and executable.name.lower().endswith("_console.exe"):
        # The console launcher can retain inherited handles after the engine
        # exits following an Android/Gradle export. Capture the engine directly.
        engine = executable.with_name(executable.name[: -len("_console.exe")] + ".exe")
        if not engine.is_file():
            raise RuntimeError(f"Matching Godot engine executable is missing: {engine}")
        return engine
    return executable


def extract(archive, destination):
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            path = (destination / entry.filename).resolve()
            if not path.is_relative_to(destination):
                raise RuntimeError("Unsafe dependency archive path")
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise RuntimeError("Dependency archive contains a symbolic link")
        source.extractall(destination)


def build_lock():
    from freecm.workspace_lock import workspace_mutation_lock

    return workspace_mutation_lock(ROOT)


def sdk_directory(env):
    value = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    if value:
        return Path(value).expanduser().absolute()
    if os.name == "nt":
        return Path(env.get("LOCALAPPDATA", Path.home())) / "Android/Sdk"
    return Path.home() / (
        "Library/Android/sdk" if sys.platform == "darwin" else "Android/Sdk"
    )


def installed_sdk_component(sdk, directory, marker, *, preferred=""):
    base = Path(sdk) / directory
    if preferred:
        selected = base / preferred
        if not (selected / marker).exists():
            raise RuntimeError(f"Configured Android component is missing: {selected}")
        return preferred
    candidates = (
        [
            path
            for path in base.iterdir()
            if path.is_dir()
            and re.fullmatch(r"\d+(?:\.\d+)*", path.name)
            and (path / marker).exists()
        ]
        if base.is_dir()
        else []
    )
    if not candidates:
        raise RuntimeError(f"Preinstall an Android {directory} component under {base}")
    return max(candidates, key=lambda path: tuple(map(int, path.name.split(".")))).name


def sdk_tools(env=None):
    env = os.environ if env is None else env
    sdk = sdk_directory(env)
    return {
        "ndk": installed_sdk_component(
            sdk,
            "ndk",
            "build/cmake/android.toolchain.cmake",
            preferred=env.get("IMMIVIO_NDK_VERSION", ""),
        ),
        "cmake": installed_sdk_component(
            sdk, "cmake", "bin", preferred=env.get("IMMIVIO_CMAKE_VERSION", "")
        ),
        "build_tools": installed_sdk_component(
            sdk,
            "build-tools",
            "source.properties",
            preferred=env.get("IMMIVIO_BUILD_TOOLS_VERSION", ""),
        ),
    }


def environment(args, base_env=None):
    env = android_environment(os.environ if base_env is None else base_env)
    sdk = Path(args.sdk).expanduser().absolute() if args.sdk else sdk_directory(env)
    # Preserve host-provided SDK junctions/aliases. On Windows C:\Android can
    # point into Program Files; resolving it breaks gomobile's unquoted CC path.
    sdk = Path(sdk).expanduser().absolute()
    java = args.java_home or env.get("JAVA_HOME")
    if (
        not java
        and os.name != "nt"
        and sys.platform != "darwin"
        and shutil.which("java")
    ):
        java = Path(shutil.which("java")).resolve().parents[1]
    if not java and sys.platform == "darwin":
        java = Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home")
    if (
        not java
        or not (
            Path(java) / "bin" / ("java.exe" if os.name == "nt" else "java")
        ).exists()
    ):
        raise RuntimeError(
            "Set JAVA_HOME to a JDK compatible with the installed Gradle/Android plugin"
        )
    ndk = sdk / "ndk" / args.ndk
    if not (ndk / "build/cmake/android.toolchain.cmake").exists():
        raise RuntimeError(f"Install Android NDK {args.ndk} or pass --ndk")
    if not (sdk / "cmake" / args.cmake).is_dir():
        raise RuntimeError(f"Install Android CMake {args.cmake} or pass --cmake")
    env.update(
        JAVA_HOME=str(Path(java).resolve()),
        ANDROID_HOME=str(sdk),
        ANDROID_SDK_ROOT=str(sdk),
        ANDROID_NDK_HOME=str(ndk),
    )
    env["PATH"] = os.pathsep.join([str(Path(java) / "bin"), env["PATH"]])
    # Java/Gradle do not honor HTTP(S)_PROXY themselves. Use only credential-free proxies.
    proxy_options = []
    for scheme in ("http", "https"):
        proxy = urlsplit(
            env.get(scheme.upper() + "_PROXY", env.get(scheme + "_proxy", ""))
        )
        if proxy.hostname and proxy.scheme in ("http", "https") and not proxy.username:
            proxy_options += [
                f"-D{scheme}.proxyHost={proxy.hostname}",
                f"-D{scheme}.proxyPort={proxy.port or 80}",
            ]
    bypass = env.get("NO_PROXY", env.get("no_proxy", ""))
    if bypass:
        hosts = [item.strip() for item in bypass.split(",") if item.strip()]
        proxy_options.append(
            "-Dhttp.nonProxyHosts="
            + "|".join("*" + host if host.startswith(".") else host for host in hosts)
        )
    env["JAVA_TOOL_OPTIONS"] = " ".join(
        [env.get("JAVA_TOOL_OPTIONS", ""), *proxy_options]
    ).strip()
    env["ORG_GRADLE_PROJECT_android.jetifier.ignorelist"] = "bcprov-jdk18on"
    env.setdefault("GRADLE_USER_HOME", str(Path.home() / ".gradle"))
    env["GRADLE_EXE"] = str(args.gradle)
    env["IMMIVIO_OFFLINE_BUILD"] = "1"
    return env, sdk


def mpv_directory():
    value = os.environ.get("IMMIVIO_MPV_LIB_DIR")
    if not value:
        raise RuntimeError(
            "Preinstall Android ARM64 libmpv and set IMMIVIO_MPV_LIB_DIR; see docs/BUILD.md"
        )
    return Path(value).expanduser().absolute()


def mpv_libraries():
    record = json.loads((ROOT / "third_party/mpv/manifest.json").read_text())
    directory = mpv_directory()
    libraries = {}
    for library in record["libraries"]:
        if library["name"] not in record["packaged_libraries"]:
            continue
        path = directory / library["name"]
        if (
            not path.is_file()
            or path.stat().st_size != library["bytes"]
            or digest(path) != library["sha256"]
        ):
            raise RuntimeError(
                f"Missing or incompatible Android libmpv library: {path}"
            )
        libraries[library["name"]] = path
    return libraries


def prepare_mpv():
    libraries = mpv_libraries()  # Validate every input before staging any file.
    destination = ROOT / "android/player-plugin/src/main/jniLibs/arm64-v8a"
    destination.mkdir(parents=True, exist_ok=True)
    for name, path in libraries.items():
        shutil.copy2(path, destination / name)


def prepare_openlist(env):
    source, inputs = openlist_workspace()
    env = go_environment(env)
    cache = ROOT / "build/openlist-output"
    cache.mkdir(parents=True, exist_ok=True)
    inputs = {
        **inputs,
        "ndk": env["ANDROID_NDK_HOME"],
        "go": subprocess.check_output(["go", "version"], env=env, text=True).strip(),
        "recipe": digest(Path(__file__)),
        "binding_tools": {
            name: digest(shutil.which(name, path=env["PATH"]))
            for name in ("gomobile", "gobind")
            if shutil.which(name, path=env["PATH"])
        },
    }
    stamp, output = cache / "android-build.json", BIN / "cloudcore.aar"
    if output.exists() and stamp.exists():
        receipt = json.loads(stamp.read_text())
        if receipt.get("inputs") == inputs and receipt.get("sha256") == digest(output):
            return
    executable = shutil.which("gomobile", path=env["PATH"])
    if not executable:
        raise RuntimeError(
            "Preinstall gomobile and gobind in PATH; see configs/toolchain.json"
        )
    pending = cache / "cloudcore.pending.aar"
    before = {name: digest(source / name) for name in ("go.mod", "go.sum")}
    # gomobile hides module-graph lookup failures and later reports an empty
    # generated go.mod. Fail here with the actual missing-module diagnostic.
    run(
        ["go", "list", "-m", "-json", "-tags=android", "all"],
        cwd=source,
        env=dict(env, GOOS="android", GOARCH="arm64"),
        log="openlist-modules.log",
    )
    run(
        [
            executable,
            "bind",
            "-target=android/arm64",
            "-androidapi",
            "29",
            "-javapkg",
            "org.vrpassthroughplayer",
            "-ldflags",
            "-s -w -extldflags=-Wl,-z,max-page-size=16384",
            "-o",
            pending,
            "./cloudcore",
        ],
        cwd=source,
        env=env,
        log="openlist-build.log",
    )
    if before != {name: digest(source / name) for name in before}:
        raise RuntimeError("Binding changed the locked Go manifests")
    with zipfile.ZipFile(pending) as archive:
        if archive.testzip() or not {"classes.jar", "jni/arm64-v8a/libgojni.so"} <= set(
            archive.namelist()
        ):
            raise RuntimeError("Incomplete OpenList AAR")
    BIN.mkdir(parents=True, exist_ok=True)
    pending.replace(output)
    stamp.write_text(
        json.dumps({"inputs": inputs, "sha256": digest(output)}, indent=2) + "\n"
    )


def gradle_executable(args):
    path = Path(args.gradle)
    if not path.is_file():
        raise RuntimeError("Preinstall Gradle and set GRADLE_EXE or PATH")
    return path


def template_directory(args, env):
    version = subprocess.check_output(
        [args.godot, "--headless", "--version"], env=env, text=True
    ).strip()
    name = version.split(".official")[0]
    configured = args.templates or env.get("GODOT_TEMPLATES_DIR")
    if configured:
        return Path(configured).expanduser().absolute(), version
    if sys.platform == "darwin":
        base = Path.home() / "Library/Application Support/Godot/export_templates"
    elif os.name == "nt":
        base = Path(env["APPDATA"]) / "Godot/export_templates"
    else:
        base = (
            Path(env.get("XDG_DATA_HOME", Path.home() / ".local/share"))
            / "godot/export_templates"
        )
    return base / name, version


def signing_environment(env, *, build_type="Release"):
    env = env.copy()
    prefix = "GODOT_ANDROID_KEYSTORE_" + build_type.upper()
    selected = prefix
    if any(env.get(selected + "_" + key) for key in ("PATH", "USER", "PASSWORD")):
        if not all(
            env.get(selected + "_" + key) for key in ("PATH", "USER", "PASSWORD")
        ):
            raise RuntimeError("Provide all " + selected + "_* variables")
        env.update(
            {
                prefix + "_" + key: env[selected + "_" + key]
                for key in ("PATH", "USER", "PASSWORD")
            }
        )
        return env
    directory = ROOT / "artifacts/signing"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Preserve the existing ordinary-player signing key for upgrade compatibility.
    stem = "thru3d" if (directory / "thru3d-signing.json").exists() else "immivio"
    credentials = directory / (stem + "-signing.json")
    keystore = directory / (stem + "-release.keystore")
    alias = "immivio"
    if not credentials.exists():
        if keystore.exists():
            raise RuntimeError(
                "Signing key exists without credentials; restore its credentials"
            )
        password = secrets.token_hex(32)
        key_env = env.copy()
        key_env["IMMIVIO_KEYSTORE_PASSWORD"] = password
        run(
            [
                Path(env["JAVA_HOME"])
                / "bin"
                / ("keytool.exe" if os.name == "nt" else "keytool"),
                "-genkeypair",
                "-keystore",
                keystore,
                "-storetype",
                "PKCS12",
                "-alias",
                alias,
                "-keyalg",
                "RSA",
                "-keysize",
                "3072",
                "-validity",
                "10000",
                "-dname",
                "CN=Immivio",
                "-storepass:env",
                "IMMIVIO_KEYSTORE_PASSWORD",
                "-keypass:env",
                "IMMIVIO_KEYSTORE_PASSWORD",
            ],
            env=key_env,
            log=stem + "-key-generation.log",
        )
        credentials.write_text(
            json.dumps(
                {"keystore": str(keystore), "alias": alias, "password": password}
            )
        )
        if os.name != "nt":
            credentials.chmod(0o600)
            keystore.chmod(0o600)
    saved = json.loads(credentials.read_text())
    saved_path = Path(saved["keystore"])
    if not saved_path.is_file():
        # A copied Windows/macOS workspace can retain the old absolute path.
        # Reuse only the same named key beside its credentials; never generate a replacement.
        recorded_name = saved["keystore"].replace("\\", "/").rsplit("/", 1)[-1]
        relocated = directory / recorded_name
        if recorded_name != keystore.name or not relocated.is_file():
            raise RuntimeError("Saved signing key is missing")
        saved_path = relocated
    env.update(
        {
            prefix + "_PATH": str(saved_path),
            prefix + "_USER": saved["alias"],
            prefix + "_PASSWORD": saved["password"],
        }
    )
    return env


def android_identity():
    # Keep the installed ordinary player's ID and data through the rename.
    return {"application_id": "com.wapok.thru3d", "application_label": "Immivio"}


@contextmanager
def variant_export_presets():
    path = PROJECT / "export_presets.cfg"
    original = path.read_bytes()
    identity = android_identity()
    text = original.decode("utf-8")
    for field, value in [
        ("package/unique_name", identity["application_id"]),
        ("package/name", identity["application_label"]),
    ]:
        text, count = re.subn(
            r"(?m)^" + re.escape(field) + r'="[^"]*"\r?$',
            field + "=" + json.dumps(value),
            text,
        )
        if count != 3:
            raise RuntimeError("Android export presets changed: " + field)
    try:
        path.write_text(text, encoding="utf-8")
        yield identity
    finally:
        path.write_bytes(original)


def inspect_package(path, env, sdk):
    native = ROOT / "artifacts/native-inspection" / path.stem
    native.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise RuntimeError("APK archive failed CRC validation")
        names = set(archive.namelist())
        required = {
            "lib/arm64-v8a/" + name
            for name in (
                "libquest_media.so",
                "libquest_mpv.so",
                "libquest_render_bridge.so",
                "libgodot_android.so",
                "libgojni.so",
                "libmpv.so",
            )
        }
        if not required <= names:
            raise RuntimeError(f"Missing packaged libraries: {required - names}")
        if any(
            re.match(
                r"assets/(rvm|rvm-mnn|depth-mnn|ai-models)/|lib/[^/]+/lib(quest_rvm|MNN[^/]*|ncnn)\.so$",
                n,
            )
            for n in names
        ):
            raise RuntimeError(
                "Immivio APK contains removed inference libraries/models"
            )
        if any(
            n.startswith("lib/") and not n.startswith("lib/arm64-v8a/") for n in names
        ):
            raise RuntimeError("Unexpected APK architecture")
        for name in names:
            if name.startswith("lib/arm64-v8a/") and name.endswith(".so"):
                (native / Path(name).name).write_bytes(archive.read(name))
    host = (
        "darwin-x86_64"
        if sys.platform == "darwin"
        else ("windows-x86_64" if os.name == "nt" else "linux-x86_64")
    )
    llvm = Path(env["ANDROID_NDK_HOME"]) / "toolchains/llvm/prebuilt" / host
    suffix = ".exe" if os.name == "nt" else ""
    libraries = [
        native / Path(name).name
        for name in names
        if name.startswith("lib/arm64-v8a/") and name.endswith(".so")
    ]
    system = [
        p
        for p in (llvm / "sysroot/usr/lib/aarch64-linux-android/29").glob("*.so")
        if p.read_bytes()[:4] == b"\x7fELF"
    ]
    supplied = {p.name for p in libraries + system}
    exports, closure = set(), []
    for library in libraries + system:
        output = subprocess.check_output(
            [
                str(llvm / "bin" / ("llvm-nm" + suffix)),
                "-D",
                "--defined-only",
                str(library),
            ],
            text=True,
        )
        exports.update(
            line.split()[-1].split("@")[0]
            for line in output.splitlines()
            if len(line.split()) >= 2
        )
    for library in libraries:
        output = subprocess.check_output(
            [
                str(llvm / "bin" / ("llvm-readelf" + suffix)),
                "-W",
                "-h",
                "-l",
                "-d",
                str(library),
            ],
            text=True,
        )
        loads = [
            line for line in output.splitlines() if line.strip().startswith("LOAD ")
        ]
        needed = re.findall(r"\(NEEDED\).*?\[(.*?)\]", output)
        if (
            "AArch64" not in output
            or not loads
            or any(int(line.split()[-1], 16) < 16384 for line in loads)
        ):
            raise RuntimeError(f"Invalid ELF architecture/alignment: {library.name}")
        if not set(needed) <= supplied:
            raise RuntimeError(
                f"Unpackaged ELF dependency: {library.name}: {set(needed) - supplied}"
            )
        symbols = subprocess.check_output(
            [
                str(llvm / "bin" / ("llvm-nm" + suffix)),
                "-D",
                "--undefined-only",
                str(library),
            ],
            text=True,
        )
        missing = [
            line.split()[-1]
            for line in symbols.splitlines()
            if len(line.split()) >= 2
            and line.split()[0] == "U"
            and line.split()[-1].split("@")[0] not in exports
        ]
        if missing:
            raise RuntimeError(f"Unresolved ELF symbols: {library.name}: {missing}")
        closure.append({"library": library.name, "needed": needed})
    (native / "elf-closure.json").write_text(json.dumps(closure, indent=2) + "\n")
    tools = sdk / "build-tools/36.1.0"
    run(
        [
            tools / ("apksigner.bat" if os.name == "nt" else "apksigner"),
            "verify",
            "--verbose",
            "--print-certs",
            path,
        ],
        env=env,
        log="base-apk-signature.log",
    )
    run(
        [
            tools / ("zipalign.exe" if os.name == "nt" else "zipalign"),
            "-c",
            "-P",
            "16",
            "-v",
            "4",
            path,
        ],
        env=env,
        log="base-apk-alignment.log",
    )
    run(
        [
            tools / ("aapt2.exe" if os.name == "nt" else "aapt2"),
            "dump",
            "badging",
            path,
        ],
        env=env,
        log="base-apk-manifest.log",
    )
    badging = (LOGS / "base-apk-manifest.log").read_text()
    identity = android_identity()
    if not re.search(
        r"(?m)^package: name='" + re.escape(identity["application_id"]) + r"'", badging
    ):
        raise RuntimeError("APK package differs from the Immivio identity")
    if "application-label:'" + identity["application_label"] + "'" not in badging:
        raise RuntimeError("APK launcher label differs from the Immivio identity")
    return digest(path)


def configure_project(args, env, sdk):
    templates, engine = template_directory(args, env)
    source_zip = templates / "android_source.zip"
    if not source_zip.exists():
        raise RuntimeError(
            f"Install Android export templates matching {engine}, or pass --templates"
        )
    api = ROOT / "build/godot-api/godot-lib.template_debug.aar"
    api.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source_zip) as archive:
        api.write_bytes(archive.read("libs/debug/godot-lib.template_debug.aar"))
    gradle_executable(args)
    properties = [
        f"-PandroidGradlePluginVersion={LOCK['android_gradle_plugin']}",
        f"-PkotlinPluginVersion={LOCK['kotlin']}",
        "-Pandroid.builtInKotlin=false",
        "-Pandroid.newDsl=false",
        f"-PandroidNdkVersion={args.ndk}",
        f"-PandroidCmakeVersion={args.cmake}",
        f"-PandroidCompileSdk={TOOLCHAIN['android']['platform']}",
        f"-PandroidBuildToolsVersion={args.build_tools}",
        f"-PandroidMinSdk={TOOLCHAIN['android']['min_sdk']}",
        f"-PgodotAarPath={api}",
        "--console=plain",
    ]
    # Materialize the matching engine template; never edit the installed copy.
    android = PROJECT / "android/build"
    android.mkdir(parents=True, exist_ok=True)
    extract(source_zip, android)
    (android.parent / ".gdignore").touch()
    (android.parent / ".build_version").write_text(
        (templates / "version.txt").read_text()
    )
    if os.name != "nt":
        (android / "gradlew").chmod(0o755)
    config = android / "config.gradle"
    text = config.read_text()
    for name, value in [
        ("androidGradlePlugin", LOCK["android_gradle_plugin"]),
        ("kotlinVersion", LOCK["kotlin"]),
        ("ndkVersion", args.ndk),
    ]:
        text, count = re.subn(
            r"(\b" + name + r"\s*:\s*)'[^']+'",
            lambda m: m[1] + repr(value),
            text,
            count=1,
        )
        if count != 1:
            raise RuntimeError(f"Godot Android template configuration changed: {name}")
    config.write_text(patch_export_path(text))
    # Godot invokes gradlew itself. Forward it to the installed Gradle instead
    # of letting the template wrapper download a distribution during export.
    for name in ("gradlew", "gradlew.bat"):
        shutil.copy2(ROOT / "android" / name, android / name)
    with (android / "gradle.properties").open("a") as stream:
        stream.write(
            "\nandroid.builtInKotlin=false\nandroid.newDsl=false\nandroid.jetifier.ignorelist=bcprov-jdk18on\n"
        )
        stream.write(
            "plugins_remote_binaries=" + "|".join(export_dependencies()) + "\n"
        )
    # Multi-release OSGi manifests have duplicate paths in BC/jspecify.
    gradle_file = android / "build.gradle"
    text = gradle_file.read_text()
    text = text.replace(
        "    packagingOptions {",
        "    packagingOptions {\n        exclude 'META-INF/versions/*/OSGI-INF/MANIFEST.MF'",
        1,
    )
    gradle_file.write_text(text)
    # Use the same strict catalog and verification policy for Godot's generated project.
    shutil.copytree(ROOT / "android/gradle", android / "gradle", dirs_exist_ok=True)
    for filename in ("libs.versions.toml", "verification-metadata.xml"):
        shutil.copy2(ROOT / "android/gradle" / filename, android / "gradle" / filename)
    shutil.copy2(
        ROOT / "android/gradle/dependency-cache.gradle",
        android / "dependency-cache.gradle",
    )
    with (android / "build.gradle").open("a") as stream:
        stream.write("\napply from: 'dependency-cache.gradle'\n")
    # The generated export uses the same dependency verification and lock files.
    export_locks = ROOT / "android/export-locks"
    if export_locks.is_dir():
        shutil.copytree(export_locks, android, dirs_exist_ok=True)
    offline_script = Path(env["GRADLE_USER_HOME"]) / "init.d/immivio-offline.gradle"
    offline_script.parent.mkdir(parents=True, exist_ok=True)
    offline_script.write_text(
        "if (System.getenv('IMMIVIO_OFFLINE_BUILD') == '1') { gradle.startParameter.offline = true }\n"
    )
    configure_android_editor(args, env, sdk)

    generated = ROOT / "build/android.properties"
    generated.parent.mkdir(parents=True, exist_ok=True)
    generated.write_text(
        "\n".join(p[2:].replace("\\", "\\\\") for p in properties if p.startswith("-P"))
        + "\n"
    )


def build_plugin(args, env, sdk):
    gradle_executable(args)
    print("Building Android plugin", flush=True)
    run(
        [
            args.gradle,
            "-p",
            str(ROOT / "android"),
            "--offline",
            "--console=plain",
            ":player-plugin:assemble" + args.build_type,
        ],
        env=env,
        log="base-plugin-build.log",
    )
    variant = args.build_type.lower()
    shutil.copy2(
        ROOT / f"android/player-plugin/build/outputs/aar/player-plugin-{variant}.aar",
        BIN,
    )


def package(args, env, sdk):
    variant = args.build_type.lower()
    templates, engine = template_directory(args, env)
    env = signing_environment(env, build_type=args.build_type)
    version = re.search(
        r'(?m)^config/version="([^"]+)"', (PROJECT / "project.godot").read_text()
    )[1]
    platform_name = {"Quest": "QUEST", "Pico": "PICO", "OpenXR": "OpenXR"}[args.vendor]
    output = (
        ROOT
        / f"artifacts/Immivio-{platform_name}-{version}-{variant}-{datetime.now():%Y%m%d}.apk"
    )
    preset = {"Quest": "Quest 3", "Pico": "PICO 4", "OpenXR": "OpenXR (Experimental)"}[
        args.vendor
    ]
    # An early/failed export must not leave a previous package looking current.
    output.unlink(missing_ok=True)
    output.with_suffix(".build.json").unlink(missing_ok=True)
    print(f"Exporting {output.name}", flush=True)
    env["IMMIVIO_OFFLINE_BUILD"] = "1"
    try:
        with variant_export_presets():
            run(
                [
                    export_executable(args.godot),
                    "--headless",
                    "--xr-mode",
                    "off",
                    "--path",
                    PROJECT,
                    "--export-release" if variant == "release" else "--export-debug",
                    preset,
                    output,
                ],
                env=env,
                log="base-godot-export.log",
                timeout=900,
                fail_on_engine_error=True,
            )
    finally:
        password = env.get(
            "GODOT_ANDROID_KEYSTORE_" + args.build_type.upper() + "_PASSWORD"
        )
        if password and (LOGS / "base-godot-export.log").exists():
            log = LOGS / "base-godot-export.log"
            log.write_text(log.read_text().replace(password, "<redacted>"))
    if re.search(
        r"(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)",
        (LOGS / "base-godot-export.log").read_text(),
    ):
        raise RuntimeError(
            "Godot export reported errors; see artifacts/logs/base-godot-export.log"
        )
    sha = inspect_package(output, env, sdk)
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    dirty = bool(
        subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=ROOT, text=True
        ).strip()
    )
    certificate = re.search(
        r"Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})",
        (LOGS / "base-apk-signature.log").read_text(),
    )
    if not certificate:
        raise RuntimeError("APK signing certificate is missing")
    from configs.android_workflow import dependency_receipt

    receipt = {
        **dependency_receipt(),
        **android_identity(),
        "signing_certificate_sha256": certificate[1],
        "apk": output.name,
        "sha256": sha,
        "product": "Immivio",
        "godot": engine,
        "vendor": args.vendor,
        "build_type": args.build_type,
        "source_commit": revision,
        "source_dirty": dirty,
        "ndk": args.ndk,
        "cmake": args.cmake,
        "dependency_lock_sha256": digest(ROOT / "source_roots.lock.jsonc"),
        "openlist_aar_sha256": digest(BIN / "cloudcore.aar"),
        "device_execution": "not_verified",
    }
    (output.with_suffix(".build.json")).write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Built {output}\nSHA256 {sha}", flush=True)


def configure_android_editor(args, env, sdk):
    setup = ROOT / "build/configure_android_editor.gd"
    setup.write_text(
        'extends SceneTree\nfunc _initialize():\n\tcall_deferred("_configure")\nfunc _configure():\n\tvar settings = EditorInterface.get_editor_settings()\n'
        + '\tsettings.set_setting("export/android/android_sdk_path", '
        + json.dumps(str(sdk))
        + ")\n"
        + '\tsettings.set_setting("export/android/java_sdk_path", '
        + json.dumps(env["JAVA_HOME"])
        + ")\n"
        + '\tvar result = ResourceSaver.save(settings, settings.resource_path)\n\tif result == OK: print("ANDROID_EDITOR_CONFIGURED")\n\telse: quit(1)\n'
    )
    run(
        [
            args.godot,
            "--headless",
            "--xr-mode",
            "off",
            "--path",
            PROJECT,
            "--editor",
            "--quit-after",
            "600",
            "--script",
            setup,
        ],
        env=env,
        log="base-editor-settings.log",
        timeout=600,
    )
    setup_log = (LOGS / "base-editor-settings.log").read_text()
    # Godot's editor + custom SceneTree helper reports editor RIDs on shutdown.
    # The settings must be saved successfully; all other errors remain fatal.
    setup_errors = [
        line
        for line in setup_log.splitlines()
        if line.startswith(("SCRIPT ERROR:", "ERROR:"))
        and not re.fullmatch(
            r"ERROR: [0-9]+ RID allocations of type '.+' were leaked at exit\.", line
        )
    ]
    if "ANDROID_EDITOR_CONFIGURED" not in setup_log or setup_errors:
        raise RuntimeError(
            "Godot editor configuration failed; see artifacts/logs/base-editor-settings.log"
        )
    run(
        [
            args.godot,
            "--headless",
            "--xr-mode",
            "off",
            "--path",
            PROJECT,
            "--editor",
            "--quit-after",
            "600",
        ],
        env=env,
        log="base-godot-import.log",
        timeout=600,
        fail_on_engine_error=True,
    )
    if re.search(
        r"(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)",
        (LOGS / "base-godot-import.log").read_text(),
    ):
        raise RuntimeError(
            "Godot import reported errors; see artifacts/logs/base-godot-import.log"
        )
