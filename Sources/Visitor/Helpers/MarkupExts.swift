//
//  MarkupExts.swift
//  GMarkdown
//
//  Created by 巩柯 on 2025/7/3.
//

import Markdown

extension ListItemContainer {
    var listDepth: Int {
        var depth = 0
        var current = parent
        while let currentElement = current {
            if currentElement is ListItemContainer {
                depth += 1
            }
            current = currentElement.parent
        }
        return depth
    }
}

extension BlockQuote {
    var quoteDepth: Int {
        var depth = 0
        var current = parent
        while let currentElement = current {
            if currentElement is BlockQuote {
                depth += 1
            }
            current = currentElement.parent
        }
        return depth
    }
}

extension Markup {
    
    var hasSuccessor: Bool {
        guard let childCount = parent?.childCount else { return false }
        return indexInParent < childCount - 1
    }
    
    var hasSuccessorForSplit: Bool {
        let siblingIndex = indexInParent
        guard let parent = parent, siblingIndex < parent.childCount - 1 else { return false }
        guard let nextSibling = parent.child(at: siblingIndex + 1) else { return false }
        return !isSplitPoint(nextSibling)
    }
    
    var isContainedInList: Bool {
        var current = parent
        while let currentElement = current {
            if currentElement is ListItemContainer {
                return true
            }
            current = currentElement.parent
        }
        return false
    }
    
    var subTag: String? {
        let siblingIndex = indexInParent
        guard let parent = parent, siblingIndex < parent.childCount - 1 else { return nil }
        let nextSibling = parent.child(at: siblingIndex + 1)
        if let inlineHTML = nextSibling as? InlineHTML, inlineHTML.plainText == "<sup>",
           let tagText = parent.child(at: siblingIndex + 2) as? Text {
            return tagText.plainText
        }
        return nil
    }
    
    func isSplitPoint(_ item: Markup) -> Bool {
        switch item {
        case is Table, is CodeBlock, is ThematicBreak, is Image:
            return true
        case let paragraph as Paragraph:
            if paragraph.child(at: 0) is Image { return true }
            if let inlineHTML = paragraph.child(at: 0) as? InlineHTML, inlineHTML.plainText == "<LaTex>" {
                return true
            }
            return false
        default:
            return false
        }
    }
}


extension Paragraph {
    /// Markdown 会把 `<h1>标题</h1>普通文本` 这类 HTML + 文本混排拆成
    /// InlineHTML/Text/InlineHTML。如果逐个 child 渲染，开闭标签中间的文字拿不到 HTML 样式；
    /// 因此在段落级别识别可渲染 HTML 片段，并把原始片段整体交给 HTML parser。
    var renderableHTMLFragment: String? {
        let directText = plainText
        if Self.isRenderableHTMLFragment(directText) {
            return directText
        }

        var rebuiltText = ""
        var hasInlineHTML = false
        for child in children {
            if let inlineHTML = child as? InlineHTML {
                rebuiltText.append(inlineHTML.rawHTML)
                hasInlineHTML = true
            } else {
                rebuiltText.append(Self.plainText(for: child))
            }
        }

        guard hasInlineHTML, Self.isRenderableHTMLFragment(rebuiltText) else { return nil }
        return rebuiltText
    }

    private static func plainText(for markup: Markup) -> String {
        switch markup {
        case let text as Text:
            return text.plainText
        case let inlineCode as InlineCode:
            return inlineCode.code
        case is SoftBreak, is LineBreak:
            return "\n"
        default:
            var stringifier = GMarkupStringifier()
            return stringifier.visit(markup)
        }
    }

    var containsRenderableHTMLFragment: Bool {
        return renderableHTMLFragment != nil
    }

    private static func isRenderableHTMLFragment(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        guard lowercasedText.contains("<"), lowercasedText.contains(">") else { return false }
        guard !lowercasedText.contains("<latex>") && !lowercasedText.contains("</latex>") else { return false }

        let supportedTags = [
            "h1", "h2", "h3", "h4", "h5", "h6",
            "p", "div", "span", "br", "strong", "b", "em", "i",
            "u", "a", "ul", "ol", "li", "blockquote", "pre", "code", "hr"
        ]
        return supportedTags.contains { tag in
            lowercasedText.contains("<\(tag)") || lowercasedText.contains("</\(tag)>")
        }
    }
}
