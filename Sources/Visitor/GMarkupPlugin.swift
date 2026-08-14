//
//  GMarkupPlugin.swift
//  GMarkdown
//
//  Created by GIKI on 2025/7/5.
//

import Foundation
import Markdown
import UIKit
import SwiftMath

/// 插件协议，用于处理不同类型的Markup元素
public protocol GMarkupPlugin {
    /// 插件标识符
    var identifier: String { get }
    
    /// 插件是否可以处理指定的Markup类型
    func canHandle(_ markup: Markup) -> Bool
    
    /// 处理Markup并返回AttributedString
    func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString?
}


/// 默认代码块插件实现
public class DefaultCodePlugin: GMarkupPlugin {
    public var identifier: String { "default.code" }
    
    public func canHandle(_ markup: Markup) -> Bool {
        return markup is CodeBlock
    }
    
    public func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        guard let codeBlock = markup as? CodeBlock else { return nil }
        return handleCodeBlock(codeBlock, visitor: &visitor)
    }
    
    public func handleCodeBlock(_ codeBlock: CodeBlock, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        let style = visitor.visitorStyle
        let code = codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = codeBlock.language
        if style.codeBlockStyle.useHighlight {
            if let highlighted = GMarkCodeHighlight.shared.generateAttributeText(code, language: language ?? ""),
               !highlighted.string.hasPrefix("undefined") {
                let attributed = NSMutableAttributedString(attributedString: highlighted)
                attributed.addAttribute(.font, value: style.codeBlockStyle.font)
                let attachment = MarkdownAttachment(viewProvider: MDCodeAttachedProvider(markup: codeBlock, style: style, attributedText: attributed))
                return NSAttributedString(attachment: attachment)
            }
        }
        let attributedString = MarkdownStyleProcessor.buildDefaultAttributedString(from: code, style: style)
        attributedString.addAttribute(.font, value: style.codeBlockStyle.font)
        attributedString.addAttribute(.foregroundColor, value: style.codeBlockStyle.foregroundColor)
        let attachment = MarkdownAttachment(viewProvider: MDCodeAttachedProvider(markup: codeBlock, style: style, attributedText: attributedString))
        return NSAttributedString(attachment: attachment)
    }
}

/// 默认表格插件实现
public class DefaultTablePlugin: GMarkupPlugin {
    public var identifier: String { "default.table" }
    public func canHandle(_ markup: Markup) -> Bool {
        return markup is Table
    }
    
    public func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        guard let table = markup as? Table else { return nil }
        return handleTable(table, visitor: &visitor)
    }
    
    public func handleTable(_ table: Table, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        var style = visitor.visitorStyle
        style.useMPTextKit = true
        style.imageStyle.size = CGSize(width: 60, height: 60)
        var tableVisitor = GMarkupTableVisitor(style: style)
        tableVisitor.imageLoader = visitor.imageLoader
        let table = tableVisitor.visit(table)
        let provider = MDTableAttachedProvider(markTable: table, style: style)
        let attachment = MarkdownAttachment(viewProvider: provider)
        result.append(NSAttributedString(attachment: attachment))
        return result
    }
}


/// 默认分割线插件实现
public class DefaultThematicBreakPlugin: GMarkupPlugin {
    public var identifier: String { "default.thematicBreak" }

    public func canHandle(_ markup: Markup) -> Bool {
        return markup is ThematicBreak
    }

    public func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        guard markup is ThematicBreak else { return nil }
        let provider = MDThematicBreakAttachedProvider(style: visitor.visitorStyle)
        let attachment = MarkdownAttachment(viewProvider: provider)
        return NSAttributedString(attachment: attachment)
    }
}

private final class MDThematicBreakAttachedProvider: MarkdownAttachedViewProvider {
    private let preferredMaxContainerWidth: CGFloat
    private let height: CGFloat = 16

    init(style: Style) {
        self.preferredMaxContainerWidth = style.maxContainerWidth > 0 ? style.maxContainerWidth : 0
    }

    func instantiateView(for attachment: MarkdownAttachment, in behavior: MarkdownAttachingBehavior) -> UIView {
        return MDThematicBreakView()
    }

    func bounds(for attachment: MarkdownAttachment, textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint) -> CGRect {
        let lineWidth = lineFrag.width > 0 ? lineFrag.width : (textContainer?.size.width ?? 0)
        let fallbackWidth = UIScreen.main.bounds.width - 16 * 2
        let baseWidth = preferredMaxContainerWidth > 0 ? preferredMaxContainerWidth : (lineWidth > 0 ? lineWidth : fallbackWidth)
        let width = max(lineWidth > 0 ? min(baseWidth, lineWidth) : baseWidth, 1)
        return CGRect(origin: .zero, size: CGSize(width: width, height: height))
    }
}

private final class MDThematicBreakView: UIView {
    private let line = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        line.backgroundColor = .lightGray
        addSubview(line)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let lineHeight = 1 / max(scale, 1)
        let lineFrame = CGRect(x: 4,
                               y: 0.5 * (bounds.height - lineHeight),
                               width: max(bounds.width - 8, 0),
                               height: lineHeight)
        if line.frame != lineFrame {
            line.frame = lineFrame
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

/// 默认图片插件实现
public class DefaultImagePlugin: GMarkupPlugin {
    public var identifier: String { "default.image" }
    
    public func canHandle(_ markup: Markup) -> Bool {
        return markup is Image
    }
    
    public func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        guard let image = markup as? Image else { return nil }
        return handleImage(image, visitor: &visitor)
    }
    
    public func handleImage(_ image: Image, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        guard image.source != nil else {
            return nil
        }
        let imageProvider = MDAsyncImageAttachedProvider(markup: image, style: visitor.visitorStyle)
        let attachment = MarkdownAttachment(viewProvider: imageProvider)
        return NSAttributedString(attachment: attachment)
    }
}

/// 默认HTML块插件实现
public class DefaultHTMLBlockPlugin: GMarkupPlugin {
    public var identifier: String { "default.htmlblock" }
    
    public func canHandle(_ markup: Markup) -> Bool {
        return markup is HTMLBlock
    }
    
    public func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        guard let htmlBlock = markup as? HTMLBlock else { return nil }
        return handleHTMLBlock(htmlBlock, visitor: &visitor)
    }
    
    public func handleHTMLBlock(_ htmlBlock: HTMLBlock, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        let style = visitor.visitorStyle
        let rawHTML = htmlBlock.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = CommonHTMLAttribute.parseHTMLWithSwiftSoup(from: rawHTML, style: style)
        MarkdownStyleProcessor.appendBreakIfNeeded(for: htmlBlock, to: result, style: style)
        return result
    }
}

/// 默认内联HTML插件实现
public class DefaultInlineHTMLPlugin: GMarkupPlugin {
    public var identifier: String { "default.inlinehtml" }
    
    private var beginLaTex:Bool = false
    
    public func canHandle(_ markup: Markup) -> Bool {
        return markup is InlineHTML || beginLaTex
    }
    
    public func handle(_ markup: Markup, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        let style = visitor.visitorStyle
        if beginLaTex, let text = markup as? Text {
            let renderResult = GMarkLaTexRender.renderLatexSmart(from: text.plainText, style: style)
            if renderResult.success, let image = renderResult.image {
                let provider = MDLaTexAttachedProvider(laTexImage: image, style: style)
                let attachment = MarkdownAttachment(viewProvider: provider)
                return NSAttributedString(attachment: attachment)
            } else {
                return nil
            }
        }
        guard let inlineHTML = markup as? InlineHTML else { return nil }
        return handleInlineHTML(inlineHTML, visitor: &visitor)
    }
    
    public func handleInlineHTML(_ inlineHTML: InlineHTML, visitor: inout GMarkupAttachVisitor) -> NSAttributedString? {
        if inlineHTML.rawHTML.contains("<LaTex>") {
            beginLaTex = true
            return NSAttributedString(string: "")
        } else if inlineHTML.rawHTML.contains("</LaTex>") {
            beginLaTex = false
            return NSAttributedString(string: "")
        }
        let style = visitor.visitorStyle
        let rawHTML = inlineHTML.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawHTML.lowercased().hasPrefix("<br") {
            return NSAttributedString.singleNewline(withStyle: style)
        }
        // InlineHTML 是行内节点，不能在这里无条件追加换行；
        // 段落级 HTML 混排和 HTMLBlock 会负责块级换行，否则 <strong>/<span> 等行内标签会多出空行。
        return CommonHTMLAttribute.parseHTMLWithSwiftSoup(from: rawHTML, style: style)
    }
}
