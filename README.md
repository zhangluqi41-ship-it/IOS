# 效期管理系统 · iOS 版

热敏标签机打效期标签的 App。**纯 iOS 原生（SwiftUI）**，50 × 30 mm 标签，
蓝牙连接硕方 T50 Pro 打印机。

- **版本**：1.0.0（build 26）— 2026-10-08 由优化清单定稿，正式投入使用
- **仓库**：`https://github.com/zhangluqi41-ship-it/IOS.git`（`main`）
- **部署目标**：iOS 26.0（跟着 Xcode 26 SDK 走，直接拿系统 Liquid Glass 材质）
- **设备**：iPhone 17 Pro / iOS 27.0.1 / UDID `00008150-0002283A3EF0401C`

> 安卓 / Flutter 版已于 2026-10-08 停止使用并从本仓库移除。

---

## 一、目录结构

```
expiry_manager/
├── .github/workflows/ios-swiftui.yml   # 云端构建：单测 + 出无签名 IPA
├── swiftui/                            # ★ 工程本体，所有代码都在这里
│   ├── project.yml                     # XcodeGen 工程描述（.xcodeproj 是生成物，不进仓库）
│   ├── Vendor/SFPrintSDK.xcframework   # 硕方官方蓝牙 SDK（静态 framework，14 MB）
│   ├── Resources/NotoSansSC-*.ttf      # 标签用的中文字体（版式是按它量的）
│   ├── Tools/                          # 本机自测脚本（见第四节）
│   ├── Tests/ExpiryAppTests/           # 单元测试
│   └── Sources/ExpiryApp/
│       ├── ExpiryApp.swift             # @main
│       ├── RootView.swift              # 四个一级页签 + 切页回一级的导航
│       ├── Theme.swift / LiquidGlass.swift
│       ├── Models/                     # LabelData(版式) / LabelRecord(记录) / LabelTemplate(业务规则)
│       ├── Services/                   # 存储、通知、字体、二维码、打印、渲染、PDF
│       ├── Views/                      # 模板页 / 扫码 / 效期管理 / 打印机 / 键盘交互
│       └── Native/                     # 硕方 SDK 的 ObjC 封装 + 桥接头 + 打印日志
└── README.md
```

## 二、换一台电脑怎么继续开发

### 1. 必备

| 需要什么 | 说明 |
|---|---|
| Windows / macOS / Linux | **只有 Windows 也能开发**（本工程就是这么做的） |
| XcodeGen | `brew install xcodegen`（macOS）。Windows 上不需要 —— 工程描述 `project.yml` 只在云端 CI 里展开 |
| Git | 本机没有系统 Git 的话，用 WorkBuddy 自带的便携版即可 |
| Python 3 + `Pillow` `opencv-python` `numpy` `qrcode` | 只用于 `Tools/` 下的本机自测脚本 |

### 2. 拿到代码

```bash
git clone https://github.com/zhangluqi41-ship-it/IOS.git
cd IOS
```

### 3. 日常改代码 → 出包 → 装机

```
改 swiftui/ 下的源码
      ↓
git push（推 main 分支）
      ↓
GitHub Actions 自动跑：
  job "Unit tests"         → 在 macos-26 模拟器上跑单测
  job "Build unsigned IPA" → xcodegen generate → xcodebuild → 产出
                             ExpiryManager-unsigned-ipa（保留 14 天）
      ↓
用 ip_tool.py / iLoader 把 IPA 装到手机
```

> ⚠️ **没有 Mac 也能跑**：`macos-26` runner 自带 Xcode 26 + iOS 26 SDK，公开仓库免费用。
> 本机跑不了 Xcode / 模拟器 / SwiftUI 实时预览，所以**版式和观感先在 `Tools/` 里出图看**。

### 4. 装机与续签

| 方式 | 工具 | 适用 |
|---|---|---|
| 首选 | **SideStore**（手机上自助刷新） | 每 7 天在手机上点一次 Refresh All |
| 保底 | **iLoader** + USB 线 | SideStore 出问题时插线重装同一个 IPA |

签名时会**改写 bundle id**：工程里写 `com.xiaoqi.expiry_manager`，
装到手机上实际是 `com.xiaoqi.expiry-manager.<TeamID>`。
⭐ **两个 id 必须对得上**，否则会装成第二个 App —— 看起来就是「数据全没了」。

## 三、几条不能碰的铁律

> 完整清单（含全部踩坑证据）见项目记忆；这里只列最容易踩的。

1. **`bundle id` 不能乱改。** 换 Apple ID = 换 Team ID = 尾串变 = 沙盒新建 = 用户以为数据全丢。
2. **标签版式常量（`LabelSpec`）改之前先算余量。** 打印硬上限 `kDotsPerMM = 8`（203 dpi）；
   「内容越短二维码越清晰」是唯一杠杆。用 `Tools/render_label_preview.py` 出图确认再改 Swift。
3. **二维码内容 = 名称 + 后两组时间**（第一组时间与制作人都不进码）。
   改 `LabelData.qrText` **必须**同步改 `LabelTemplate.parseKombuchaQr`。
4. **康普茶二发完成时间 = 二发制备 + 3 天**（不是「一发完成 + 3 天」，那样会显示成 +10 天）。
5. **连接打印机失败时不要「刚发起连接就 stopScan」** —— 会把在途连接掐死，症状是「完全无法连接」。
6. **`ScrollView` 里 `aspectRatio(.fit)` 会失效**，必须先用 `GeometryReader` 量出可用区域。
7. **预览功能已下线**：`PreviewView` / `PreviewPayload` / `PDFRasterizer` 源码保留但没入口，**别当死代码删**。

## 四、本机自测脚本（`swiftui/Tools/`）

不需要 Mac，改完版式先在这里看效果：

```bash
cd swiftui/Tools
python render_label_preview.py       # 出标签效果图 → Tools/label_preview/
python qr_preview.py                 # 出二维码密度对比图
python verify_qr_local.py            # 二维码端到端校验（渲染 → 解码 → 比对原文）
python theme_preview.py              # 主题配色对比图
python analyze_printer_log.py <日志>  # 解析真机 printer_log.txt
```

> 这些脚本里的路径都是**相对脚本自身**的，工程拷到哪台机器都能直接跑。

## 五、已知边界

- **UI / 蓝牙 / 扫码 / 观感只能在真机验收** —— 单测 + 云端编译覆盖不到这些。
- 硕方 **T50 Pro 的功能已冻结**（连接判定逻辑不再改动），要支持别的机型请另开通道。
- 免费 Apple 账号限制：同时 3 个 App（含 SideStore 自身）、每 7 天 10 个 App ID、
  iOS Development 证书最多 2 张。
