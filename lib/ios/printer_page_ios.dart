/// iOS 打印机页 —— `printer_page.dart` 的 Cupertino 对位实现，
/// 同时**修复需求第 5 条**。
///
/// ## 需求 5 的三个原始症状与修法
///
/// 症状：*「添加打印机界面能否不要一直旋转，至少要有目前搜索到的蓝牙设备的列表」*
///
/// 原安卓版根因（三个叠加）：
///  1. **扫描态与连接态共用一个 `_busy`** —— 连接被 arm 了 16 秒超时，
///     这 16 秒里整页都在转圈，看起来「一直在旋转」。
///  2. **30 秒自动收尾用的是一次性 `Timer`**，中途任何一次 `setState`
///     把它覆盖掉就再也不会触发，扫描态永久卡在 true。
///  3. **兜底轮询每 2 秒调一次 `listDevices`**，而原生侧每次 `listDevices`
///     都会**重新起一轮 2.5 秒扫描**（`SFPrinterBridge.m` 注释已写明），
///     新旧扫描互相掐断 → 列表反复清空、设备扫不全。
///
/// iOS 版修法：
///  * **`_scanning`（扫描中）与 `_connecting`（连接中）彻底分离**，
///    各自有独立的 spinner，页面不再整体转圈；
///  * 扫描用**单一 `Timer.periodic(1s)` 心跳**做倒计时 + 从 `_found` 抓快照，
///    到点（25 秒）自动收尾，**幂等**，不会漏触发；
///  * **不再轮询 `listDevices`** —— 直接消费原生 `deviceFound` 事件流累加，
///    避免反复重启扫描；
///  * 已配对设备与附近发现设备**分段展示**（`CupertinoSegmentedControl`），
///    用户随时能看到已搜到的列表，而不是一个空转的圈。
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../prefs.dart';
import '../printer.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';

class IosPrinterPage extends StatefulWidget {
  const IosPrinterPage({super.key, this.target});

  /// 从「已添加」卡片进来时带目标设备；为空表示新增。
  final SavedPrinter? target;

  @override
  State<IosPrinterPage> createState() => _IosPrinterPageState();
}

class _IosPrinterPageState extends State<IosPrinterPage> {
  final PrinterService _svc = PrinterService.instance;

  StreamSubscription<PrinterEvent>? _sub;

  /// 扫描心跳（唯一的定时器来源）。
  Timer? _scanTicker;

  /// 连接超时。
  Timer? _connectTimer;

  bool _supported = true;
  bool _enabled = false;
  bool _hasPerm = false;

  /// ★ 与连接态分离：只有「正在扫描」才驱动扫描 spinner。
  bool _scanning = false;

  /// ★ 独立的连接中状态。
  bool _connecting = false;

  bool _loading = true;

  /// 扫描剩余秒数（用于给用户可见的倒计时，而不是无限转圈）。
  int _scanLeft = 0;

  /// 已配对设备。
  List<BtDevice> _bonded = const <BtDevice>[];

  /// 附近发现的设备（由 `deviceFound` 事件累加，去重）。
  final List<BtDevice> _found = <BtDevice>[];

  /// 当前分段：0 = 已配对，1 = 附近
  int _segment = 0;

  BtDevice? _connected;
  PrinterStatus _status = PrinterStatus.unknown;

  bool _autoTried = false;

  late PrinterKind _kind = widget.target?.kind ?? AppPrefs.lastKind;
  late PrintOptions _options = AppPrefs.printOptions;

  static const int _scanSeconds = 25;

  @override
  void initState() {
    super.initState();
    _sub = _svc.events.listen(_onEvent);
    _bootstrap();
  }

  @override
  void dispose() {
    _scanTicker?.cancel();
    _connectTimer?.cancel();
    _sub?.cancel();
    _svc.stopScan();
    super.dispose();
  }

  // ---------------------------------------------------------------- 初始化

  Future<void> _bootstrap() async {
    await _refresh(autoStartScan: true);
    final SavedPrinter? t = widget.target;
    if (t != null && !_autoTried) {
      _autoTried = true;
      await _connect(
        BtDevice(name: t.name, address: t.address, bonded: true),
      );
    }
  }

  /// 探测环境 + 拉一次已配对设备。
  ///
  /// ★ 这里**不轮询、不自动开扫描**（除非显式要求），避免反复重启扫描。
  Future<void> _refresh({bool autoStartScan = false}) async {
    final bool supported = await _svc.isSupported();
    final bool enabled = supported && await _svc.isEnabled();
    final bool perm = supported && await _svc.hasPermission();

    List<BtDevice> bonded = const <BtDevice>[];
    if (supported && enabled && perm) {
      // 只调一次，拿到系统的已配对列表即可；
      // 附近设备完全靠 deviceFound 事件流，不再频繁 listDevices。
      bonded = await _svc.listDevices();
    }

    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = enabled;
      _hasPerm = perm;
      _bonded = bonded;
      _loading = false;
      // 有已配对设备时默认展示「已配对」分段
      if (bonded.isNotEmpty) _segment = 0;
    });

    if (widget.target != null &&
        _connected != null &&
        _connected!.address != widget.target!.address) {
      setState(() => _connected = null);
    }

    if (autoStartScan && supported && enabled && perm) {
      await _startScan();
    }
  }

  Future<void> _ensurePermission() async {
    if (_hasPerm) return;
    final bool ok = await _svc.requestPermission();
    if (!mounted) return;
    setState(() => _hasPerm = ok);
  }

  // ------------------------------------------------------------------ 扫描

  /// 开始扫描。
  ///
  /// ★ 修复要点：
  ///  * 只用一个 `Timer.periodic` 做心跳，同时负责倒计时与收尾，**幂等**；
  ///  * 不再每 2 秒 `listDevices`（那会反复重启原生扫描）；
  ///  * 到点自动调用 `_stopScan()`，绝不会留下永久转圈的状态。
  Future<void> _startScan() async {
    if (_scanning) return;
    await _ensurePermission();
    if (!mounted || !_hasPerm) return;

    final bool ok = await _svc.startScan();
    if (!mounted) return;
    if (!ok) {
      await _showToast('无法开始扫描，请确认蓝牙已打开');
      return;
    }

    setState(() {
      _scanning = true;
      _scanLeft = _scanSeconds;
    });

    _scanTicker?.cancel();
    _scanTicker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final int left = _scanLeft - 1;
      if (left <= 0) {
        t.cancel();
        _stopScan();
      } else {
        setState(() => _scanLeft = left);
      }
    });
  }

  /// 停止扫描（幂等，可重复调用）。
  Future<void> _stopScan() async {
    _scanTicker?.cancel();
    _scanTicker = null;
    await _svc.stopScan();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scanLeft = 0;
    });
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await _stopScan();
    } else {
      await _startScan();
    }
  }

  // ------------------------------------------------------------------ 交互

  Future<void> _showToast(String msg) {
    if (!mounted) return Future<void>.value();
    // iOS 用轻量提示，避免打断
    final Brightness b = iosBrightness(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Padding(
          padding: const EdgeInsets.only(top: IosSpace.sm),
          child: Text(
            msg,
            style: TextStyle(
              fontSize: IosText.subheadline,
              color: IosColors.secondaryLabel(b),
            ),
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  /// 连接设备。★ 连接中只让**这一行**转圈，不再整页 `_busy`。
  Future<void> _connect(BtDevice device) async {
    if (_connecting) return;
    await _ensurePermission();
    if (!mounted) return;

    setState(() {
      _connecting = true;
      _connectingAddress = device.address;
    });

    await _svc.connect(device.address, kind: _kind);

    // 连接结果由 connected 事件带回；这里只兜一个超时，
    // 超时仅解除**本行**的转圈，不影响扫描列表展示。
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 16), () {
      if (!mounted) return;
      if (_connecting && _connected?.address != device.address) {
        setState(() {
          _connecting = false;
          _connectingAddress = null;
        });
        _showToast('连接超时，请确认打印机已开机并在范围内');
      }
    });
  }

  /// 正在连接的设备地址（用于行内 spinner）。
  String? _connectingAddress;

  void _onEvent(PrinterEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'connected':
        final bool ok = e.ok ?? false;
        final BtDevice? dev = _deviceByAddress(e.address);
        _connectTimer?.cancel();
        setState(() {
          _connecting = false;
          _connectingAddress = null;
          if (ok) {
            _connected = dev ?? _connected;
            _autoTried = true;
          }
        });
        if (ok) {
          final String name = dev?.name ?? e.name ?? '打印机';
          unawaited(_svc.savePrinter(
            name: name,
            address: e.address ?? dev?.address ?? '',
            kind: _kind,
          ));
          if (_kind.supportsStatus) unawaited(_queryStatus());
        }
      case 'disconnected':
        setState(() {
          _connected = null;
          _status = PrinterStatus.unknown;
        });
      case 'status':
        final Object? v = e.value;
        if (v is num) {
          setState(() => _status = PrinterStatus.fromCode(v.toInt()));
        }
      case 'deviceFound':
        final BtDevice? d = BtDevice.tryParse(e.value);
        if (d == null || d.address.isEmpty) return;
        // 已在附近列表里就跳过（去重）
        if (_found.any((BtDevice x) => x.address == d.address)) return;
        setState(() => _found.add(d));
      case 'scanFinished':
        _stopScan();
      default:
        break;
    }
  }

  BtDevice? _deviceByAddress(String? addr) {
    if (addr == null || addr.isEmpty) return null;
    for (final BtDevice d in _bonded) {
      if (d.address == addr) return d;
    }
    for (final BtDevice d in _found) {
      if (d.address == addr) return d;
    }
    final SavedPrinter? t = widget.target;
    if (t != null && t.address == addr) {
      return BtDevice(name: t.name, address: t.address, bonded: true);
    }
    return null;
  }

  Future<void> _queryStatus() async {
    final PrinterStatus s = await _svc.status();
    if (!mounted) return;
    setState(() => _status = s);
  }

  void _onKindChanged(PrinterKind k) {
    iosHaptic(HapticFeedbackType.selection);
    setState(() {
      _kind = k;
      _options = _options.copyWith(
        headDots: k.defaultHeadDots,
        density: k == PrinterKind.tspl ? 8 : 4,
      );
    });
    AppPrefs.setLastKind(k);
  }

  Future<void> _addManual() async {
    final (String, String)? r = await showCupertinoDialog<(String, String)>(
      context: context,
      builder: (_) => _ManualAddDialog(kindLabel: _kind.label),
    );
    if (r == null) return;
    await _svc.savePrinter(name: r.$1, address: r.$2, kind: _kind);
    await _refresh();
  }

  Future<void> _printTest() async {
    await AppPrefs.setPrintOptions(_options);
    await _svc.printTest(kind: _kind, options: _options);
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final bool locked = widget.target != null;

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.target?.name ?? '添加打印机',
          style: IosText.navTitle,
        ),
        backgroundColor: IosColors.grouped(b).withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          onPressed: _loading ? null : () => _refresh(),
          child: const Icon(CupertinoIcons.refresh, size: 22),
        ),
      ),
      child: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 12))
          : SafeArea(
              child: ListView(
                padding: kIosListPadding,
                children: <Widget>[
                  _kindSection(locked: locked),
                  const SizedBox(height: IosSpace.lg),
                  if (_supported) _envSection(),
                  if (!_supported || !_enabled) ...<Widget>[
                    const SizedBox(height: IosSpace.lg),
                    IosBanner(
                      tone: IosBannerTone.warn,
                      title: '蓝牙未就绪',
                      lines: <String>[
                        if (!_supported) '· 当前设备不支持蓝牙打印通道',
                        if (_supported && !_enabled) '· 请先在系统设置里打开蓝牙',
                        if (_supported && _enabled && !_hasPerm)
                          '· 需要授予蓝牙权限才能扫描设备',
                      ],
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: IosSpace.lg),
                    _deviceSection(b),
                  ],
                  if (_connected != null) ...<Widget>[
                    const SizedBox(height: IosSpace.lg),
                    _connectedSection(b),
                  ],
                  const SizedBox(height: IosSpace.lg),
                  _printSection(b),
                  const SizedBox(height: IosSpace.lg),
                  _aboutSection(b),
                  const SizedBox(height: IosSpace.xl),
                ],
              ),
            ),
    );
  }

  /// 型号选择（对应安卓版 `_kindCard`）。
  Widget _kindSection({required bool locked}) {
    final Brightness b = iosBrightness(context);
    final List<PrinterKind> options =
        kIsIos ? const <PrinterKind>[PrinterKind.supvan] : PrinterKind.values;

    return IosListGroup(
      header: IosSectionHeader(
        title: '打印机型号',
        padding: const EdgeInsets.fromLTRB(
          IosSpace.xs,
          0,
          IosSpace.xs,
          IosSpace.sm,
        ),
      ),
      children: <Widget>[
        IosPickerField<PrinterKind>(
          label: '型号',
          value: _kind,
          items: options,
          itemLabel: (PrinterKind k) => k.label,
          icon: CupertinoIcons.device_phone_portrait,
          enabled: !locked && options.length > 1,
          lockedHint: locked ? '已锁定' : null,
          helper: _kind.hint,
          onChanged: _onKindChanged,
        ),
        if (_kind.isGeneric) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IosSpace.ml,
              0,
              IosSpace.ml,
              IosSpace.ml,
            ),
            child: Text(
              '通用机型走经典蓝牙 SPP 通道，需要先在本机「设置 → 蓝牙」里配对；'
              '如果配对后仍连不上，请确认打印机工作在 ${_kind.label} 模式。',
              style: TextStyle(
                fontSize: IosText.caption1,
                color: IosColors.secondaryLabel(b),
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 环境检查。
  Widget _envSection() {
    final Brightness b = iosBrightness(context);
    return IosListGroup(
      header: IosSectionHeader(
        title: '环境检查',
        padding: const EdgeInsets.fromLTRB(
          IosSpace.xs,
          0,
          IosSpace.xs,
          IosSpace.sm,
        ),
      ),
      children: <Widget>[
        _envRow(b, '蓝牙', _supported, '本机蓝牙能力'),
        _envRow(b, '开关', _enabled, _enabled ? '已打开' : '未打开'),
        _envRow(b, '权限', _hasPerm, _hasPerm ? '已授权' : '未授权'),
        if (!_enabled || !_hasPerm)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IosSpace.ml,
              0,
              IosSpace.ml,
              IosSpace.ml,
            ),
            child: Row(
              children: <Widget>[
                if (!_enabled)
                  IosSecondaryButton(
                    label: '打开系统蓝牙',
                    icon: CupertinoIcons.settings,
                    onPressed: () => _svc.openBluetoothSettings(),
                  ),
                if (!_enabled && !_hasPerm) const SizedBox(width: IosSpace.sm),
                if (!_hasPerm)
                  IosSecondaryButton(
                    label: '申请蓝牙权限',
                    icon: CupertinoIcons.lock_open,
                    onPressed: () async {
                      await _ensurePermission();
                      await _refresh();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _envRow(Brightness b, String label, bool ok, String detail) {
    return IosListRow(
      title: label,
      value: ok ? '正常' : '异常',
      valueColor: ok ? IosColors.green : IosColors.red,
      subtitle: detail,
      leadingIcon: ok
          ? CupertinoIcons.checkmark_circle_fill
          : CupertinoIcons.xmark_circle_fill,
      leadingColor: ok ? IosColors.green : IosColors.red,
      showDivider: true,
    );
  }

  /// ★ 需求 5 的核心：设备列表（分段 + 可见倒计时 + 行内 spinner）。
  Widget _deviceSection(Brightness b) {
    final List<BtDevice> list = _segment == 0 ? _bonded : _found;

    return IosListGroup(
      header: IosSectionHeader(
        title: '选择打印机',
        subtitle: _scanning
            ? '正在扫描，$_scanLeft 秒后自动结束'
            : '可随时点右侧按钮重新扫描',
        trailing: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: IosSpace.sm),
          minimumSize: const Size(0, 30),
          pressedOpacity: 0.5,
          onPressed: _toggleScan,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_scanning) ...<Widget>[
                const CupertinoActivityIndicator(radius: 7),
                const SizedBox(width: IosSpace.s),
              ] else
                const Icon(
                  CupertinoIcons.search,
                  size: 15,
                  color: IosColors.blue,
                ),
              Text(
                _scanning ? '停止' : '扫描',
                style: const TextStyle(
                  fontSize: IosText.subheadline,
                  color: IosColors.blue,
                ),
              ),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          IosSpace.xs,
          0,
          IosSpace.sm,
          IosSpace.sm,
        ),
      ),
      children: <Widget>[
        // 分段控件：已配对 / 附近
        Padding(
          padding: const EdgeInsets.fromLTRB(
            IosSpace.m,
            IosSpace.sm,
            IosSpace.m,
            IosSpace.sm,
          ),
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: _segment,
            children: <int, Widget>{
              0: Padding(
                padding: const EdgeInsets.symmetric(vertical: IosSpace.s),
                child: Text('已配对 (${_bonded.length})'),
              ),
              1: Padding(
                padding: const EdgeInsets.symmetric(vertical: IosSpace.s),
                child: Text('附近 (${_found.length})'),
              ),
            },
            onValueChanged: (int? v) {
              if (v == null) return;
              iosHaptic(HapticFeedbackType.selection);
              setState(() => _segment = v);
            },
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IosSpace.ml,
              vertical: IosSpace.xl,
            ),
            child: Column(
              children: <Widget>[
                Icon(
                  _segment == 0
                      ? CupertinoIcons.link
                      : CupertinoIcons.bluetooth,
                  size: 30,
                  color: IosColors.tertiaryLabel(b),
                ),
                const SizedBox(height: IosSpace.sm),
                Text(
                  _segment == 0
                      ? '还没有已配对设备'
                      : (_scanning ? '正在搜索附近设备…' : '点右上角「扫描」开始搜索'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: IosText.subheadline,
                    color: IosColors.secondaryLabel(b),
                  ),
                ),
                if (_segment == 0) ...<Widget>[
                  const SizedBox(height: IosSpace.s),
                  Text(
                    '请先在系统「设置 → 蓝牙」里配对打印机，\n配对后会出现在这里。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: IosText.caption1,
                      color: IosColors.tertiaryLabel(b),
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          for (int i = 0; i < list.length; i++)
            _deviceRow(b, list[i], isLast: i == list.length - 1),
        if (!kIsIos)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IosSpace.ml,
              0,
              IosSpace.ml,
              IosSpace.ml,
            ),
            child: IosSecondaryButton(
              label: '手动输入 MAC 添加',
              icon: CupertinoIcons.pencil,
              onPressed: _addManual,
            ),
          ),
      ],
    );
  }

  Widget _deviceRow(Brightness b, BtDevice d, {required bool isLast}) {
    final bool isConnected = _connected?.address == d.address;
    final bool isConnecting = _connectingAddress == d.address;

    return IosListRow(
      title: d.name.isEmpty ? '未知设备' : d.name,
      subtitle: d.address,
      leadingIcon: isConnected ? CupertinoIcons.printer_fill : CupertinoIcons.printer,
      leadingColor: isConnected ? IosColors.green : null,
      showDivider: !isLast,
      showChevron: false,
      onTap: (_connecting || isConnected) ? null : () => _connect(d),
      trailing: isConnecting
          ? const CupertinoActivityIndicator(radius: 8)
          : Text(
              isConnected ? '已连接' : '连接',
              style: TextStyle(
                fontSize: IosText.subheadline,
                fontWeight: FontWeight.w600,
                color: isConnected
                    ? IosColors.green
                    : IosColors.blue.withValues(alpha: _connecting ? 0.4 : 1),
              ),
            ),
    );
  }

  /// 已连接卡片。
  Widget _connectedSection(Brightness b) {
    final bool ready = _status == PrinterStatus.ready;
    return IosListGroup(
      header: IosSectionHeader(
        title: '当前连接',
        padding: const EdgeInsets.fromLTRB(
          IosSpace.xs,
          0,
          IosSpace.xs,
          IosSpace.sm,
        ),
      ),
      children: <Widget>[
        IosListRow(
          title: _connected!.name.isEmpty ? '打印机' : _connected!.name,
          subtitle: '${_status.label} · ${_status.hint}',
          leadingIcon: CupertinoIcons.printer_fill,
          leadingColor: ready ? IosColors.green : IosColors.orange,
          showDivider: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_kind.supportsStatus)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IosSpace.xs,
                  ),
                  minimumSize: const Size(30, 30),
                  onPressed: _queryStatus,
                  child: const Icon(
                    CupertinoIcons.arrow_clockwise,
                    size: 18,
                    color: IosColors.blue,
                  ),
                ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: IosSpace.xs),
                minimumSize: const Size(30, 30),
                onPressed: () async {
                  await _svc.disconnect();
                  if (mounted) setState(() => _connected = null);
                },
                child: const Icon(
                  CupertinoIcons.link,
                  size: 18,
                  color: IosColors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 打印测试页。
  Widget _printSection(Brightness b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IosSectionHeader(
          title: '打印测试页',
          subtitle: '先确认纸型与浓度合适，再正式打印',
          padding: const EdgeInsets.fromLTRB(
            IosSpace.xs,
            0,
            IosSpace.xs,
            IosSpace.sm,
          ),
        ),
        IosListGroup(
          padding: const EdgeInsets.all(IosSpace.ml),
          children: <Widget>[
            IosPrintOptionsEditor(
              kind: _kind,
              options: _options,
              onChanged: (PrintOptions o) => setState(() => _options = o),
            ),
          ],
        ),
        const SizedBox(height: IosSpace.m),
        IosSecondaryButton(
          label: '打印测试页',
          icon: CupertinoIcons.printer,
          expand: true,
          onPressed: _connecting ? null : _printTest,
        ),
      ],
    );
  }

  /// 「为什么有的型号要单独选」说明。
  Widget _aboutSection(Brightness b) {
    return IosListGroup(
      header: IosSectionHeader(
        title: '关于型号',
        padding: const EdgeInsets.fromLTRB(
          IosSpace.xs,
          0,
          IosSpace.xs,
          IosSpace.sm,
        ),
      ),
      padding: const EdgeInsets.all(IosSpace.ml),
      children: <Widget>[
        Text(
          '不同打印机说的「语言」不一样。硕方 T50 Pro 用官方 SDK 通道，'
          '能查状态和耗材；国产通用标签机多说 TSPL 指令；热敏票据机多说 ESC/POS。'
          '选错型号会出现「连上了但打不出字」或走纸错位。',
          style: TextStyle(
            fontSize: IosText.footnote,
            color: IosColors.secondaryLabel(b),
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

/// 手动输入 MAC 弹窗（iOS 版）。
///
/// 控制器由弹窗自持自释 —— 放调用方会在关闭动画期间因 TextField 仍引用而红屏。
class _ManualAddDialog extends StatefulWidget {
  const _ManualAddDialog({required this.kindLabel});

  final String kindLabel;

  @override
  State<_ManualAddDialog> createState() => _ManualAddDialogState();
}

class _ManualAddDialogState extends State<_ManualAddDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _macCtrl = TextEditingController();
  bool _badMac = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _macCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameCtrl.text.trim();
    final List<String> parts = _macCtrl.text
        .replaceAll(RegExp('[^0-9A-Fa-f]'), '')
        .split('');
    if (name.isEmpty || parts.length != 12) {
      setState(() => _badMac = true);
      return;
    }
    final String hex = parts.join().toUpperCase();
    final String mac = <String>[
      for (int i = 0; i < 12; i += 2) hex.substring(i, i + 2),
    ].join(':');
    Navigator.of(context).pop((name, mac));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('手动添加打印机'),
      content: Padding(
        padding: const EdgeInsets.only(top: IosSpace.m),
        child: Column(
          children: <Widget>[
            Text(
              '型号：${widget.kindLabel}',
              style: const TextStyle(fontSize: IosText.footnote),
            ),
            const SizedBox(height: IosSpace.m),
            CupertinoTextField(
              controller: _nameCtrl,
              autofocus: true,
              textInputAction: TextInputAction.next,
              placeholder: '设备名称',
            ),
            const SizedBox(height: IosSpace.sm),
            CupertinoTextField(
              controller: _macCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              placeholder: 'AA:BB:CC:DD:EE:FF',
              onChanged: (_) {
                if (_badMac) setState(() => _badMac = false);
              },
            ),
            if (_badMac) ...<Widget>[
              const SizedBox(height: IosSpace.sm),
              const Text(
                '请输入 12 位十六进制 MAC 地址',
                style: TextStyle(
                  fontSize: IosText.caption1,
                  color: IosColors.red,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}

/// iOS 版打印参数编辑器 —— `print_options.dart` 的 Cupertino 对位实现。
///
/// 用 `CupertinoSlidingSegmentedControl` 替代 `ChoiceChip`，
/// 用 `CupertinoSlider` 替代 `Slider`，用 `CupertinoSwitch` 替代 `SwitchListTile`。
class IosPrintOptionsEditor extends StatelessWidget {
  const IosPrintOptionsEditor({
    super.key,
    required this.kind,
    required this.options,
    required this.onChanged,
  });

  final PrinterKind kind;
  final PrintOptions options;
  final ValueChanged<PrintOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final bool showGap = kind != PrinterKind.escpos;
    final bool showDensity = kind != PrinterKind.escpos;
    final bool showSpeed = kind == PrinterKind.tspl;
    final bool generic = kind.isGeneric;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _slider(
          b,
          label: '份数',
          value: '${options.copies}',
          v: options.copies.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          onChanged: (double v) =>
              onChanged(options.copyWith(copies: v.round())),
        ),
        if (showGap)
          _slider(
            b,
            label: '纸张间隙',
            value: '${options.gap} mm',
            v: options.gap.toDouble(),
            min: 0,
            max: 8,
            divisions: 8,
            hint: '走纸定位不准时调它',
            onChanged: (double v) =>
                onChanged(options.copyWith(gap: v.round())),
          ),
        if (showDensity)
          _slider(
            b,
            label: '浓度',
            value: '${options.density}',
            v: options.density.toDouble(),
            min: kind == PrinterKind.tspl ? 0 : 1,
            max: kind == PrinterKind.tspl ? 15 : 9,
            divisions: 14,
            onChanged: (double v) =>
                onChanged(options.copyWith(density: v.round())),
          ),
        if (showSpeed)
          _slider(
            b,
            label: '打印速度',
            value: '${options.speed}',
            v: options.speed.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            hint: '越大越快，字迹越淡',
            onChanged: (double v) =>
                onChanged(options.copyWith(speed: v.round())),
          ),
        if (kind == PrinterKind.supvan) ...<Widget>[
          _label(b, '纸张类型'),
          Padding(
            padding: const EdgeInsets.only(bottom: IosSpace.sm),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: options.paperType.code,
              children: <int, Widget>{
                for (final PaperType t in PaperType.values)
                  t.code: Padding(
                    padding: const EdgeInsets.symmetric(vertical: IosSpace.s),
                    child: Text(t.label),
                  ),
              },
              onValueChanged: (int? v) {
                if (v == null) return;
                final PaperType t = PaperType.values.firstWhere(
                  (PaperType x) => x.code == v,
                  orElse: () => PaperType.gap,
                );
                onChanged(options.copyWith(paperType: t));
              },
            ),
          ),
        ],
        if (generic) ...<Widget>[
          _label(b, '打印头点数'),
          Padding(
            padding: const EdgeInsets.only(bottom: IosSpace.sm),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: options.headDots,
              children: const <int, Widget>{
                384: Padding(
                  padding: EdgeInsets.symmetric(vertical: IosSpace.s),
                  child: Text('384'),
                ),
                400: Padding(
                  padding: EdgeInsets.symmetric(vertical: IosSpace.s),
                  child: Text('400'),
                ),
                576: Padding(
                  padding: EdgeInsets.symmetric(vertical: IosSpace.s),
                  child: Text('576'),
                ),
              },
              onValueChanged: (int? v) {
                if (v == null) return;
                onChanged(options.copyWith(headDots: v));
              },
            ),
          ),
          if (kind == PrinterKind.escpos)
            _slider(
              b,
              label: '走纸行数',
              value: '${options.feedLines}',
              v: options.feedLines.toDouble(),
              min: 0,
              max: 8,
              divisions: 8,
              onChanged: (double v) =>
                  onChanged(options.copyWith(feedLines: v.round())),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IosSpace.s),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '黑白取反',
                        style: TextStyle(
                          fontSize: IosText.body,
                          color: IosColors.label(b),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '打出来整片黑或整片白时打开它',
                        style: TextStyle(
                          fontSize: IosText.caption1,
                          color: IosColors.tertiaryLabel(b),
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: options.invert,
                  onChanged: (bool v) =>
                      onChanged(options.copyWith(invert: v)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _label(Brightness b, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: IosSpace.sm, bottom: IosSpace.s),
      child: Text(
        text,
        style: TextStyle(
          fontSize: IosText.footnote,
          color: IosColors.secondaryLabel(b),
        ),
      ),
    );
  }

  Widget _slider(
    Brightness b, {
    required String label,
    required String value,
    required double v,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: IosSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: IosText.subheadline,
                    color: IosColors.label(b),
                  ),
                ),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: v.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: IosText.subheadline,
                    fontWeight: FontWeight.w600,
                    color: IosColors.label(b),
                  ),
                ),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 76, bottom: IosSpace.xs),
              child: Text(
                hint,
                style: TextStyle(
                  fontSize: IosText.caption1,
                  color: IosColors.tertiaryLabel(b),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
