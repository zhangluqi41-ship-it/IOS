#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
analyze_printer_log.py —— 把真机 printer_log.txt 读成一份「人话结论」。

背景：v1.6.12 起，日志里新增了两处决定性证据：
  1. 调 connectedBlueteeth: 之前 / 返回后 各一次的 peripheral.state
     （CoreBluetooth 语义：一调 connectPeripheral: 就立刻变 connecting）
  2. 连接期间每秒一次的探针：target.state / SDK 内部 cbCM.state /
     connectPeripheral.state / getDeviceStatus

判读规则（就这两条，别绕）：
  · 返回后 state = connecting / connected
      → 硕方 SDK **确实**把外设交给了 CoreBluetooth，
        卡住就是链路层的事（射频、距离、打印机正被别的中心占用）→ 偏「环境」。
  · 返回后 state = disconnected
      → SDK 内部提前 return 了，压根没发起连接 → 偏「代码 / SDK 用法」。

用法:
  python analyze_printer_log.py [日志路径]
"""

import collections
import os
import re
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "printer_log.txt")


def split_sessions(lines):
    """按 beginConnect 把日志切成若干次「用户发起的一轮连接」。"""
    sessions = []
    cur = None
    for ln in lines:
        if "beginConnect" in ln:
            if cur:
                sessions.append(cur)
            cur = [ln]
        elif cur is not None:
            cur.append(ln)
    if cur:
        sessions.append(cur)
    return sessions


def grab(pattern, text, group=1):
    m = re.search(pattern, text)
    return m.group(group) if m else None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.exists(path):
        raise SystemExit("[!] 找不到日志：%s" % path)

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]

    print("=" * 78)
    print("日志文件：%s   共 %d 行" % (path, len(lines)))
    print("=" * 78)

    sessions = split_sessions(lines)
    if not sessions:
        print("[!] 没有找到 beginConnect —— 用户可能根本没点过连接")
        return

    verdicts = []
    success_any = False

    for idx, sess in enumerate(sessions, 1):
        text = "\n".join(sess)
        head = sess[0]
        start_ts = head.split()[0]

        name = grab(r"name=(\S+)", head) or "?"
        uuid = grab(r"uuid=(\S+)", head) or "?"
        attempt = grab(r"第(\d+)次", head) or "1"
        from_saved = grab(r"fromSaved=(\w+)", head) or "?"

        before = grab(r"调 connectedBlueteeth: 之前 state=(\w+)", text)
        after = grab(r"connectedBlueteeth: 返回后 state=(\w+)", text)
        probes = re.findall(r"target=\S+ state=(\w+)", text)
        probe_seq = []
        for s in probes:
            if not probe_seq or probe_seq[-1] != s:
                probe_seq.append(s)
        sdk_status = re.findall(r"getDeviceStatus=(\d)", text)
        success = ("markConnected" in text)
        success_any = success_any or success
        # v1.6.14 起原生层自己判定：0.5 秒轮询看到「本机外设已连 + SDK 认账」就放行。
        # 这一行出现 = 新判定生效；没出现但探针已看到 connected = 轮询定时器没跑起来
        # （runloop/线程问题），是另一类 bug，要分开看。
        poll_ok = "轮询判定连接成功" in text
        # ★ 先确认这份日志到底是不是「带轮询的那个版本」产出的。
        #   判据用 v1.6.14 新加的自证日志（`connectedBlueteeth:` 返回后那句补了
        #   「此后每 0.5 秒轮询判定」）。没有它就别下「轮询没跑」的结论 ——
        #   旧版本日志根本没有轮询代码，否则会对旧日志误报（已踩过）。
        has_poll_code = "此后每 0.5 秒轮询判定" in text
        fail_line = grab(r"连接最终失败.*", text)
        late = "忽略一次迟到的 connectFail" in text

        print()
        print("-" * 78)
        print("第 %d 轮  %s   （第 %s 次尝试，fromSaved=%s）" % (idx, start_ts, attempt, from_saved))
        print("  目标        : %s  [%s]" % (name, uuid))
        print("  调 SDK 前   : peripheral.state = %s" % (before or "（无记录）"))
        print("  调 SDK 后   : peripheral.state = %s" % (after or "（无记录）"))
        if probe_seq:
            print("  探针轨迹    : %s" % " → ".join(probe_seq))
        if sdk_status:
            uniq = []
            for v in sdk_status:
                if not uniq or uniq[-1] != v:
                    uniq.append(v)
            print("  getDeviceStatus 轨迹: %s" % " → ".join(uniq))
        print("  结果        : %s" % ("✅ 连上了" if success else (fail_line or "（无结论行）")))
        if poll_ok:
            print("  判定方式    : ✅ 0.5 秒轮询判定生效（SDK 的 connectSuccessBlock 没回调也能连上）")

        if after:
            if after in ("connecting", "connected"):
                verdicts.append("link")
            elif after == "disconnected":
                verdicts.append("nosend")
            if after in ("connecting", "connected") and probe_seq:
                if set(probe_seq) == {"connecting"}:
                    verdicts.append("stuck-connecting")
                if "connected" in probe_seq:
                    verdicts.append("reached-connected")
        if poll_ok:
            verdicts.append("poll")
        elif has_poll_code and "connected" in probe_seq and not success:
            verdicts.append("no-poll")
        elif not has_poll_code:
            verdicts.append("old-build")
        if late:
            print("  ⚠️ 出现过迟到的 connectFail（已被忽略，没抹掉连接）")

    print()
    print("=" * 78)
    print("结论")
    print("=" * 78)
    if not verdicts:
        print("  日志里没有取证行 —— 这份是旧版本产出的日志。")
        return

    nosend = verdicts.count("nosend")
    link = verdicts.count("link")
    stuck = verdicts.count("stuck-connecting")
    reached = verdicts.count("reached-connected")
    poll = verdicts.count("poll")
    nopoll = verdicts.count("no-poll")
    old = verdicts.count("old-build")

    if poll:
        print("  ✅ 新判定已生效：0.5 秒轮询拿到了连接结果，不再依赖")
        print("     SDK 的 `connectSuccessBlock`（它全程不回调）。")
        print("     本次日志里「轮询判定连接成功」出现 %d 次，连接成功 %s。"
              % (poll, "正常" if success_any else "但 markConnected 没出现 —— 去查回调链"))
    elif nopoll:
        print("  ★★ 探针已经看到 peripheral.state = connected，但 0.5 秒轮询**一次判定")
        print("     都没给出** —— 说明 `connectWatchTimer` 根本没跑起来")
        print("     （典型原因：定时器挂到了不运行的 runloop / 非主线程）。")
        print("     → 方向：给该定时器改挂 `NSRunLoopCommonModes` 并确保主线程创建。")
    elif old:
        print("  ⚠️ 这份日志是 v1.6.13 及更早版本产出的（没有「此后每 0.5 秒轮询判定」")
        print("     这句自证日志），所以**不能**用「轮询有没有跑」来判读 —— 那时还没这功能。")
        print("     它只能证明一件事：链路每次都真的连上了（探针 connected +")
        print("     getDeviceStatus=1），但 connectSuccessBlock 一次都没回调。")
        print("     → 这正是 v1.6.14 要修的那个现象，请用新版重测后再拉日志。")
    elif reached and not success_any:
        print("  ★★★ 链路**每次都真的连上了**（探针看到 peripheral.state = connected、")
        print("      getDeviceStatus = 1），但全程收不到 `connectSuccessBlock` ——")
        print("      也就是「打印机显示已连接、App 一直转圈」那个现象。")
        print("      → 这是**硕方 SDK 不回回调**，不是射频/环境问题。")
        print("      → v1.6.14 起已改为「按本机外设 state 判定」")
        print("        （ExpiryPrinterSDK.pollConnectState，0.5 秒一次）。")
    elif nosend and not link:
        print("  ★ 所有尝试里，`connectedBlueteeth:` 返回后 peripheral.state 都还是")
        print("    **disconnected** —— 说明硕方 SDK 内部提前 return 了，")
        print("    **根本没有把外设交给 CoreBluetooth**。")
        print("    → 方向：SDK 用法 / 初始化时序，不是射频环境。")
    elif link and nosend:
        print("  ★ 两种都有：有时 SDK 交出去了，有时没有。")
        print("    → 偏向时序/竞态（比如扫描与连接的先后顺序）。")
    else:
        print("  ★ `connectedBlueteeth:` 返回后 peripheral.state 已经是 connecting")
        print("    —— 硕方 SDK **确实发起过 BLE 连接**，是链路层没握上。")
        if stuck:
            print("    探针显示状态**一直卡在 connecting**，从没变成 connected，")
            print("    也从没退回 disconnected —— 典型的「对方不理你」：")
            print("      · 打印机正在被别的中心占用（硕方官方 App 还开着？另一台手机？）")
            print("      · 距离/干扰（USB 3 数据线与蓝牙同在 2.4GHz，插着线时更明显）")
        print("    → 方向：先把环境排干净再试，别改代码。")


if __name__ == "__main__":
    main()
