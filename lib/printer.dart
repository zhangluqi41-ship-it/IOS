import 'dart:async';

import 'package:flutter/services.dart';

/// 打印机型号（= 通信协议）。
///
/// 以后要接新品牌，只要在这里加一个枚举值，界面上的「打印机型号」选择会自动多一项；
/// 原生侧 [PrinterBridge] 按 [code] 分派到对应驱动。
enum PrinterKind {
  /// 硕方 T50 Pro / T56 Pro / T50S / T50 Plus —— 官方 SDK 私有协议，能查到状态和耗材。
  supvan(
    'supvan_t50pro',
    '硕方 T50 Pro',
    '官方 SDK 通道 · 可查状态与耗材',
    'supvan',
  ),

  /// 通用标签机 —— TSPL 指令集，佳博/汉印/芯烨等大多数国产标签机都吃这套。
  tspl(
    'generic_tspl',
    '通用标签机',
    'TSPL 指令 · 大多数国产标签机',
    'generic',
  ),

  /// 通用热敏机 —— ESC/POS 光栅指令。
  escpos(
    'generic_escpos',
    '通用热敏机',
    'ESC/POS 指令 · 票据机 / 便携机',
    'generic',
  );

  const PrinterKind(this.code, this.label, this.hint, this.family);

  final String code;

  /// 界面上显示的型号名
  final String label;

  /// 一句话说明
  final String hint;

  /// 驱动大类：supvan = 官方 SDK；generic = 标准蓝牙 SPP
  final String family;

  bool get isGeneric => family == 'generic';

  /// 该型号是否支持「查询状态」。
  bool get supportsStatus => this == PrinterKind.supvan;

  /// 该型号打印头默认点数（203dpi，8 dots/mm，50mm ≈ 400 点）。
  int get defaultHeadDots => this == PrinterKind.escpos ? 384 : 400;

  static PrinterKind fromCode(String? code) => PrinterKind.values.firstWhere(
    (e) => e.code == code,
    orElse: () => PrinterKind.supvan,
  );
}

/// 一台蓝牙设备（已配对或扫描发现的）。
class BtDevice {
  const BtDevice({
    required this.name,
    required this.address,
    required this.bonded,
  });

  final String name;
  final String address;

  /// true = 系统里已配对，连接成功率最高。
  final bool bonded;

  static BtDevice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final address = raw['address'] as String? ?? '';
    if (address.isEmpty) return null;
    return BtDevice(
      name: raw['name'] as String? ?? '未知设备',
      address: address,
      bonded: raw['bonded'] as bool? ?? false,
    );
  }
}

/// 已经「添加」过的打印机（存在原生 SharedPreferences 里，重启 App 仍在）。
class SavedPrinter {
  const SavedPrinter({
    required this.name,
    required this.address,
    this.kind = PrinterKind.supvan,
  });

  final String name;
  final String address;
  final PrinterKind kind;

  /// 卡片副标题显示的短地址（MAC 太长，只留后 8 位便于辨认）。
  String get shortAddress =>
      address.length > 8 ? '…${address.substring(address.length - 8)}' : address;

  SavedPrinter copyWith({String? name, PrinterKind? kind}) => SavedPrinter(
    name: name ?? this.name,
    address: address,
    kind: kind ?? this.kind,
  );

  static SavedPrinter? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final address = raw['address'] as String? ?? '';
    if (address.isEmpty) return null;
    return SavedPrinter(
      name: raw['name'] as String? ?? '打印机',
      address: address,
      kind: PrinterKind.fromCode(raw['kind'] as String?),
    );
  }
}

/// 打印机状态码（对应硕方 SDK 的 GetStatus 返回值；通用机型拿不到，恒为 [unknown]）。
enum PrinterStatus {
  unknown(-1, '未知', '尚未连接到打印机'),
  ready(0, '准备就绪', '可以开始打印'),
  headTooHot(1, '打印头温度过高', '稍等片刻再试'),
  coverOpen(2, '上盖未关好', '请合上打印头上盖'),
  materialBad(3, '耗材未装好', '请重新装入标签纸'),
  materialLow(4, '耗材余量不足', '准备更换标签纸'),
  materialMissing(5, '未检测到耗材', '请装入标签纸'),
  materialUnrecognized(6, '未识别到耗材', '请确认是否为原厂标签纸'),
  materialUsedUp(7, '耗材已用完', '请更换标签纸'),
  batteryLow(8, '电池电压低', '请先充电');

  const PrinterStatus(this.code, this.label, this.hint);

  final int code;
  final String label;
  final String hint;

  static PrinterStatus fromCode(int code) => PrinterStatus.values.firstWhere(
    (e) => e.code == code,
    orElse: () => PrinterStatus.unknown,
  );
}

/// 硕方机型的纸张类型（对应 SDK 的 paperType）。
enum PaperType {
  gap(1, '间隙纸'),
  blackMark(2, '普通黑标'),
  blackMarkCard(5, '黑标卡纸');

  const PaperType(this.code, this.label);

  final int code;
  final String label;
}

/// 打印参数。硕方与通用机型共用一份，各自取用得上的字段。
class PrintOptions {
  const PrintOptions({
    this.widthMm = 50,
    this.heightMm = 30,
    this.copies = 1,
    this.density = 4,
    this.speed = 3,
    this.paperType = PaperType.gap,
    this.gap = 3,
    this.headDots = 400,
    this.invert = false,
    this.feedLines = 2,
  });

  final int widthMm;
  final int heightMm;
  final int copies;

  /// 硕方 1~9；TSPL 0~15
  final int density;

  /// 仅 TSPL 有效，1~6（越大越快越淡）
  final int speed;

  /// 仅硕方有效
  final PaperType paperType;

  /// 纸张间隙 mm（0~8）
  final int gap;

  /// 通用机型打印头点数：384 / 400 / 576
  final int headDots;

  /// 通用机型黑白取反
  final bool invert;

  /// 仅 ESC/POS：打完走纸行数
  final int feedLines;

  PrintOptions copyWith({
    int? copies,
    int? density,
    int? speed,
    PaperType? paperType,
    int? gap,
    int? headDots,
    bool? invert,
    int? feedLines,
  }) => PrintOptions(
    widthMm: widthMm,
    heightMm: heightMm,
    copies: copies ?? this.copies,
    density: density ?? this.density,
    speed: speed ?? this.speed,
    paperType: paperType ?? this.paperType,
    gap: gap ?? this.gap,
    headDots: headDots ?? this.headDots,
    invert: invert ?? this.invert,
    feedLines: feedLines ?? this.feedLines,
  );

  Map<String, Object?> toMap() => {
    'widthMm': widthMm,
    'heightMm': heightMm,
    'copies': copies,
    'density': density,
    'speed': speed,
    'paperType': paperType.code,
    'gap': gap,
    'headDots': headDots,
    'invert': invert,
    'feedLines': feedLines,
  };
}

/// 原生侧主动推上来的事件。
///
/// `connected` / `disconnected` / `printDone` 的 value 是 Map；
/// `status` 是 int；`deviceFound` 是设备 map；`savedChanged` 是变化的 MAC。
class PrinterEvent {
  const PrinterEvent(this.type, this.value);

  /// connected / disconnected / status / printDone / deviceFound /
  /// scanFinished / permission / savedChanged
  final String type;
  final Object? value;

  Map<Object?, Object?>? get _map =>
      value is Map ? value as Map<Object?, Object?> : null;

  /// 连接/打印是否成功。兼容旧格式（裸 bool）与新的 Map 格式。
  bool? get ok {
    final m = _map;
    if (m != null) return m['ok'] as bool?;
    return value is bool ? value as bool : null;
  }

  /// 本次事件关联的设备 MAC。
  String? get address {
    final m = _map;
    if (m != null) return m['address'] as String?;
    final v = value;
    return v is String ? v : null;
  }

  /// 本次事件关联的设备名。
  String? get name => _map?['name'] as String?;

  /// 本次事件关联的打印机型号。
  PrinterKind get kind => PrinterKind.fromCode(_map?['kind'] as String?);
}

/// 蓝牙打印服务（对应原生 PrinterBridge）。
class PrinterService {
  PrinterService._();

  static final PrinterService instance = PrinterService._();

  static const MethodChannel _channel = MethodChannel(
    'com.xiaoqi.expiry_manager/printer',
  );

  final _controller = StreamController<PrinterEvent>.broadcast();

  /// 原生事件流。
  Stream<PrinterEvent> get events => _controller.stream;

  /// 当前已连接的打印机 MAC（null = 未连接）。
  String? get connectedAddress => _connectedAddress;
  String? _connectedAddress;

  /// 当前已连接打印机的型号。
  PrinterKind get connectedKind => _connectedKind;
  PrinterKind _connectedKind = PrinterKind.supvan;

  /// 最近一次打印结果（预览页判断「打完了没」用）。
  PrintOptions lastOptions = const PrintOptions();

  bool _handlerReady = false;

  void _ensureHandler() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEvent') {
        final args = call.arguments;
        if (args is Map) {
          final event = PrinterEvent(
            args['type'] as String? ?? '',
            args['value'],
          );
          switch (event.type) {
            case 'connected':
              if (event.ok == true) {
                _connectedAddress = event.address;
                _connectedKind = event.kind;
              } else {
                _connectedAddress = null;
              }
            case 'disconnected':
              _connectedAddress = null;
          }
          _controller.add(event);
        }
      }
      return null;
    });
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    _ensureHandler();
    return _channel.invokeMethod<T>(method, args);
  }

  /// 设备是否有蓝牙（部分模拟器没有）。
  Future<bool> isSupported() async =>
      await _invoke<bool>('isSupported') ?? false;

  /// 蓝牙开关是否已打开。
  Future<bool> isEnabled() async => await _invoke<bool>('isEnabled') ?? false;

  /// 是否已获得蓝牙权限。
  Future<bool> hasPermission() async =>
      await _invoke<bool>('hasPermission') ?? false;

  /// 申请蓝牙权限，返回是否授予。
  Future<bool> requestPermission() async =>
      await _invoke<bool>('requestPermission') ?? false;

  /// 直接跳到系统蓝牙设置页。
  Future<bool> openBluetoothSettings() async =>
      await _invoke<bool>('openBluetoothSettings') ?? false;

  /// 列出设备：已配对的在前，扫描到的在后。
  Future<List<BtDevice>> listDevices() async {
    final raw = await _invoke<List<Object?>>('listDevices') ?? const [];
    return raw.map(BtDevice.tryParse).whereType<BtDevice>().toList();
  }

  /// 开始扫描附近设备。
  Future<bool> startScan() async => await _invoke<bool>('startScan') ?? false;

  /// 停止扫描。
  Future<bool> stopScan() async => await _invoke<bool>('stopScan') ?? true;

  /// 连接指定 MAC 的设备（结果通过 [events] 的 connected 事件返回）。
  Future<bool> connect(String address, {PrinterKind? kind}) async =>
      await _invoke<bool>('connect', {
        'address': address,
        'kind': (kind ?? PrinterKind.supvan).code,
      }) ??
      false;

  /// 断开连接。
  Future<bool> disconnect() async => await _invoke<bool>('disconnect') ?? false;

  /// 查询打印机状态（通用机型恒返回 [PrinterStatus.unknown]）。
  Future<PrinterStatus> status() async {
    final code = await _invoke<int>('status') ?? -1;
    return PrinterStatus.fromCode(code);
  }

  /// 打印一张真实标签：直接把生成的 PDF 交给打印机。
  Future<bool> printLabel({
    required Uint8List pdf,
    required PrinterKind kind,
    PrintOptions options = const PrintOptions(),
  }) async {
    lastOptions = options;
    return await _invoke<bool>('printLabel', {
          'pdf': pdf,
          'kind': kind.code,
          ...options.toMap(),
        }) ??
        false;
  }

  /// 打印内置标尺测试页（不含 PDF，原生自己画）。
  Future<bool> printTest({
    required PrinterKind kind,
    PrintOptions options = const PrintOptions(),
  }) async {
    lastOptions = options;
    return await _invoke<bool>('printTest', {
          'kind': kind.code,
          'width': options.widthMm,
          'height': options.heightMm,
          ...options.toMap(),
        }) ??
        false;
  }

  /// 已添加的打印机列表（最近连接的排最前，重启 App 仍在）。
  Future<List<SavedPrinter>> listSavedPrinters() async {
    final raw =
        await _invoke<List<Object?>>('listSavedPrinters') ?? const <Object?>[];
    return raw.map(SavedPrinter.tryParse).whereType<SavedPrinter>().toList();
  }

  /// 手动按 MAC 添加一台打印机（扫描扫不到的机型用这个）。
  /// 返回 false 表示 MAC 格式不对。
  Future<bool> savePrinter({
    required String name,
    required String address,
    required PrinterKind kind,
  }) async =>
      await _invoke<bool>('savePrinter', {
        'name': name,
        'address': address,
        'kind': kind.code,
      }) ??
      false;

  /// 给已添加的打印机改个名字。
  Future<bool> renamePrinter(String address, String name) async =>
      await _invoke<bool>('renamePrinter', {
        'address': address,
        'name': name,
      }) ??
      false;

  /// 从列表里移除一台已添加的打印机。
  Future<bool> removePrinter(String address) async =>
      await _invoke<bool>('removePrinter', {'address': address}) ?? false;
}
