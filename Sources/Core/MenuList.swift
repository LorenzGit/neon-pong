import SpriteKit
import UIKit

struct MenuItem {
    let id: String
    var title: String
    /// Right-hand value. Present on rows that cycle through options.
    var value: String?
    var symbol: String?
    var enabled = true
    /// Extra line shown beneath the list while this row is selected.
    var detail: String?
    var tint: UIColor?

    var isOption: Bool { value != nil }
}

/// Vertical, controller-driven list. Selection is a moving neon slab so the
/// focused row is unmistakable from across the room.
final class MenuList: SKNode {

    private(set) var items: [MenuItem]
    private(set) var selectedIndex = 0

    var onSelect: ((MenuItem, Int) -> Void)?
    /// Fired when an option row is nudged left (-1) or right (+1).
    var onAdjust: ((MenuItem, Int, Int) -> Void)?
    var onSelectionChanged: ((MenuItem, Int) -> Void)?

    private let rowWidth: CGFloat
    private let rowHeight: CGFloat
    private let spacing: CGFloat

    private let highlight: SKSpriteNode
    private let highlightGlow: GlowSprite
    private var rowNodes: [RowNode] = []
    private let detailLabel: NeonLabel

    init(items: [MenuItem], width: CGFloat = 760,
         rowHeight: CGFloat = 88, spacing: CGFloat = 14) {
        self.items = items
        self.rowWidth = width
        self.rowHeight = rowHeight
        self.spacing = spacing

        highlight = SKSpriteNode(texture: TextureFactory.panel(
            size: CGSize(width: width, height: rowHeight),
            corner: 16,
            fill: UIColor(hex: 0x142A52, alpha: 0.95),
            stroke: Theme.p1,
            lineWidth: 3),
                                 size: CGSize(width: width, height: rowHeight))
        highlightGlow = GlowSprite(color: Theme.p1, diameter: width * 1.1, intensity: 0.30, falloff: 3.0)
        highlightGlow.yScale = rowHeight / (width * 1.1) * 3.4
        detailLabel = NeonLabel("", style: .caption, color: Theme.inkDim, glow: 0.35)

        super.init()

        addChild(highlightGlow)
        addChild(highlight)
        rebuildRows()
        addChild(detailLabel)
        layoutDetail()
        moveHighlight(animated: false)
        refreshRowStates()
        announceSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var contentHeight: CGFloat {
        CGFloat(items.count) * rowHeight + CGFloat(max(0, items.count - 1)) * spacing
    }

    private func rowY(_ index: Int) -> CGFloat {
        let total = contentHeight
        let top = total / 2 - rowHeight / 2
        return top - CGFloat(index) * (rowHeight + spacing)
    }

    private func layoutDetail() {
        detailLabel.position = CGPoint(x: 0, y: -contentHeight / 2 - 52)
    }

    // MARK: - Rows

    private func rebuildRows() {
        rowNodes.forEach { $0.removeFromParent() }
        rowNodes = items.enumerated().map { index, item in
            let row = RowNode(item: item, width: rowWidth, height: rowHeight)
            row.position = CGPoint(x: 0, y: rowY(index))
            addChild(row)
            return row
        }
    }

    /// Replaces the contents while keeping the selection where possible.
    func reload(_ newItems: [MenuItem]) {
        let previousID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
        items = newItems
        rebuildRows()
        if let previousID, let match = items.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = match
        }
        selectedIndex = clamp(selectedIndex, 0, max(0, items.count - 1))
        layoutDetail()
        moveHighlight(animated: false)
        refreshRowStates()
        announceSelection()
    }

    /// Updates one row's value in place, without disturbing the selection.
    func updateValue(_ value: String, forID id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].value = value
        rowNodes[index].setValue(value)
    }

    func updateItem(_ id: String, _ transform: (inout MenuItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[index])
        rowNodes[index].apply(items[index])
        if index == selectedIndex { announceSelection() }
    }

    // MARK: - Navigation

    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        var next = selectedIndex
        // Skip disabled rows so focus never lands somewhere dead.
        for _ in 0..<items.count {
            next = (next + delta + items.count) % items.count
            if items[next].enabled { break }
        }
        guard next != selectedIndex else { return }
        selectedIndex = next
        SoundEngine.shared.play(.uiMove, volume: 0.5)
        moveHighlight(animated: true)
        refreshRowStates()
        announceSelection()
    }

    func adjust(_ delta: Int) {
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        guard item.enabled, item.isOption else { return }
        SoundEngine.shared.play(.uiMove, volume: 0.7)
        rowNodes[selectedIndex].nudge(delta)
        onAdjust?(item, selectedIndex, delta)
    }

    func activate() {
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        guard item.enabled else { return }
        if item.isOption {
            // Confirming an option row cycles it forward, which is what people
            // expect when they press the main button on a settings row.
            adjust(1)
            return
        }
        SoundEngine.shared.play(.uiConfirm)
        rowNodes[selectedIndex].pressFeedback()
        onSelect?(item, selectedIndex)
    }

    func select(index: Int) {
        guard items.indices.contains(index), items[index].enabled else { return }
        selectedIndex = index
        moveHighlight(animated: true)
        refreshRowStates()
        announceSelection()
    }

    private func announceSelection() {
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        detailLabel.text = item.detail ?? ""
        onSelectionChanged?(item, selectedIndex)
    }

    private func moveHighlight(animated: Bool) {
        guard items.indices.contains(selectedIndex) else { return }
        let target = CGPoint(x: 0, y: rowY(selectedIndex))
        let tint = items[selectedIndex].tint ?? Theme.p1
        highlight.texture = TextureFactory.panel(
            size: CGSize(width: rowWidth, height: rowHeight), corner: 16,
            fill: tint.withAlphaComponent(0.16), stroke: tint, lineWidth: 3)
        highlightGlow.color = tint
        if animated {
            let move = SKAction.move(to: target, duration: 0.14).eased(.easeOut)
            highlight.run(move)
            highlightGlow.run(.move(to: target, duration: 0.14).eased(.easeOut))
        } else {
            highlight.position = target
            highlightGlow.position = target
        }
    }

    private func refreshRowStates() {
        for (index, row) in rowNodes.enumerated() {
            row.setFocused(index == selectedIndex)
        }
    }

    // MARK: - Row node

    private final class RowNode: SKNode {

        private let titleLabel: NeonLabel
        private var valueLabel: NeonLabel?
        private var symbol: SymbolNode?
        private var chevrons: SKNode?
        private let width: CGFloat
        private var item: MenuItem

        init(item: MenuItem, width: CGFloat, height: CGFloat) {
            self.width = width
            self.item = item
            let color = item.enabled ? Theme.ink : Theme.inkFaint
            titleLabel = NeonLabel(item.title, style: .button, color: color,
                                   align: .left, glow: 0.4)
            super.init()

            var textX = -width / 2 + 34
            if let symbolName = item.symbol,
               let node = SymbolNode(symbolName, pointSize: 32,
                                     color: item.tint ?? Theme.inkDim) {
                node.position = CGPoint(x: textX + 16, y: 0)
                addChild(node)
                symbol = node
                textX += 56
            }
            titleLabel.position = CGPoint(x: textX, y: 0)
            addChild(titleLabel)

            if let value = item.value {
                let label = NeonLabel(value, style: .button,
                                      color: item.tint ?? Theme.gold,
                                      align: .right, glow: 0.5)
                label.position = CGPoint(x: width / 2 - 62, y: 0)
                addChild(label)
                valueLabel = label
                addChild(makeChevrons(width: width, color: item.tint ?? Theme.gold))
            }
            alpha = item.enabled ? 0.72 : 0.3
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        private func makeChevrons(width: CGFloat, color: UIColor) -> SKNode {
            let node = SKNode()
            if let left = SymbolNode("chevron.left", pointSize: 24, color: color) {
                left.position = CGPoint(x: width / 2 - 250, y: 0)
                left.alpha = 0.6
                node.addChild(left)
            }
            if let right = SymbolNode("chevron.right", pointSize: 24, color: color) {
                right.position = CGPoint(x: width / 2 - 26, y: 0)
                right.alpha = 0.6
                node.addChild(right)
            }
            node.alpha = 0
            chevrons = node
            return node
        }

        func apply(_ newItem: MenuItem) {
            item = newItem
            titleLabel.text = newItem.title
            titleLabel.color = newItem.enabled ? Theme.ink : Theme.inkFaint
            if let value = newItem.value { valueLabel?.text = value }
            alpha = newItem.enabled ? (alpha > 0.9 ? 1 : 0.72) : 0.3
        }

        func setValue(_ value: String) {
            valueLabel?.text = value
            valueLabel?.pop(scale: 1.1, duration: 0.16)
        }

        func setFocused(_ focused: Bool) {
            guard item.enabled else { return }
            removeAction(forKey: "focus")
            run(.fadeAlpha(to: focused ? 1.0 : 0.72, duration: 0.12), withKey: "focus")
            chevrons?.run(.fadeAlpha(to: focused ? 1 : 0, duration: 0.12))
        }

        func nudge(_ delta: Int) {
            let dx = CGFloat(delta) * 10
            run(.sequence([
                .moveBy(x: dx, y: 0, duration: 0.06),
                .moveBy(x: -dx, y: 0, duration: 0.10).eased(.easeOut)
            ]))
        }

        func pressFeedback() {
            removeAction(forKey: "press")
            run(.sequence([
                .scale(to: 0.97, duration: 0.05),
                .scale(to: 1.0, duration: 0.12).eased(.easeOut)
            ]), withKey: "press")
        }
    }
}
