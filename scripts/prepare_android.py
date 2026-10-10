#!/usr/bin/env python3
"""
Configures the Android project that `flutter create` generates in CI (the android/ folder is not
committed, so it always matches the pinned Flutter version). Idempotent: safe to run twice.

  * application id  com.dazzlingwins.app, label "DazzlingWins"
  * Android Gradle Plugin / Gradle / Kotlin raised to versions current AndroidX libraries need
  * release signing from android/key.properties (written by CI from repository secrets)
  * core library desugaring (required by flutter_local_notifications)
  * minSdk 23 (Android 6+, needed by the voice-note recorder)
  * permissions: INTERNET, POST_NOTIFICATIONS, RECORD_AUDIO, REQUEST_INSTALL_PACKAGES; backups off; cleartext (http) traffic off
  * https <queries> so url_launcher can open links and the APK download
  * Google sign-in callback activity (scheme dazzlingwins://auth)
  * notification small icon and the dark brand launch background (no white flash)
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
APP = ANDROID / "app"
APP_ID = "com.dazzlingwins.app"
# Android build tooling. Flutter 3.27's template pins AGP 8.1.0, but current AndroidX libraries
# (e.g. androidx.webkit used by webview_flutter) need AGP 8.1.1+. These versions work together:
# AGP 8.6.1 requires Gradle 8.7+; Kotlin 1.9.24 compiles every plugin in pubspec.yaml.
AGP_VERSION = "8.6.1"
GRADLE_VERSION = "8.7"
KOTLIN_VERSION = "1.9.24"
# Android 6.0. The voice-note recorder (record) needs it; Flutter's default is 21.
MIN_SDK = 23
# Current AndroidX libraries (pulled in by the audio plugins) need to be compiled against API 35.
COMPILE_SDK = 35
BG = "#FF07060E"


def fail(msg: str) -> None:
    print(f"prepare_android: {msg}", file=sys.stderr)
    sys.exit(1)


def patch_groovy(path: pathlib.Path) -> None:
    s = path.read_text(encoding="utf-8")
    if "DW_PATCHED" in s:
        return
    s = re.sub(r'applicationId\s*=?\s*"[^"]+"', f'applicationId = "{APP_ID}"', s, count=1)
    s = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", f"minSdk = {MIN_SDK}", s, count=1)
    s = re.sub(r"compileSdk(Version)?\s*=?\s*flutter\.compileSdkVersion", f"compileSdk = {COMPILE_SDK}", s, count=1)
    loader = (
        "// DW_PATCHED: release signing from key.properties (written by CI)\n"
        "def keystoreProperties = new Properties()\n"
        "def keystorePropertiesFile = rootProject.file('key.properties')\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystorePropertiesFile.withReader('UTF-8') { reader -> keystoreProperties.load(reader) }\n"
        "}\n\n"
    )
    idx = s.find("android {")
    if idx < 0:
        fail("android { block not found in build.gradle")
    s = s[:idx] + loader + s[idx:]
    if "coreLibraryDesugaringEnabled" not in s:
        s, n = re.subn(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", s, count=1)
        if n == 0:
            s = s.replace("android {", "android {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }", 1)
    signing = (
        "    signingConfigs {\n"
        "        release {\n"
        "            if (keystorePropertiesFile.exists()) {\n"
        "                keyAlias keystoreProperties['keyAlias']\n"
        "                keyPassword keystoreProperties['keyPassword']\n"
        "                storeFile file(keystoreProperties['storeFile'])\n"
        "                storePassword keystoreProperties['storePassword']\n"
        "                storeType keystoreProperties['storeType'] ?: 'pkcs12'\n"
        "            }\n"
        "        }\n"
        "    }\n\n"
    )
    idx = s.find("    buildTypes {")
    if idx < 0:
        fail("buildTypes block not found in build.gradle")
    s = s[:idx] + signing + s[idx:]
    s, n = re.subn(
        r"signingConfig\s*=?\s*signingConfigs\.debug",
        "signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
        s,
        count=1,
    )
    if n == 0:
        fail("release signingConfig line not found in build.gradle")
    s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    path.write_text(s, encoding="utf-8")


def patch_kts(path: pathlib.Path) -> None:
    s = path.read_text(encoding="utf-8")
    if "DW_PATCHED" in s:
        return
    s = re.sub(r'applicationId\s*=\s*"[^"]+"', f'applicationId = "{APP_ID}"', s, count=1)
    s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", f"minSdk = {MIN_SDK}", s, count=1)
    s = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", f"compileSdk = {COMPILE_SDK}", s, count=1)
    header = (
        "// DW_PATCHED: release signing from key.properties (written by CI)\n"
        "val keystoreProperties = java.util.Properties()\n"
        "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }\n"
        "}\n\n"
    )
    idx = s.find("android {")
    if idx < 0:
        fail("android { block not found in build.gradle.kts")
    s = s[:idx] + header + s[idx:]
    s, n = re.subn(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
    if n == 0:
        fail("compileOptions not found in build.gradle.kts")
    signing = (
        "    signingConfigs {\n"
        "        create(\"release\") {\n"
        "            if (keystorePropertiesFile.exists()) {\n"
        "                keyAlias = keystoreProperties[\"keyAlias\"] as String\n"
        "                keyPassword = keystoreProperties[\"keyPassword\"] as String\n"
        "                storeFile = file(keystoreProperties[\"storeFile\"] as String)\n"
        "                storePassword = keystoreProperties[\"storePassword\"] as String\n"
        "                storeType = (keystoreProperties[\"storeType\"] as String?) ?: \"pkcs12\"\n"
        "            }\n"
        "        }\n"
        "    }\n\n"
    )
    idx = s.find("    buildTypes {")
    if idx < 0:
        fail("buildTypes block not found in build.gradle.kts")
    s = s[:idx] + signing + s[idx:]
    s, n = re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        s,
        count=1,
    )
    if n == 0:
        fail("release signingConfig line not found in build.gradle.kts")
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    path.write_text(s, encoding="utf-8")


def patch_manifest(path: pathlib.Path) -> None:
    s = path.read_text(encoding="utf-8")
    if "DW_PATCHED" in s:
        return
    perms = (
        "    <!-- DW_PATCHED -->\n"
        '    <uses-permission android:name="android.permission.INTERNET" />\n'
        '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n'
        # Live Chat voice notes. Asked for only when the player taps the microphone.
        '    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n'
        # In-app updater: lets Android's installer open the update the app downloaded.
        '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n'
    )
    s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + perms, s, count=1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="DazzlingWins"', s, count=1)
    s = s.replace(
        "<application",
        '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"\n        android:usesCleartextTraffic="false"',
        1,
    )
    # Google sign-in: the website hands the one-time code back to this app via
    # intent://auth?...#Intent;scheme=dazzlingwins;package=com.dazzlingwins.app;end, received by the
    # main activity as a deep link (app_links). singleTask: the link returns to the running app
    # instead of starting a second copy of it.
    s, n = re.subn(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', s, count=1)
    if n == 0:
        s = s.replace('android:name=".MainActivity"', 'android:name=".MainActivity"\n            android:launchMode="singleTask"', 1)
    deep_link = "".join(
        line + "\n"
        for line in (
            '            <intent-filter android:label="DazzlingWins sign-in">',
            '                <action android:name="android.intent.action.VIEW" />',
            '                <category android:name="android.intent.category.DEFAULT" />',
            '                <category android:name="android.intent.category.BROWSABLE" />',
            '                <data android:scheme="dazzlingwins" android:host="auth" />',
            "            </intent-filter>",
        )
    )
    main_activity = s.find('android:name=".MainActivity"')
    end_activity = s.find("</activity>", main_activity)
    if main_activity < 0 or end_activity < 0:
        fail("MainActivity not found in AndroidManifest.xml")
    # Links are handled by app_links only, never pushed as Flutter routes.
    deep_link += '            <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />\n'
    s = s[:end_activity] + deep_link + "        " + s[end_activity:]
    https_query = (
        "        <intent>\n"
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:scheme="https" />\n'
        "        </intent>\n"
        # Lets the app find a Custom Tabs browser, so Google sign-in opens inside the app.
        "        <intent>\n"
        '            <action android:name="android.support.customtabs.action.CustomTabsService" />\n'
        "        </intent>\n"
    )
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>\n" + https_query, 1)
    else:
        s = s.replace("</manifest>", "    <queries>\n" + https_query + "    </queries>\n</manifest>", 1)
    path.write_text(s, encoding="utf-8")


def write_resources() -> None:
    res = APP / "src" / "main" / "res"
    drawable = res / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "assets" / "brand" / "notification_icon.png", drawable / "ic_stat_dw.png")
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "dw_colors.xml").write_text(
        f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="dw_bg">{BG}</color>\n</resources>\n',
        encoding="utf-8",
    )
    launch = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <item android:drawable="@color/dw_bg" />\n'
        "</layer-list>\n"
    )
    for folder in ("drawable", "drawable-v21"):
        d = res / folder
        if d.exists():
            (d / "launch_background.xml").write_text(launch, encoding="utf-8")
    # Keep notification icon from being stripped by resource shrinking.
    raw = res / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    (raw / "keep.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_stat_dw" />\n',
        encoding="utf-8",
    )


def patch_tooling() -> None:
    """Raise AGP / Kotlin in settings.gradle(.kts) and the Gradle wrapper version."""
    for name in ("settings.gradle", "settings.gradle.kts"):
        path = ANDROID / name
        if not path.exists():
            continue
        s = path.read_text(encoding="utf-8")
        s, n_agp = re.subn(
            r'(id\s*\(?\s*"com\.android\.application"\s*\)?\s*version\s*\(?\s*)"[^"]+"',
            lambda m: m.group(1) + f'"{AGP_VERSION}"',
            s,
        )
        s = re.sub(
            r'(id\s*\(?\s*"org\.jetbrains\.kotlin\.android"\s*\)?\s*version\s*\(?\s*)"[^"]+"',
            lambda m: m.group(1) + f'"{KOTLIN_VERSION}"',
            s,
        )
        if n_agp == 0:
            fail(f"Android Gradle Plugin version not found in {name}")
        path.write_text(s, encoding="utf-8")
        break
    else:
        fail("android/settings.gradle(.kts) not found")

    wrapper = ANDROID / "gradle" / "wrapper" / "gradle-wrapper.properties"
    if not wrapper.exists():
        fail("gradle-wrapper.properties not found")
    w = wrapper.read_text(encoding="utf-8")
    w, n = re.subn(
        r"distributionUrl=.*",
        lambda _m: r"distributionUrl=https\://services.gradle.org/distributions/gradle-" + GRADLE_VERSION + "-all.zip",
        w,
    )
    if n == 0:
        fail("distributionUrl not found in gradle-wrapper.properties")
    wrapper.write_text(w, encoding="utf-8")


def main() -> None:
    if not APP.exists():
        fail("android/app not found — run `flutter create --platforms=android .` first")
    groovy = APP / "build.gradle"
    kts = APP / "build.gradle.kts"
    if groovy.exists():
        patch_groovy(groovy)
    elif kts.exists():
        patch_kts(kts)
    else:
        fail("no app build.gradle(.kts) found")
    patch_tooling()
    patch_manifest(APP / "src" / "main" / "AndroidManifest.xml")
    write_resources()
    print("prepare_android: OK")


if __name__ == "__main__":
    main()
