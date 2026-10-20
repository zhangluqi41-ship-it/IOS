import SwiftUI
import UIKit

// MARK: - 磁贴网格（UICollectionView 版）
//
// ★★★ 2026-10-21（用户）：「**哪个是最接近苹果的最完美的视觉方案**」
//   → `UICollectionView` + `UICollectionViewDragDelegate` + `UICollectionViewDropDelegate`
//   理由：**iOS 主屏（SpringBoard）本身就是这个组合**，所以下面这些动画全是系统内置的，
//   一行都不用自己写：
//     · 长按抬起：图标放大 + 投影
//     · 拖动中：**其他磁贴实时让开**
//     · 目标位置：**半透明占位符**
//     · 松手：弹性归位
//     · 拖到屏幕边缘：自动滚动
//
//   SwiftUI 的 `.draggable` 做不到上面这些 —— 它对应的是"跨 App 拖放"，
//   只有 `isTargeted: Bool`，拿不到"插到第几格"的中间态。
//
//   ⚠️ 代价：UICollectionView 是 UIKit 视图，图钉 / 删除 / 编辑 / 点击跳转
//      都要在这里重新实现一遍（cell 内 `UIButton` + `didSelectItemAt`）。

/// 2 列网格的卡片。
struct TileGrid: UIViewRepresentable {
    let order: [TemplateRoute]
    let pinnedKeys: [String]
    let deletingMode: Bool
    let editingMode: Bool
    let onSelect: (TemplateRoute) -> Void
    let onPin: (TemplateRoute) -> Void
    let onRemove: (TemplateRoute) -> Void
    let onEdit: (TemplateRoute) -> Void
    /// 松手换位后回调（拖动的落点由 collectionView 算好，这里只负责持久化）。
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
        cv.showsVerticalScrollIndicator = true
        cv.delegate = context.coordinator
        cv.dataSource = context.coordinator
        cv.dragDelegate = context.coordinator
        cv.dropDelegate = context.coordinator
        cv.dragInteractionEnabled = true
        cv.register(TileCell.self, forCellWithReuseIdentifier: TileCell.reuseID)
        context.coordinator.collectionView = cv
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        context.coordinator.parent = self
        // 内容变了才 reload，避免拖动中途的每一帧都重建 cell。
        if context.coordinator.renderedKeys != order.map(\.key)
            || context.coordinator.renderedPinned != pinnedKeys
            || context.coordinator.renderedDeleting != deletingMode
            || context.coordinator.renderedEditing != editingMode {
            context.coordinator.renderedKeys = order.map(\.key)
            context.coordinator.renderedPinned = pinnedKeys
            context.coordinator.renderedDeleting = deletingMode
            context.coordinator.renderedEditing = editingMode
            cv.reloadData()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             UICollectionViewDataSource,
                             UICollectionViewDelegateFlowLayout,
                             UICollectionViewDragDelegate,
                             UICollectionViewDropDelegate {
        var parent: TileGrid
        weak var collectionView: UICollectionView?

        // 缓存上一次渲染的状态，避免 updateUIView 里无脑 reload。
        var renderedKeys: [String] = []
        var renderedPinned: [String] = []
        var renderedDeleting = false
        var renderedEditing = false

        init(_ parent: TileGrid) {
            self.parent = parent
        }

        // ── DataSource ──

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.order.count
        }

        func collectionView(_ cv: UICollectionView,
                            cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: TileCell.reuseID,
                                              for: indexPath) as! TileCell
            let route = parent.order[indexPath.item]
            cell.configure(route: route,
                           pinned: parent.pinnedKeys.contains(route.key),
                           deletingMode: parent.deletingMode,
                           editingMode: parent.editingMode,
                           onTapAction: { [weak self] in self?.parent.onPin(route) },
                           onRemoveAction: { [weak self] in self?.parent.onRemove(route) },
                           onEditAction: { [weak self] in self?.parent.onEdit(route) })
            return cell
        }

        // ── 尺寸 ──

        func collectionView(_ cv: UICollectionView,
                            layout cvLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = (cv.bounds.width - 12) / 2
            return CGSize(width: max(120, width), height: 132)
        }

        // ── 点击 ──

        func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            cv.deselectItem(at: indexPath, animated: false)
            guard !parent.deletingMode, !parent.editingMode else { return }
            parent.onSelect(parent.order[indexPath.item])
        }

        // ── 拖：谁能被拖 ──

        func collectionView(_ cv: UICollectionView,
                            itemsForBeginning session: UIDragSession,
                            at indexPath: IndexPath) -> [UIDragItem] {
            guard !parent.deletingMode, !parent.editingMode else { return [] }
            let route = parent.order[indexPath.item]
            // 固定项锁定位置，不给拖（用户：「被固定住的图标就应该移动不了」）。
            guard !parent.pinnedKeys.contains(route.key) else { return [] }

            let provider = NSItemProvider(object: route.key as NSString)
            let item = UIDragItem(itemProvider: provider)
            item.localObject = route.key
            return [item]
        }

        // ── 放：拖动过程中持续告诉系统"我要插到第几格" ──
        //
        // ★ 这个方法就是 SpringBoard 那种"其他磁贴实时让开"的来源：
        //   返回 `.move` + `.insertAtDestinationIndexPath` 后，系统立刻播放让位动画。

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

            // 有目标位置 → 插过去；没有（拖到空白）→ 不动。
            if let to = coordinator.destinationIndexPath?.item {
                parent.onMove(from, to)
            }
            coordinator.drop(item.dragItem, toItemAt: coordinator.destinationIndexPath ?? IndexPath(item: from, section: 0))
        }

        // 拖动时给一个跟手的预览（系统会加投影/缩放）。
        func collectionView(_ cv: UICollectionView,
                            dragPreviewParametersForItemAt indexPath: IndexPath)
                            -> UIDragPreviewParameters? {
            let params = UIDragPreviewParameters()
            let radius = Theme.tileRadius
            params.backgroundColor = .clear
            params.visiblePath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 160, height: 132),
                                              cornerRadius: radius)
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
        self.onTapAction = onTapAction
        self.onRemoveAction = onRemoveAction
        self.onEditAction = onEditAction

        titleLabel.text = route.title
        iconView.image = UIImage(systemName: route.systemImage)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        iconView.tintColor = UIColor(route.tint)
        iconContainer.backgroundColor = UIColor(route.fill)

        // 右上角：删除模式红减号 / 编辑模式绿加号（仅自定义）/ 平时固定图钉
        if deletingMode {
            actionButton.isHidden = false
            actionButton.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
            actionButton.tintColor = .systemRed
            actionButton.backgroundColor = .clear
            actionButton.layer.cornerRadius = 15
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
            actionButton.setImage(UIImage(systemName: pinned ? "pin.fill" : "pin"), for: .normal)
            actionButton.tintColor = pinned ? .white : .secondaryLabel
            actionButton.backgroundColor = pinned ? UIColor(Theme.brand) : .tertiarySystemFill
            actionButton.layer.cornerRadius = 15
        }

        // 删除/编辑模式下整张卡片变淡，和之前 SwiftUI 版本的观感一致。
        contentView.alpha = (deletingMode || editingMode) ? 0.55 : 1
    }

    @objc private func actionTapped() {
        if deletingMode {
            onRemoveAction?()
        } else if editingMode {
            onEditAction?()
        } else {
            onTapAction?()
        }
    }
}
