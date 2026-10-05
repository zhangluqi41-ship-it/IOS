plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.xiaoqi.expiry_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.xiaoqi.expiry_manager"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 只打包 arm64-v8a。
        // 原因：mobile_scanner 的 MLKit 会额外带入 x86_64/armeabi-v7a 的原生库，
        // 导致设备安装器优先挑 x86_64 装，而 Flutter 引擎只有 arm64，
        // 启动即报 `libflutter.so is for EM_AARCH64 instead of EM_X86_64`。
        // 锁定 ABI 后，模拟器会回退到 arm64 + ARM 转译（与上一版行为一致）。
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // 硕方 SDK 没有官方混淆规则，见 proguard-rules.pro
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 硕方官方 T50 系列蓝牙打印 SDK（明文字节码，Java 8 编译）。
    // 提供 BluetoothManager（经典蓝牙 SPP 连接）与 PrintParameter（纸张类型/间隙等）。
    // 注意：该 jar 使用私有协议，仅能与硕方自家机型通信。
    implementation(files("libs/supvan.jar"))
}

flutter {
    source = "../.."
}
