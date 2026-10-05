import 'dart:async';

import 'package:flutter/material.dart';

import 'prefs.dart';
import 'print_options.dart';
import 'printer.dart';

/// 二级页：添加 / 管理一台打印机。
///
/// 从「添加打印机」进来 → 先选型号，再扫描连接；
/// 从已添加的打印机卡片进来 → 带 [target]，进页面自动尝试连接它。
///
/// 连接成功时**原生侧会自动把这台设备加入打印机列表**，返回一级页即可看到。
class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key, this.target});

  /// 要自动连接的目标（从已添加列表点进来时非空）。
  final SavedPrinter? target;

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  final _svc = PrinterService.instance;

  StreamSubscription<PrinterEvent>? _sub;
  Timer? _scanTicker;
  Timer? _busyTimer;

  bool _supported = true;
  bool _enabled = false;
  bool _hasPerm = false;
  bool _scanning = false;
  bool _busy = false;
  bool _loading = true;

  List<BtDevice> _devices = const [];
  BtDevice? _pending; // 正在连接的设备
  BtDevice? _connected;

  PrinterStatus _status = PrinterStatus.unknown;

  /// 已尝试过自动连接目标（避免每帧重试）。
  bool _autoTried = false;

  /// 当前选择的型号。带 target 进来时锁定为那台机器的型号。
  late PrinterKind _kind = widget.target?.kind ?? AppPrefs.lastKind;

  PrintOptions _options = AppPrefs.printOptions;

  @override
  void initState() {
    super.initState();
    _sub = _svc.events.listen(_onEvent);
    _bootstrap();
  }

  /// 先刷环境与设备列表，再（若指定了目标）自动发起一次连接。
  Future<void> _bootstrap() async {
    await _refresh();
    final t = widget.target;
    if (t == null || _autoTried) return;
    _autoTried = true;
    if (!mounted) return;
    await _connect(BtDevice(name: t.name, address: t.address, bonded: true));
  }

  @override
  void dispose() {
    _scanTicker?.cancel();
    _busyTimer?.cancel();
    _sub?.cancel();
    _svc.stopScan();
    super.dispose();
  }

  // ---------------------------------------------------------------- 数据刷新

  Future<void> _refresh() async {
    final supported = await _svc.isSupported();
    final enabled = supported && await _svc.isEnabled();
    final perm = supported && await _svc.hasPermission();
    final devices = supported && enabled && perm
        ? await _svc.listDevices()
        : <BtDevice>[];
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = enabled;
      _hasPerm = perm;
      _devices = devices;
      _loading = false;
      if (_connected != null &&
          !devices.any((d) => d.address == _connected!.address)) {
        // 设备掉线了就清掉连接态
        _connected = null;
        _status = PrinterStatus.unknown;
      }
    });
  }

  Future<void> _ensurePermission() async {
    if (!_hasPerm) {
      final ok = await _svc.requestPermission();
      if (!mounted) return;
      setState(() => _hasPerm = ok);
      if (!ok) _toast('需要蓝牙权限才能连接打印机');
    }
    await _refresh();
  }

  Future<void> _startScan() async {
    await _ensurePermission();
    if (!mounted || !_hasPerm) return;
    final ok = await _svc.startScan();
    if (!mounted) return;
    setState(() => _scanning = ok);
    if (!ok) {
      _toast('无法开始扫描，请确认蓝牙已打开');
      return;
    }
    // 兜底轮询：部分机型不派发 FOUND 广播
    _scanTicker?.cancel();
    _scanTicker = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      final list = await _svc.listDevices();
      if (!mounted) return;
      setState(() => _devices = list);
    });
    // 扫描最长 30 秒自动收尾
    Timer(const Duration(seconds: 30), () {
      if (mounted && _scanning) _stopScan();
    });
  }

  Future<void> _stopScan() async {
    _scanTicker?.cancel();
    _scanTicker = null;
    await _svc.stopScan();
    if (!mounted) return;
    setState(() => _scanning = false);
  }

  // ------------------------------------------------------------------ 交互

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _connect(BtDevice device) async {
    if (_busy) return;
    await _ensurePermission();
    if (!mounted || !_hasPerm) return;

    setState(() {
      _busy = true;
      _pending = device;
    });
    final ok = await _svc.connect(device.address, kind: _kind);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _pending = null;
      });
      _toast(
        widget.target != null
            ? '连接失败，请确认打印机已开机并在范围内'
            : '连接请求未能发出，请确认打印机已开机并已配对',
      );
      return;
    }
    // 结果由 connected 事件回来；超时兜底
    _armBusyTimeout(const Duration(seconds: 16), '连接超时，请确认打印机在范围内');
  }

  /// 手动按 MAC 添加：有些机型不做可发现广播，扫描扫不到。
  Future<void> _addManual() async {
    final r = await showDialog<_ManualAddResult>(
      context: context,
      builder: (_) => _ManualAddDialog(kindLabel: _kind.label),
    );
    if (r == null || !mounted) return;
    final saved = await _svc.savePrinter(
      name: r.name,
      address: r.address,
      kind: _kind,
    );
    if (!mounted) return;
    if (saved) {
      _toast('已添加，返回上一页即可看到');
      await _refresh();
    } else {
      _toast('添加失败，请检查 MAC 地址');
    }
  }

  Future<void> _disconnect() async {
    await _svc.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = null;
      _status = PrinterStatus.unknown;
      _pending = null;
    });
  }

  Future<void> _queryStatus() async {
    final s = await _svc.status();
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _printTest() async {
    if (_connected == null || _busy) return;
    setState(() => _busy = true);
    await AppPrefs.setPrintOptions(_options);
    final ok = await _svc.printTest(kind: _kind, options: _options);
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      _toast('打印指令下发失败，请重新连接打印机');
      return;
    }
    _toast('已下发打印指令');
    _armBusyTimeout(const Duration(seconds: 12), null);
  }

  /// 到点还没收到回调就自己复位，避免界面一直转圈。
  void _armBusyTimeout(Duration d, String? message) {
    _busyTimer?.cancel();
    _busyTimer = Timer(d, () {
      if (!mounted) return;
      if (_busy) setState(() => _busy = false);
      if (message != null) _toast(message);
    });
  }

  /// 按 MAC 找设备：先查当前列表，再回落到来时带的目标。
  BtDevice? _deviceByAddress(String? address) {
    if (address == null || address.isEmpty) return null;
    for (final d in _devices) {
      if (d.address == address) return d;
    }
    final t = widget.target;
    if (t != null && t.address == address) {
      return BtDevice(name: t.name, address: address, bonded: true);
    }
    return null;
  }

  void _onEvent(PrinterEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'connected':
        final ok = e.ok == true;
        _busyTimer?.cancel();
        if (ok) {
          final dev = _deviceByAddress(e.address) ?? _pending;
          setState(() {
            _busy = false;
            _connected = dev;
            _pending = null;
            _kind = e.kind;
          });
          _toast('已连接 ${dev?.name ?? e.name ?? '打印机'}');
          if (_kind.supportsStatus) _queryStatus();
        } else {
          setState(() {
            _busy = false;
            _pending = null;
          });
          _toast('连接失败，请确认打印机已开机');
        }
      case 'disconnected':
        setState(() {
          _connected = null;
          _pending = null;
          _status = PrinterStatus.unknown;
        });
        _toast('已断开连接');
      case 'status':
        if (e.value is int) {
          setState(() => _status = PrinterStatus.fromCode(e.value as int));
        }
      case 'printDone':
        _busyTimer?.cancel();
        setState(() => _busy = false);
        _toast(e.ok == true ? '打印完成' : '打印失败，请检查打印机状态');
      case 'deviceFound':
        final dev = BtDevice.tryParse(e.value);
        if (dev != null && !_devices.any((d) => d.address == dev.address)) {
          setState(() => _devices = [..._devices, dev]);
        }
      case 'scanFinished':
        _stopScan();
    }
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.target?.name ?? '添加打印机'),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _kindCard(),
                  const SizedBox(height: 12),
                  _envCard(),
                  const SizedBox(height: 12),
                  if (!_supported || !_enabled)
                    _hintCard()
                  else ...[
                    if (_connected != null) ...[
                      _connectedCard(),
                      const SizedBox(height: 12),
                    ],
                    _deviceSection(),
                    if (_connected != null) ...[
                      const SizedBox(height: 12),
                      _printCard(),
                    ],
                  ],
                  const SizedBox(height: 16),
                  _aboutCard(),
                ],
              ),
            ),
    );
  }

  /// 打印机型号（= 通信协议）选择。决定走官方 SDK 还是通用蓝牙指令。
  ///
  /// v1.4.1 起改为**下拉菜单**，选完在下方显示该型号的一句话说明。
  Widget _kindCard() {
    final theme = Theme.of(context);
    final locked = widget.target != null;
    final enabled = !locked && !_busy && _connected == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('打印机型号', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                if (locked)
                  Chip(
                    label: const Text('已锁定'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              locked
                  ? '这台设备添加时选的就是该型号，删除后可重新以其他型号添加。'
                  : '型号决定了用哪套通信协议，请按打印机实际品牌选择。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PrinterKind>(
              initialValue: _kind,
              isExpanded: true,
              icon: const Icon(Icons.expand_more),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: '型号',
                prefixIcon: const Icon(Icons.precision_manufacturing_outlined),
                border: const OutlineInputBorder(),
                enabled: enabled,
              ),
              items: [
                for (final k in PrinterKind.values)
                  DropdownMenuItem<PrinterKind>(
                    value: k,
                    child: Text(k.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: enabled ? _onKindChanged : null,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _kind.hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (_kind.isGeneric) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '通用机型走标准蓝牙串口，建议先在系统蓝牙设置里把打印机配对好，'
                  '再回来点「连接」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 切换型号：同步该型号的默认打印参数，并记住选择供下次使用。
  void _onKindChanged(PrinterKind? k) {
    if (k == null || k == _kind) return;
    setState(() {
      _kind = k;
      _options = _options.copyWith(
        headDots: k.defaultHeadDots,
        density: k == PrinterKind.tspl ? 8 : 4,
      );
    });
    AppPrefs.setLastKind(k);
  }

  Widget _envCard() {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, bool ok, String detail) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: ok ? Colors.green : theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            SizedBox(width: 72, child: Text(label)),
            Expanded(
              child: Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('环境检查', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            row(
              Icons.bluetooth,
              '蓝牙',
              _supported,
              _supported ? '设备支持蓝牙' : '本机没有蓝牙硬件',
            ),
            row(
              Icons.toggle_on_outlined,
              '开关',
              _enabled,
              _enabled ? '已打开' : '未打开，点下面的按钮去系统设置开启',
            ),
            row(
              Icons.key_outlined,
              '权限',
              _hasPerm,
              _hasPerm ? '已授予' : '未授予（点下面的按钮申请）',
            ),
            if (_supported && !_enabled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _svc.openBluetoothSettings(),
                  icon: const Icon(Icons.settings_bluetooth),
                  label: const Text('打开系统蓝牙设置'),
                ),
              ),
            if (_supported && _enabled && !_hasPerm)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _ensurePermission,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('申请蓝牙权限'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hintCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _supported ? '请先打开手机的蓝牙开关，再回到本页点击右上角刷新。' : '本机没有蓝牙硬件，无法连接打印机。',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceSection() {
    final theme = Theme.of(context);
    final bonded = _devices.where((d) => d.bonded).toList();
    final found = _devices.where((d) => !d.bonded).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('选择打印机', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _scanning ? _stopScan : _startScan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching, size: 18),
                  label: Text(_scanning ? '停止扫描' : '扫描附近设备'),
                ),
              ],
            ),
            if (bonded.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '已配对（建议先用这些）',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              ...bonded.map(_deviceTile),
            ],
            if (found.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '附近发现',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              ...found.map(_deviceTile),
            ],
            if (_devices.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '还没有设备。先在系统蓝牙设置里把打印机配对好，'
                '或点右上角「扫描附近设备」。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : _addManual,
                icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                label: const Text('手动输入 MAC 添加'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(BtDevice d) {
    final isPending = _pending?.address == d.address && _busy;
    final isCurrent = _connected?.address == d.address;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isCurrent ? Icons.print : Icons.bluetooth,
        color: isCurrent ? Colors.green : null,
      ),
      title: Text(d.name),
      subtitle: Text(d.address),
      trailing: isPending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(isCurrent ? '已连接' : '连接'),
      onTap: _busy ? null : () => _connect(d),
    );
  }

  Widget _connectedCard() {
    final theme = Theme.of(context);
    final ready = _status == PrinterStatus.ready;
    final known = _kind.supportsStatus;
    return Card(
      color: ready
          ? Colors.green.withValues(alpha: 0.10)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              !known
                  ? Icons.print
                  : (ready ? Icons.check_circle : Icons.warning_amber_rounded),
              color: !known
                  ? theme.colorScheme.primary
                  : (ready ? Colors.green : Colors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _connected!.name,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    known
                        ? '${_status.label} · ${_status.hint}'
                        : '${_kind.label} · 该型号不支持查询状态，直接打印即可',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (known)
              IconButton(
                tooltip: '查询状态',
                icon: const Icon(Icons.sync),
                onPressed: _queryStatus,
              ),
            IconButton(
              tooltip: '断开',
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
            ),
          ],
        ),
      ),
    );
  }

  Widget _printCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('打印测试页', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '打一张 50×30mm 的标尺图：外框贴边 + 四角角标 + 时间戳，'
              '用来确认走纸定位和边距。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            PrintOptionsEditor(
              kind: _kind,
              options: _options,
              onChanged: (o) => setState(() => _options = o),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _printTest,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print),
                label: const Text('打印测试页'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutCard() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, size: 18),
                const SizedBox(width: 8),
                Text('为什么有的型号要单独选', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '硕方 T50 Pro 走的是经典蓝牙 SPP + 私有协议（耗材带 RFID 校验），'
              '手机自带蓝牙或第三方打印 App 都连不上，只能通过官方 SDK 通信，'
              '所以 App 里内置了官方 SDK。\n'
              '其他品牌多数是标准蓝牙串口 + TSPL 或 ESC/POS 指令，'
              '走「通用」通道直接发指令即可，不需要 SDK。\n'
              '两者识别方式不同，因此添加时必须先选对型号。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 手动添加的结果。
class _ManualAddResult {
  const _ManualAddResult(this.name, this.address);

  final String name;
  final String address;
}

/// 手动输入 MAC 添加打印机。
///
/// 输入框控制器由弹窗自己持有并在自己的 [State.dispose] 里释放 ——
/// 放在调用方释放会在关闭动画期间被 [TextField] 用到，直接红屏。
class _ManualAddDialog extends StatefulWidget {
  const _ManualAddDialog({required this.kindLabel});

  final String kindLabel;

  @override
  State<_ManualAddDialog> createState() => _ManualAddDialogState();
}

class _ManualAddDialogState extends State<_ManualAddDialog> {
  final _nameCtrl = TextEditingController();
  final _macCtrl = TextEditingController();
  bool _badMac = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _macCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final hex = _macCtrl.text.replaceAll(RegExp('[^0-9A-Fa-f]'), '');
    if (hex.length != 12) {
      setState(() => _badMac = true);
      return;
    }
    Navigator.of(context).pop(_ManualAddResult(_nameCtrl.text, _macCtrl.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('手动添加打印机'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('型号：${widget.kindLabel}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称（可留空）',
              hintText: '例：车间标签机',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _macCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'MAC 地址',
              hintText: 'AA:BB:CC:DD:EE:FF',
              helperText: '在系统蓝牙设置里能看到',
              errorText: _badMac ? '格式不对，应为 12 位十六进制' : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
