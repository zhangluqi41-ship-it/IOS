/// 占位库。
///
/// 本插件只在 iOS 侧提供原生实现，Dart 侧没有任何代码 ——
/// 应用直接走 `MethodChannel`，通道名与安卓侧完全一致：
///
/// * `com.xiaoqi.expiry_manager/prefs`
/// * `com.xiaoqi.expiry_manager/save`
/// * `com.xiaoqi.expiry_manager/printer`
///
/// 之所以做成「插件」而不是直接往 `ios/Runner` 里塞文件：
/// Flutter 会自动把插件注册进 `GeneratedPluginRegistrant`，
/// 于是**不需要手改 `project.pbxproj`、也不需要动 AppDelegate**。
library;
