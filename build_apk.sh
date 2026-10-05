#!/bin/bash
# 效期管理程序 —— 一键构建 APK
# 用法：bash build_apk.sh
set -e

PROJ=/d/AndroidDev/projects/expiry_manager
export JAVA_HOME="D:\\AndroidDev\\jdk17"
export ANDROID_HOME="D:\\AndroidDev\\android-sdk"
export ANDROID_SDK_ROOT="D:\\AndroidDev\\android-sdk"
export FLUTTER_ROOT="D:\\AndroidDev\\flutter"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

echo "== 1/2 拉依赖（用 dart 自带 pub，绕开 flutter 工具层的 preload 故障）=="
cd "$PROJ"
/d/AndroidDev/flutter/bin/cache/dart-sdk/bin/dart.exe pub get

echo "== 2/2 构建 release APK（直接调 Gradle）=="
cd "$PROJ/android"
./gradlew assembleRelease -Ptarget=lib/main.dart -Ptarget-platform=android-arm64

echo
echo "== APK 产物 =="
find "$PROJ/build" -name "*.apk"
