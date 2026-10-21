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
        cv.dragDelegate = context.coordinator
        cv.dropDelegate = context.coordinator
        cv.dragInteractionEnabled = true
        cv.register(TileCell.self, forCellWithReuseIdentifier: TileCell.reuseID)

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
                             UICollectionViewDelegateFlowLayout,
                             UICollectionViewDragDelegate,
                             UICollectionViewDropDelegate {
        var parent: TileGrid
        weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<String, TemplateRoute>!

        /// 上一次应用的状态（没变就不 apply，避免拖动中反复重建）。
        private var appliedKeys: [String] = []
        private var appliedPinned: [String] = []
        private var appliedDeleting = false
        private var appliedEditing = false


        init(_ parent: TileGrid) {
            self.parent = parent
        }

        func makeDataSource() {
            guard let cv = collectionView else { return }
            dataSource = UICollectionViewDiffableDataSource<String, TemplateRoute>(
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
        }

        /// ★ DiffableDataSource 的核心：给快照，系统自己 diff + 播放动画。
        func apply(order: [TemplateRoute], animated: Bool) {
            guard let cv = collectionView, dataSource != nil else { return }
            let keys = order.map(\.key)
            let orderUnchanged = appliedKeys == keys
            let sameContent = orderUnchanged
                && appliedPinned == parent.pinnedKeys
                && appliedDeleting == parent.deletingMode
                && appliedEditing == parent.editingMode
            if sameContent && !appliedKeys.isEmpty { return }

            appliedKeys = keys
            appliedPinned = parent.pinnedKeys
            appliedDeleting = parent.deletingMode
            appliedEditing = parent.editingMode

            var snapshot = NSDiffableDataSourceSnapshot<String, TemplateRoute>()
            snapshot.appendSections(["main"])
            snapshot.appendItems(order, toSection: "main")
            // 顺序没变、只是固定/编辑/删除状态变了 → reconfigure 即可（不重建 cell、不闪）。
            if orderUnchanged, !appliedKeys.isEmpty {
                snapshot.reconfigureItems(order)
            }
            // ★★★ 2026-10-21（用户）：「**不是弹性，是动画不连贯**」——
            //   原来外面套了 `UIView.animate` 包 `apply`：但 `apply` 是**异步布局**，
            //   下一帧才真正动 cell，而 `UIView.animate` 的时长已经走完 →
            //   外层的曲线和内层的布局对不上，看起来就是"断一下、跳一下"。
            //   ➜ 去掉外层包裹，只留 `apply(animatingDifferences:)`：
            //     整个 diff + 布局在同一套系统事务里，帧是连贯的。
            // 100% 原生：动画完全交给 DiffableDataSource。
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

        // ── 拖：谁能被拖 ──

        func collectionView(_ cv: UICollectionView,
                            itemsForBeginning session: UIDragSession,
                            at indexPath: IndexPath) -> [UIDragItem] {
            guard !parent.deletingMode, !parent.editingMode,
                  let route = dataSource.itemIdentifier(for: indexPath),
                  !parent.pinnedKeys.contains(route.key) else { return [] }
            let provider = NSItemProvider(object: route.key as NSString)
            let item = UIDragItem(itemProvider: provider)
            item.localObject = route.key
            return [item]
        }

        // ── 放：拖动中持续告诉系统"插到第几格" → 系统播放实时让位 ──

        func collectionView(_ cv: UICollectionView,
                            dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destinationIndexPath: IndexPath?)
                            -> UICollectionViewDropProposal {
            guard session.localDragSession != nil,
                  !parent.deletingMode, !parent.editingMode else {
                return UICollectionViewDropProposal(operation: .cancel)
            }
            return UICollectionViewDropProposal(operation: .move,
                                                 intent: .insertAtDestinationIndexPath)
        }

        func collectionView(_ cv: UICollectionView,
                            performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first,
                  let key = item.dragItem.localObject as? String,
                  let from = parent.order.firstIndex(where: { $0.key == key }) else { return }

            // ★★★ 2026-10-21（用户）：「**100% 原生哈不怕麻烦**」——
            //   100% 原生 = **不自己插手任何动画**：
            //     · 不调 `coordinator.drop(...)`（那是"飞落"，会和 diff 动画打架）；
            //     · 不加任何 suppress 标志；
            //     · 只更新数据，**全部动画由 `dataSource.apply(animatingDifferences: true)` 播**。
            //   ⚠️ 代价（用户已接受）：松手时卡片会直接"消失/重排"，没有从手指飞落的过程。
            guard let dest = coordinator.destinationIndexPath else { return }
            parent.onMove(from, dest.item)
            _ = cv
        }

        // ── 拖动预览：用实际 cell 尺寸，避免裁切/松手变形 ──

        func collectionView(_ cv: UICollectionView,
                            dragPreviewParametersForItemAt indexPath: IndexPath)
                            -> UIDragPreviewParameters? {
            let params = UIDragPreviewParameters()
            params.backgroundColor = .clear
            let cell = cv.cellForItem(at: indexPath)
            let rect = cell?.bounds ?? CGRect(x: 0, y: 0,
                                              width: (cv.bounds.width - 12) / 2,
                                              height: 132)
            params.visiblePath = UIBezierPath(roundedRect: rect,
                                              cornerRadius: Theme.tileRadius)
            return params
        }
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
