import 'dart:convert';

import 'package:flutter/services.dart';

import 'printer.dart';

/// App 级轻量设置 —— 制作人、上次选的打印机型号、上次的打印参数。
///
/// 直接走原生 SharedPreferences，不额外引 Flutter 插件（这点需求不值得多背一个依赖）。
/// 内存里做一层缓存，界面可以同步读，不用等 IO。
class AppPrefs {
  AppPrefs._();

  static const MethodChannel _ch = MethodChannel(
    'com.xiaoqi.expiry_manager/prefs',
  );

  static const _kLastMaker = 'last_maker';
  static const _kLastKind = 'last_printer_kind';
  static const _kPrintOptions = 'last_print_options';

  static String _lastMaker = '';

  /// 上一次填写的制作人 —— 模板页打开时用它做默认值。
  static String get lastMaker => _lastMaker;

  static PrinterKind _lastKind = PrinterKind.supvan;

  /// 上一次选的打印机型号，添加打印机页默认选中它。
  static PrinterKind get lastKind => _lastKind;

  static PrintOptions _printOptions = const PrintOptions();

  /// 上一次用过的打印参数（浓度、间隙、份数…）。
  static PrintOptions get printOptions => _printOptions;

  /// 启动时调一次，把设置读进内存。
  static Future<void> load() async {
    _lastMaker = await _getString(_kLastMaker) ?? '';
    final kind = await _getString(_kLastKind);
    if (kind != null && kind.isNotEmpty) _lastKind = PrinterKind.fromCode(kind);
    final raw = await _getString(_kPrintOptions);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _printOptions = PrintOptions(
          widthMm: (m['widthMm'] as num?)?.toInt() ?? 50,
          heightMm: (m['heightMm'] as num?)?.toInt() ?? 30,
          copies: (m['copies'] as num?)?.toInt() ?? 1,
          density: (m['density'] as num?)?.toInt() ?? 4,
          speed: (m['speed'] as num?)?.toInt() ?? 3,
          paperType: PaperType.values.firstWhere(
            (e) => e.code == ((m['paperType'] as num?)?.toInt() ?? 1),
            orElse: () => PaperType.gap,
          ),
          gap: (m['gap'] as num?)?.toInt() ?? 3,
          headDots: (m['headDots'] as num?)?.toInt() ?? 400,
          invert: m['invert'] as bool? ?? false,
          feedLines: (m['feedLines'] as num?)?.toInt() ?? 2,
        );
      } catch (_) {
        // 参数坏了就用默认值
      }
    }
  }

  static Future<void> setLastMaker(String value) async {
    final v = value.trim();
    if (v.isEmpty || v == _lastMaker) return;
    _lastMaker = v;
    await _putString(_kLastMaker, v);
  }

  static Future<void> setLastKind(PrinterKind kind) async {
    if (kind == _lastKind) return;
    _lastKind = kind;
    await _putString(_kLastKind, kind.code);
  }

  static Future<void> setPrintOptions(PrintOptions o) async {
    _printOptions = o;
    await _putString(
      _kPrintOptions,
      jsonEncode({
        'widthMm': o.widthMm,
        'heightMm': o.heightMm,
        'copies': o.copies,
        'density': o.density,
        'speed': o.speed,
        'paperType': o.paperType.code,
        'gap': o.gap,
        'headDots': o.headDots,
        'invert': o.invert,
        'feedLines': o.feedLines,
      }),
    );
  }

  static Future<String?> _getString(String key) async {
    try {
      return await _ch.invokeMethod<String>('getString', {'key': key});
    } on MissingPluginException {
      return null; // 桌面 / 测试环境没有原生实现
    } catch (_) {
      return null;
    }
  }

  static Future<void> _putString(String key, String value) async {
    try {
      await _ch.invokeMethod<bool>('setString', {'key': key, 'value': value});
    } catch (_) {
      // 写失败只影响下次的默认值，忽略
    }
  }
}
