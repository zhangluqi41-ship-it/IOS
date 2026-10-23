import SwiftUI
import UIKit

// MARK: - 磁贴网格（UICollectionView + DiffableDataSource）
//
// 2026-10-21：整套换成**苹果第一方**：
//   · 网格 / 拖放：`UICollectionView` + `UICollectionViewDragDelegate` + `UICollectionViewDropDelegate`
//     （iOS 主屏 SpringBoard 就是这一套 → 抬起放大、其他磁贴实时让开、半透明占位、
//      弹性归位、拖到边缘自动滚动，全是系统内置动画）；
//   · 数据源：**`UICollectionViewDiffableDataSource`**（WWDC 2019 发布，Apple 现在推荐的接口）——
//     给它一个快照，系统自己算增删移动，并**用系统动画播放**。
//     固定 → 卡片滑到第一位；删除 → 收缩消失；新建 → 插入。

struct TileGrid: UIViewRepresentable {
    let order: [TemplateRoute]
    let pinnedKeys: [String]
    let deletingMode: Bool
    let editingMode: Bool
    let onSelect: (TemplateRoute) -> Void
    let onPin: (TemplateRoute) -> Void
    let onRemove: (TemplateRoute) -> Void
    let onEdit: (TemplateRoute) -> Void
    let onMove: (_ from: Int, _ to: Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = .zero

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.delegate = context.coordinator
        cv.register(TileCell.self, forCellWithReuseIdentifier: TileCell.reuseID)

        // ★★★ 2026-10-21：改用 **`beginInteractiveMovementForItem`**（UICollectionView 自带的
        //   交互式移动，iOS 9 起就有）。和 DragDelegate 的区别：
        //     · DragDelegate = 跨 App 拖放 → **生成预览副本 + 源 cell 立即 hidden** → "两个模块"
        //     · InteractiveMovement = **cell 本身浮起**、原位置留半透明占位、松手自己滑到位
        //   全程系统动画，**一行手写动画代码都不需要**（连 suppress 标志都不用）。
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        cv.addGestureRecognizer(longPress)

        context.coordinator.collectionView = cv
        context.coordinator.makeDataSource()
        context.coordinator.apply(order: order, animated: false)
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(order: order, animated: true)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             UICollectionViewDelegateFlowLayout {
        var parent: TileGrid
        weak var collectionView: UICollectionView?
        private var dataSource: TileDataSource!

        /// ★ 2026-10-22：拖动中最后一帧的手指位置，以及据此算出的**目标格子下标**。
        ///   为什么不用系统给的 `destination`：它到底是"最终位置"还是"被落到的格子"
        ///   在 `beginInteractiveMovement` + `DiffableDataSource` 下前后对不上（实测差 1），
        ///   而 `indexPathForItem(at:)` 的语义是**明确的**（这个点落在哪一格）。
        private var lastDragLocation: CGPoint = .zero
        private var pendingTarget: Int?

        /// 上一次应用的状态（没变就不 apply，避免拖动中反复重建）。
        private var appliedKeys: [String] = []
        private var appliedPinned: [String] = []
        private var appliedDeleting = false
        private var appliedEditing = false
        /// 刚刚发生过拖放落位 —— 下一次 `apply` 改走"无 diff 同步"。
        private var dropJustHappened = false

        init(_ parent: TileGrid) {
            self.parent = parent
        }

        func makeDataSource() {
            guard let cv = collectionView else { return }
            let source = TileDataSource(
                collectionView: cv
            ) { [weak self] cv, indexPath, route in
                guard let self else { return nil }
                let cell = cv.dequeueReusableCell(withReuseIdentifier: TileCell.reuseID,
                                                  for: indexPath) as! TileCell
                cell.configure(route: route,
                               pinned: self.parent.pinnedKeys.contains(route.key),
                               deletingMode: self.parent.deletingMode,
                               editingMode: self.parent.editingMode,
                               onTapAction: { [weak self] in self?.parent.onPin(route) },
                               onRemoveAction: { [weak self] in self?.parent.onRemove(route) },
                               onEditAction: { [weak self] in self?.parent.onEdit(route) })
                return cell
            }
            source.onMove = { [weak self] from, to in
                self?.parent.onMove(from, to)
            }
            source.onDropLanded = { [weak self] in
                self?.dropJustHappened = true
            }
            dataSource = source
        }

        /// ★ 2026-10-22 三次实测后的最终结论：
        ///   · `applySnapshotUsingReloadData`（reloadData）→ 落位**对**，但**打断系统动画**（瞬间落下）；
        ///   · `apply(animatingDifferences: true)` → 有动画，但会在系统已移过的布局上**再移一次**
        ///     → 落位**跑到后一位**（用户本次反馈）。
        ///   ➜ 正解：`apply(animatingDifferences: **false**)`。
        ///     它**只更新数据、不重置布局、不播自己的动画** ——
        ///     视觉完全由 `endInteractiveMovement()` 那次系统动画负责，两者不再打架。
        func syncAfterDrop(order: [TemplateRoute]) {
            guard dataSource != nil else { return }
            appliedKeys = order.map(\.key)
            appliedPinned = parent.pinnedKeys
            appliedDeleting = parent.deletingMode
            appliedEditing = parent.editingMode

            var snapshot = NSDiffableDataSourceSnapshot<String, TemplateRoute>()
            snapshot.appendSections(["main"])
            snapshot.appendItems(order, toSection: "main")
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        /// ★ DiffableDataSource 的核心：给快照，系统自己 diff + 播放动画。
        func apply(order: [TemplateRoute], animated: Bool) {
            guard let cv = collectionView, dataSource != nil else { return }

            // ★ 拖动刚落位：系统已经把 cell 移好，这里**只同步数据、不做 diff**。
            if dropJustHappened {
                dropJustHappened = false
                DebugLog.drag("apply -> syncAfterDrop(no diff)")
                syncAfterDrop(order: order)
                return
            }

            let keys = order.map(\.key)
            let orderUnchanged = appliedKeys == keys

            // ★★★ 2026-10-22（用户两次报「编辑和删除**依然用不了**」）——
            //   ⚠️ 上一版把 `modeChanged` 写在**赋值之后**：
            //     appliedEditing = parent.editingMode   // 先更新
            //     let modeChanged = appliedEditing != parent.editingMode   // 永远 false ✗
            //   → `reconfigureItems` 一次都没执行过。**先算，再存。**
            let modeChanged = appliedDeleting != parent.deletingMode
                || appliedEditing != parent.editingMode
                || appliedPinned != parent.pinnedKeys

            let sameContent = orderUnchanged && !modeChanged
            if sameContent && !appliedKeys.isEmpty { return }

            appliedKeys = keys
            appliedPinned = parent.pinnedKeys
            appliedDeleting = parent.deletingMode
            appliedEditing = parent.editingMode

            var snapshot = NSDiffableDataSourceSnapshot<String, TemplateRoute>()
            snapshot.appendSections(["main"])
            snapshot.appendItems(order, toSection: "main")

            // ★★★ 2026-10-23（用户）：「点击编辑和删除，**只能编辑那两个需要扫码的标签了，
            //   其他的都动不了了**」——
            //   说明 `reconfigureItems` 只对「新插入」的那两个生效，原有磁贴没重配。
            //   与其继续靠 `modeChanged` 猜时机（SwiftUI 的 `updateUIView` 可能在某些
            //   中间状态下先跑一次、把 `appliedEditing` 提前置位），
            //   ➜ **磁贴数量本来就很少（<20），每次 apply 都全量重配**，彻底绕开时机问题。
            if !order.isEmpty {
                snapshot.reconfigureItems(order)
            }
            // ★★★ 2026-10-21（用户）：「**不是弹性，是动画不连贯**」——
            //   原来外面套了 `UIView.animate` 包 `apply`：但 `apply` 是**异步布局**，
            //   下一帧才真正动 cell，而 `UIView.animate` 的时长已经走完 →
            //   外层的曲线和内层的布局对不上，看起来就是"断一下、跳一下"。
            //   ➜ 去掉外层包裹，只留 `apply(animatingDifferences:)`：
            //     整个 diff + 布局在同一套系统事务里，帧是连贯的。
            // 100% 原生：动画完全交给系统。
            dataSource.apply(snapshot, animatingDifferences: animated)
            _ = cv
        }

        // ── 尺寸 ──

        func collectionView(_ cv: UICollectionView,
                            layout cvLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = (cv.bounds.width - 12) / 2
            return CGSize(width: max(120, width), height: 132)
        }

        // ── 点击（Diffable 要用 itemIdentifier 反查，不能直接用 indexPath.item）──

        func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            cv.deselectItem(at: indexPath, animated: false)
            guard !parent.deletingMode, !parent.editingMode,
                  let route = dataSource.itemIdentifier(for: indexPath) else { return }
            parent.onSelect(route)
        }

        // ── 交互式移动：长按 → 开始 / 跟手 / 结束 ──

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let cv = collectionView,
                  !parent.deletingMode, !parent.editingMode else { return }
            let location = gesture.location(in: cv)

            switch gesture.state {
            case .began:
                pendingTarget = nil
                guard let indexPath = cv.indexPathForItem(at: location),
                      let route = dataSource.itemIdentifier(for: indexPath),
                      !parent.pinnedKeys.contains(route.key) else { return }
                cv.beginInteractiveMovementForItem(at: indexPath)
            case .changed:
                lastDragLocation = location
                // 顺手记下"手指现在压在哪一格"—— 这是**唯一语义明确**的目标位置来源。
                if let idx = cv.indexPathForItem(at: location) {
                    pendingTarget = idx.item
                }
                cv.updateInteractiveMovementTargetPosition(location)
            case .ended:
                DebugLog.drag("ended: pendingTarget=\(pendingTarget.map(String.init) ?? "nil")")
                // 交给 dataSource —— `moveItemAt` 会紧接着被调用（同一次 runloop）。
                dataSource.targetIndex = pendingTarget
                cv.endInteractiveMovement()
            default:
                pendingTarget = nil
                dataSource.targetIndex = nil
                cv.cancelInteractiveMovement()
            }
        }

    }
}

// MARK: - DataSource（为了接管 moveItemAt）
//
// ★★★ 2026-10-21（用户报：「**现在桌面图标不能拖动了**」）——
//   真因：`beginInteractiveMovement` 落位时会调 **dataSource 的** `collectionView(_:moveItemAt:to:)`，
//   而 `UICollectionViewDiffableDataSource` **没有实现这个可选方法**，
//   所以"松手后数据不落地" → 视觉上等于拖动没反应。
//   （这个方法必须挂在 dataSource 上，挂在 delegate 上永远不会被调用。）
//   ➜ 子类化，把落位事件转出来。

final class TileDataSource: UICollectionViewDiffableDataSource<String, TemplateRoute> {
    var onMove: ((Int, Int) -> Void)?
    /// 由 Coordinator 写入：手指最终压到的格子下标。
    var targetIndex: Int?
    /// 由 Coordinator 写入：落位即将发生 → 通知它下一次 apply 走"无 diff 同步"。
    var onDropLanded: (() -> Void)?

    override func collectionView(_ cv: UICollectionView,
                                 moveItemAt source: IndexPath,
                                 to destination: IndexPath) {
        // ★ 2026-10-22：**忽略 `destination`**（语义不可靠，见上），
        //   用 Coordinator 在 `.ended` 前记录的 `targetIndex`（手指压到的格子）。
        DebugLog.drag("moveItemAt src=\(source.item) dest=\(destination.item) "
                      + "usedTarget=\(targetIndex.map(String.init) ?? "nil")")
        guard let target = targetIndex else { return }
        onDropLanded?()
        onMove?(source.item, target)
    }
}

// MARK: - Cell

final class TileCell: UICollectionViewCell {
    static let reuseID = "TileCell"

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    private var onTapAction: (() -> Void)?
    private var onRemoveAction: (() -> Void)?
    private var onEditAction: (() -> Void)?
    private var route: TemplateRoute?
    private var deletingMode = false
    private var editingMode = false
    private var isPinned = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = Theme.tileRadius
        contentView.layer.cornerCurve = .continuous
        contentView.backgroundColor = .secondarySystemGroupedBackground

        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        contentView.addSubview(iconContainer)
        contentView.addSubview(titleLabel)
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            iconContainer.widthAnchor.constraint(equalToConstant: 46),
            iconContainer.heightAnchor.constraint(equalToConstant: 46),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),

            actionButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            actionButton.widthAnchor.constraint(equalToConstant: 30),
            actionButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(route: TemplateRoute,
                   pinned: Bool,
                   deletingMode: Bool,
                   editingMode: Bool,
                   onTapAction: @escaping () -> Void,
                   onRemoveAction: @escaping () -> Void,
                   onEditAction: @escaping () -> Void) {
        self.route = route
        self.deletingMode = deletingMode
        self.editingMode = editingMode
        self.isPinned = pinned
        self.onTapAction = onTapAction
        self.onRemoveAction = onRemoveAction
        self.onEditAction = onEditAction

        titleLabel.text = route.title
        iconView.image = UIImage(systemName: route.systemImage)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        iconView.tintColor = UIColor(route.tint)
        iconContainer.backgroundColor = UIColor(route.fill)

        if deletingMode {
            actionButton.isHidden = false
            actionButton.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
            actionButton.tintColor = .systemRed
            actionButton.backgroundColor = .clear
        } else if editingMode {
            if route.isCustom {
                actionButton.isHidden = false
                actionButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
                actionButton.tintColor = .systemGreen
                actionButton.backgroundColor = .clear
            } else {
                actionButton.isHidden = true
            }
        } else {
            actionButton.isHidden = false
            applyPinAppearance()
        }

        contentView.alpha = (deletingMode || editingMode) ? 0.55 : 1
    }

    /// 图钉外观（圆底 + 11pt 图标），`configure` 和"点击后立即刷新"共用。
    private func applyPinAppearance() {
        // 圆底：未固定 = 淡灰；固定 = 品牌色淡底（18%）。两层都是圆底，观感统一。
        // 图标 11pt bold（和之前 SwiftUI 版一致，不大不小）。
        let pinConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        actionButton.setImage(UIImage(systemName: isPinned ? "pin.fill" : "pin",
                                      withConfiguration: pinConfig), for: .normal)
        actionButton.tintColor = isPinned ? UIColor(Theme.brand) : .secondaryLabel
        actionButton.backgroundColor = isPinned
            ? UIColor(Theme.brand).withAlphaComponent(0.18)
            : .tertiarySystemFill
        actionButton.layer.cornerRadius = 15
    }

    @objc private func actionTapped() {
        if deletingMode {
            onRemoveAction?()
        } else if editingMode {
            onEditAction?()
        } else {
            // ★ 2026-10-21（用户）：「点击完固定后，**固定按钮的动画不是马上刷新**」
            //   ➜ 原来是等父状态变 → `apply` → `reconfigureItems` 才更新 cell，中间有延迟。
            //     这里**先本地翻转外观**（立即生效），再通知父级同步数据。
            isPinned.toggle()
            applyPinAppearance()
            onTapAction?()
        }
    }
}
