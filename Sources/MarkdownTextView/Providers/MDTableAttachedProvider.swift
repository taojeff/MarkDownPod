//
//  MDTableAttachedProvider.swift
//  GMarkdown
//
//  Created by 巩柯 on 2025/7/3.
//

import UIKit
import MPITextKit

class MDTableAttachedProvider: MarkdownAttachedViewProvider {
    
    let markTable:GMarkTable
    let style: Style
    
    var tableLayout: GMarkTableLayout?
    var itemSize: CGSize = .zero
    private let preferredMaxContainerWidth: CGFloat
        
    private var attachedTableView: GMarkTableView?
    private var attachedContainerView: MDTableContainerView?

    var tableView: GMarkTableView {
        if let attachedTableView = attachedTableView {
            return attachedTableView
        }
        let table = GMarkTableView()
        table.backgroundColor = .white
        table.register(GMarkTableRichLabelCell.self, forCellReuseIdentifier: "GMarkTableRichLabelCell")
        table.dataSource = self
        table.style = tableStyle
        table.layer.cornerRadius = 6
        table.layer.masksToBounds = true
        attachedTableView = table
        return table
    }

    private var containerView: MDTableContainerView {
        if let attachedContainerView = attachedContainerView {
            return attachedContainerView
        }
        let container = MDTableContainerView(tableView: tableView, contentInset: defaultStyle.padding)
        attachedContainerView = container
        return container
    }
    
    public private(set) lazy var tableStyle: GMarkTableStyle = {
        let style = GMarkTableStyle()
        style.cornerRadius = 6
        style.colGap = 1
        style.gapColor = UIColor(hex: "#F2F2FF")
        style.maxContainerWidth = max(preferredMaxContainerWidth, 1)
        return style
    }()

    var defaultStyle: TableStyle {
        return style.tableStyle
    }
    
    public init(markTable: GMarkTable, style: Style) {
        self.markTable = markTable
        self.style = style
        self.preferredMaxContainerWidth = style.maxContainerWidth > 0 ? style.maxContainerWidth : 0
        tableLayout = GMarkTableLayout(markTable: markTable, style: style)
        itemSize = CGSize(width: max(preferredMaxContainerWidth, 1), height: tableLayout?.tableHeight ?? 0)
    }
    
    func instantiateView(for attachment: MarkdownAttachment, in behavior: MarkdownAttachingBehavior) -> UIView {
        let container = containerView
        container.contentInset = defaultStyle.padding
        tableView.reloadData()
        return container
    }

    func bounds(for attachment: MarkdownAttachment, textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint) -> CGRect {
        let lineWidth = lineFrag.width > 0 ? lineFrag.width : (textContainer?.size.width ?? 0)
        let fallbackWidth = UIScreen.main.bounds.width - 16 * 2
        let baseWidth = preferredMaxContainerWidth > 0 ? preferredMaxContainerWidth : (lineWidth > 0 ? lineWidth : fallbackWidth)
        let width = max(lineWidth > 0 ? min(baseWidth, lineWidth) : baseWidth, 1)
        if abs(itemSize.width - width) > 0.5 {
            itemSize = CGSize(width: width, height: itemSize.height)
        }
        return CGRect(origin: .zero, size: self.itemSize)
    }
}

private final class MDTableContainerView: UIView {
    let tableView: GMarkTableView
    var contentInset: UIEdgeInsets {
        didSet {
            if contentInset != oldValue {
                setNeedsLayout()
            }
        }
    }

    init(tableView: GMarkTableView, contentInset: UIEdgeInsets) {
        self.tableView = tableView
        self.contentInset = contentInset
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = false
        addSubview(tableView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tableFrame = CGRect(x: contentInset.left,
                                y: contentInset.top,
                                width: max(bounds.width - contentInset.left - contentInset.right, 0),
                                height: max(bounds.height - contentInset.top - contentInset.bottom, 0))
        if tableView.frame != tableFrame {
            tableView.frame = tableFrame
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

extension MDTableAttachedProvider: GMarkTableViewDataSource {

    func headerEmpty() -> Bool {
        return tableLayout?.headerRenders.isEmpty ?? true
    }

    func headerRenders() -> [MPITextRenderer] {
        if let renders = tableLayout?.headerRenders {
            return renders
        }
        return []
    }

    func bodyRenders() -> [[MPITextRenderer]] {
        if let renders = tableLayout?.bodyRenders {
            return renders
        }
        return []
    }

    func tableRenders() -> [[MPITextRenderer]] {
        let header = headerRenders()
        let headerArray = header.isEmpty ? [] : [header]
        let body = bodyRenders()
        let result = headerArray + body
        return result
    }

    // MARK: GMarkTableViewDataSource

    func numberOfRows(in _: GMarkTableView) -> Int {
        return tableRenders().count
    }

    func numberOfCols(in _: GMarkTableView) -> Int {
        let bodyColCount = bodyRenders().map { $0.count }.max() ?? 0
        return max(headerRenders().count, bodyColCount)
    }

    func numberOfLockingRows(in _: GMarkTableView) -> Int {
        return 0
    }

    func numberOfLockingCols(in _: GMarkTableView) -> Int {
        return 0
    }

    func table(_: GMarkTableView, lengthForRow row: Int) -> CGFloat {
        var height: CGFloat = defaultStyle.cellHeight
        let renderArray = tableRenders()
        if let renders = renderArray[safe: row] {
            for textRender in renders {
                let textheight = textRender.size().height
                height = max(height, textheight + defaultStyle.cellPadding.top + defaultStyle.cellPadding.bottom)
            }
        }
        return max(height, defaultStyle.cellHeight)
    }

    func table(_: GMarkTableView, lengthForCol col: Int) -> CGFloat {
        let renderArray = tableRenders()
        var maxColWidth: CGFloat = 0
        for row in renderArray {
            if col < row.count {
                if let textRender = row[safe: col] {
                    let textWidth = textRender.size().width
                    maxColWidth = max(maxColWidth, textWidth + defaultStyle.cellPadding.left + defaultStyle.cellPadding.right)
                }
            }
        }
        return max(maxColWidth, defaultStyle.cellWidth)
    }

    func table(_ table: GMarkTableView, cellForIndexPath indexPath: TabIndexPath) -> GMarkTableViewCell? {
        guard let cell = table.dequeueReusableCell(withIdentifier: "GMarkTableRichLabelCell", for: indexPath) as? GMarkTableRichLabelCell else {
            return nil
        }

        let renders = tableRenders()

        if indexPath.row < renders.count && indexPath.col < renders[indexPath.row].count {
            let textRender = renders[indexPath.row][indexPath.col]
            cell.configure(textRender)
        }

        cell.contentInset = defaultStyle.cellPadding

        if indexPath.row % 2 == 0 {
            cell.backgroundColor = .black.withAlphaComponent(0.06)
        } else {
            cell.backgroundColor = UIColor(hex: "#F2F4F7")
        }

        return cell
    }
}



