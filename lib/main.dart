import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'ios/ios_nav.dart';
import 'ios/ios_shell.dart';
import 'ios/ios_theme.dart';
import 'nav.dart';
import 'prefs.dart';
import 'printer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 读一次本地设置（制作人 / 上次选的型号 / 上次的打印参数）
  await AppPrefs.load();
  runApp(const ExpiryApp());
}

/// 效期管理系统 —— 按平台分流两套完全独立的 UI。
///
/// **架构决策（对应用户需求第 3、8 条）**：
/// 不再「安卓写完硬转 iOS」，而是**两端各自实现**：
///  * iOS → `CupertinoApp` + [IosHomeShell]（`lib/ios/` 下一整套 Cupertino 组件）
///  * 安卓 → `MaterialApp` + [HomeShell]（`lib/ui_kit.dart` 那套 Material 组件）
///
/// 业务逻辑（`label_template` / `label_renderer` / `printer` / `prefs`）
/// **两端共用**，只有表现层分开，避免逻辑分叉。
class ExpiryApp extends StatelessWidget {
  const ExpiryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return kIsIos ? const _IosApp() : const _AndroidApp();
  }
}

// ===========================================================================
// iOS 分支
// ===========================================================================

class _IosApp extends StatelessWidget {
  const _IosApp();

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: '效期管理系统',
      debugShowCheckedModeBanner: false,
      // ★ 必须注册 CNTabBarRouteObserver：
      //   CNTabBar 等原生组件是嵌进 Flutter 的原生视图，其 Liquid Glass 光晕
      //   会渗出自身边界。这个观察器负责在弹窗 / sheet 弹出时把光晕收住、
      //   并让底栏在整屏 sheet 之上自动隐藏，否则会出现
      //   「玻璃穿透弹窗」和「sheet 里的输入框被底栏盖住」。
      navigatorObservers: <NavigatorObserver>[
        iosRouteObserver,
        CNTabBarRouteObserver(),
      ],
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: IosColors.brand,
        scaffoldBackgroundColor: IosColors.groupedLight,
        barBackgroundColor: IosColors.cardLight,
        textTheme: CupertinoTextThemeData(
          primaryColor: IosColors.brand,
        ),
      ),
      home: const IosHomeShell(),
    );
  }
}

// ===========================================================================
// 安卓分支
// ===========================================================================

class _AndroidApp extends StatelessWidget {
  const _AndroidApp();

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF00695C);
    return MaterialApp(
      title: '效期管理程序',
      debugShowCheckedModeBanner: false,
      navigatorObservers: <NavigatorObserver>[glassRouteObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF7F9F8),
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
