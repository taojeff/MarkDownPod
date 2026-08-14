//
//  Untitled.swift
//  YSTBasicSDK
//
//  Created by John on 2025/9/22.
//  Copyright © 2025 易视腾科技股份有限公司. All rights reserved.
//

import UIKit
import SwiftSoup

public class CommonHTMLAttribute: NSObject {
    public static func parseHTMLWithSwiftSoup(from htmlString: String, style: Style) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let context = HTMLRenderContext(font: style.fonts.current, color: style.colors.current)

        do {
            // 使用 parseBodyFragment 解析片段，兼容「<h1>标题</h1>普通文本」这类非完整 HTML。
            let doc: SwiftSoup.Document = try SwiftSoup.parseBodyFragment(htmlString)
            guard let body = doc.body() else { return result }

            let children = body.getChildNodes()
            for (index, child) in children.enumerated() {
                append(node: child, to: result, context: context, style: style)

                if shouldAppendNewline(after: child, at: index, in: children) {
                    appendNewline(to: result, style: style)
                }
            }
        } catch Exception.Error(let type, let message) {
            print("SwiftSoup错误类型: \(type), 消息: \(message)")
            return plainAttributedString(from: htmlString, style: style)
        } catch {
            print("其他错误: \(error)")
            return plainAttributedString(from: htmlString, style: style)
        }

        return result
    }

    private struct HTMLRenderContext {
        var font: UIFont
        var color: UIColor
    }

    private static func plainAttributedString(from text: String, style: Style) -> NSMutableAttributedString {
        let context = HTMLRenderContext(font: style.fonts.current, color: style.colors.current)
        return NSMutableAttributedString(string: text, attributes: attributes(context: context, style: style))
    }

    private static func append(node: Node,
                               to result: NSMutableAttributedString,
                               context: HTMLRenderContext,
                               style: Style) {
        if let textNode = node as? SwiftSoup.TextNode {
            appendTextNode(textNode, to: result, context: context, style: style)
        } else if let element = node as? SwiftSoup.Element {
            result.append(parseElement(element, context: context, style: style))
        }
    }

    private static func appendTextNode(_ textNode: SwiftSoup.TextNode,
                                       to result: NSMutableAttributedString,
                                       context: HTMLRenderContext,
                                       style: Style) {
        let text = textNode.getWholeText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        result.append(NSAttributedString(string: text, attributes: attributes(context: context, style: style)))
    }

    private static func parseElement(_ element: SwiftSoup.Element,
                                     context: HTMLRenderContext,
                                     style: Style) -> NSAttributedString {
        let tagName = element.tagName().lowercased()

        if tagName == "br" {
            return NSAttributedString.singleNewline(withStyle: style)
        }

        if tagName == "hr" {
            return NSAttributedString(string: "\n", attributes: attributes(context: context, style: style))
        }

        let elementContext = contextForElement(element, parent: context, style: style)
        let result = NSMutableAttributedString()
        let childNodes = element.getChildNodes()

        for (index, node) in childNodes.enumerated() {
            append(node: node, to: result, context: elementContext, style: style)

            if shouldAppendNewline(after: node, at: index, in: childNodes) {
                appendNewline(to: result, style: style)
            }
        }

        applyElementStyles(element, to: result, context: elementContext, style: style)
        return result
    }

    private static func shouldAppendNewline(after node: Node, at index: Int, in siblings: [Node]) -> Bool {
        guard index < siblings.count - 1 else { return false }

        if let element = node as? SwiftSoup.Element, isBlockLevelElement(element) {
            return true
        }

        if node is SwiftSoup.TextNode,
           let nextElement = siblings[index + 1] as? SwiftSoup.Element,
           isBlockLevelElement(nextElement) {
            return true
        }

        return false
    }

    private static func appendNewline(to result: NSMutableAttributedString, style: Style) {
        if result.string.hasSuffix("\n") { return }
        result.append(NSAttributedString.singleNewline(withStyle: style))
    }

    private static func attributes(context: HTMLRenderContext, style: Style) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.paragraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = style.paragraphStyle.paragraphSpacing
        paragraphStyle.minimumLineHeight = style.paragraphStyle.minimumLineHeight
        paragraphStyle.alignment = style.paragraphStyle.alignment

        return [
            .font: context.font,
            .foregroundColor: context.color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func isBlockLevelElement(_ element: SwiftSoup.Element) -> Bool {
        let blockTags: Set<String> = [
            "address", "article", "aside", "blockquote", "canvas", "dd", "div", "dl",
            "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2",
            "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "noscript",
            "ol", "output", "p", "pre", "section", "table", "tfoot", "ul", "video"
        ]
        return blockTags.contains(element.tagName().lowercased())
    }

    private static func contextForElement(_ element: SwiftSoup.Element,
                                          parent: HTMLRenderContext,
                                          style: Style) -> HTMLRenderContext {
        var context = parent
        let tagName = element.tagName().lowercased()

        switch tagName {
        case "h1":
            context.font = style.fonts.h1
            context.color = style.colors.h1
        case "h2":
            context.font = style.fonts.h2
            context.color = style.colors.h2
        case "h3":
            context.font = style.fonts.h3
            context.color = style.colors.h3
        case "h4":
            context.font = style.fonts.h4
            context.color = style.colors.h4
        case "h5":
            context.font = style.fonts.h5
            context.color = style.colors.h5
        case "h6":
            context.font = style.fonts.h6
            context.color = style.colors.h6
        case "strong", "b":
            context.font = parent.font.bold ?? parent.font
        case "em", "i":
            context.font = parent.font.italic ?? parent.font
        case "code", "pre":
            context.font = UIFont.monospacedSystemFont(ofSize: parent.font.pointSize, weight: .regular)
            context.color = style.colors.inlineCodeForeground
        case "a":
            context.color = style.colors.link
        default:
            break
        }

        applyInlineStyle(from: element, to: &context)
        return context
    }

    private static func applyInlineStyle(from element: SwiftSoup.Element, to context: inout HTMLRenderContext) {
        guard let inlineStyle = try? element.attr("style") else { return }

        if let sizeValue = cssValue(named: "font-size", in: inlineStyle),
           let sizeRange = sizeValue.range(of: "\\d+(\\.\\d+)?", options: .regularExpression),
           let size = Double(String(sizeValue[sizeRange])) {
            context.font = context.font.withSize(CGFloat(size))
        }

        if let fontValue = cssValue(named: "font-family", in: inlineStyle) {
            let fontName = fontValue
                .split(separator: ",")
                .first
                .map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) ?? ""
            if !fontName.isEmpty, let customFont = UIFont(name: fontName, size: context.font.pointSize) {
                context.font = customFont
            }
        }

        if let colorValue = cssValue(named: "color", in: inlineStyle),
           let color = parseColor(from: colorValue) {
            context.color = color
        }
    }

    private static func cssValue(named name: String, in inlineStyle: String) -> String? {
        let declarations = inlineStyle.split(separator: ";", omittingEmptySubsequences: true)
        for declaration in declarations {
            let parts = declaration.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key == name.lowercased() {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func parseColor(from colorString: String) -> UIColor? {
        let trimmedColor = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colorRange = trimmedColor.range(of: "#[0-9a-fA-F]{6}", options: .regularExpression) {
            return UIColor(hex: String(trimmedColor[colorRange]))
        }

        if let colorRange = trimmedColor.range(of: "rgb\\([^)]+\\)", options: .regularExpression) {
            let colorStr = String(trimmedColor[colorRange])
                .replacingOccurrences(of: "rgb(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let components = colorStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if components.count == 3,
               let r = Int(components[0]),
               let g = Int(components[1]),
               let b = Int(components[2]) {
                guard (0...255).contains(r),
                      (0...255).contains(g),
                      (0...255).contains(b) else {
                    return nil
                }
                return UIColor(red: CGFloat(r) / 255.0,
                               green: CGFloat(g) / 255.0,
                               blue: CGFloat(b) / 255.0,
                               alpha: 1.0)
            }
        }

        switch trimmedColor.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "black": return .black
        case "white": return .white
        case "gray", "grey": return .gray
        default: return nil
        }
    }

    private static func applyElementStyles(_ element: SwiftSoup.Element,
                                           to attributedString: NSMutableAttributedString,
                                           context: HTMLRenderContext,
                                           style: Style) {
        guard attributedString.length > 0 else { return }

        let tagName = element.tagName().lowercased()
        let range = NSRange(location: 0, length: attributedString.length)

        switch tagName {
        case "a":
            if let href = try? element.attr("href"), let url = URL(string: href) {
                attributedString.addAttribute(.link, value: url, range: range)
                attributedString.addAttribute(.foregroundColor, value: style.colors.link, range: range)
                attributedString.addAttribute(.underlineStyle, value: style.linkUnderlineStyle.rawValue, range: range)
            }
        case "u":
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case "code", "pre":
            attributedString.addAttribute(.foregroundColor, value: style.colors.inlineCodeForeground, range: range)
            attributedString.addAttribute(.backgroundColor, value: style.colors.inlineCodeBackground, range: range)
        case "span", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote":
            if let inlineStyle = try? element.attr("style"),
               let backgroundColorValue = cssValue(named: "background-color", in: inlineStyle),
               let color = parseColor(from: backgroundColorValue) {
                attributedString.addAttribute(.backgroundColor, value: color, range: range)
            }
        case "li":
            let bulletAttributed = NSMutableAttributedString(string: "• ", attributes: attributes(context: context, style: style))
            bulletAttributed.append(attributedString)
            attributedString.setAttributedString(bulletAttributed)
        default:
            break
        }
    }
}
