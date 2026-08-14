//
//  MarkdownTextView.swift
//  GMarkdown
//
//  Created by GIKI on 2025/7/3.
//

import UIKit
import SDWebImage

/// 流式 Markdown 渲染结果模型，供 Objective-C Cell 直接消费。
@objcMembers
public class StreamMarkdownModel: NSObject, NSCopying {
    public var markdownContent: NSAttributedString = NSAttributedString(string: "")
    /// 当前 attributed string 实际对应的原始 Markdown 前缀。
    public var renderedSourceContent: String = ""
    /// 转译是否完成（true: 当前服务端内容已经逐字渲染完成）
    public var exchangeStatus: Bool = false
    public var markdownHeight: CGFloat = 0
    /// 当前是否处于表格的流式降级展示阶段（true: 先按普通文本展示，完成后再渲染真实表格）
    public var containsStreamingTable: Bool = false

    public func copy(with zone: NSZone? = nil) -> Any {
        let model = StreamMarkdownModel()
        model.markdownContent = markdownContent.copy() as? NSAttributedString ?? markdownContent
        model.renderedSourceContent = renderedSourceContent
        model.exchangeStatus = exchangeStatus
        model.markdownHeight = markdownHeight
        model.containsStreamingTable = containsStreamingTable
        return model
    }
}

/// 流式 Markdown 显示代理协议。
@objc public protocol MarkdownTextViewStreamDelegate: NSObjectProtocol {
    @objc optional func markdownTextView(_ textView: MarkdownTextView, didUpdateStreamModel model: StreamMarkdownModel)
}
/// CADisplayLink 默认会强引用 target，这里用弱代理避免 MarkdownTextView 与 displayLink 形成循环引用。
private final class WeakDisplayLinkTarget: NSObject {
    weak var target: MarkdownTextView?

    init(target: MarkdownTextView) {
        self.target = target
        super.init()
    }

    @objc func tick() {
        target?.updateStreamTranslation()
    }
}

/// 专门用于Markdown渲染的TextView
/// 负责接收AttributedString并进行高性能渲染，支持SubviewAttaching
@objcMembers
open class MarkdownTextView: UITextView {
    
    // MARK: - Properties
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: WeakDisplayLinkTarget?
    private var currentIndex = 0
    private var currentContent = ""
    private var inputFinished = false
    private var streamProgressCallback: ((StreamMarkdownModel) -> Void)?
    public weak var streamDelegate: MarkdownTextViewStreamDelegate?
    /// 正常流式阶段每帧推进的最小字符数。一次推进多个字符比“严格 1 字/帧”更接近豆包的排式流水，且能减少 Markdown 重排次数。
    private let normalStreamCharactersPerFrame = 2
    /// 服务端已结束后，本地追帧加速，避免长内容 END 后还慢慢补字导致推荐按钮/卡片等待过久。
    private let finishedStreamCharactersPerFrame = 12
    /// 积压内容较多时的单帧最大推进数，限制主线程 Markdown 解析压力。
    private let maxStreamCharactersPerFrame = 24
    /// 最近一次生成的流式渲染源，用于过滤“表格尾行逐字变化但 UI 不需要刷新”的重复回调。
    private var latestStreamRenderContent = ""
    /// 最近一次真正回调给 Cell 的渲染源，避免相同表格附件重复 set attributedText 导致闪烁。
    private var lastStreamCallbackContent = ""
    /// 最近一次 Markdown 解析源/结果缓存，表格尾行逐字变化但展示源不变时不重复解析。
    private var lastRenderedStreamContent = ""
    private var lastRenderedStreamModel: StreamMarkdownModel?
    
    /// SubviewAttaching行为管理器
    private let attachmentBehavior = MarkdownAttachingBehavior()
    public var contentHeight:CGFloat = 0
    public var maxContainerWidth: CGFloat {
        get {
            return style.maxContainerWidth > 0 ? style.maxContainerWidth : UIScreen.main.bounds.width - 16*2
        }
        set {
            style.maxContainerWidth = newValue
        }
    }
    
    public var currentFont: UIFont {
        get {
            style.fonts.current
        }
        set {
            style.fonts.current = newValue
        }
    }
    
    public var currentColor: UIColor {
        get {
            style.colors.current
        }
        set {
            style.colors.current = newValue
        }
    }
    
    public var style = MarkdownStyle.defaultStyle()
    /// 是否启用SubviewAttaching功能
    public var isSubviewAttachingEnabled: Bool = true {
        didSet {
            updateAttachmentBehavior()
        }
    }
    
    /// 是否启用高性能渲染优化
    public var isPerformanceOptimized: Bool = true {
        didSet {
            attachmentBehavior.isPerformanceOptimized = isPerformanceOptimized
        }
    }
    
    // MARK: - Initialization
    
    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    deinit {
        stopDisplayLink()
    }
    
    private func commonInit() {
        style.useMPTextKit = false
        style.codeBlockStyle.customRender = false
        style.paragraphStyle.lineSpacing = 2;
        style.paragraphStyle.paragraphSpacing = 10
        setupAttachmentBehavior()
        setupDefaultConfiguration()
    }
    
    private func setupAttachmentBehavior() {
        attachmentBehavior.textView = self
        layoutManager.delegate = attachmentBehavior
        textStorage.delegate = attachmentBehavior
    }
    
    private func setupDefaultConfiguration() {
        // 默认配置
        isEditable = false
        isSelectable = false
        isScrollEnabled = true
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = false
        
        // 设置默认的文本容器配置
        textContainer.lineFragmentPadding = 0
    }
    
    // MARK: - Public Methods
    
    /// 设置渲染的AttributedString
    /// - Parameter attributedString: 已经解析和样式化的AttributedString
    public func setAttributedMarkdown(_ attributedString: NSAttributedString) {
        self.attributedText = attributedString
    }
    
    /// 追加AttributedString内容（用于流式渲染）
    /// - Parameter attributedString: 要追加的AttributedString
    public func appendAttributedMarkdown(_ attributedString: NSAttributedString) {
        let mutableText = NSMutableAttributedString(attributedString: self.attributedText)
        mutableText.append(attributedString)
        self.attributedText = mutableText
        
        // 自动滚动到底部
        if isPerformanceOptimized {
            scrollToBottom()
        }
    }
    
    /// 清空内容
    public func clearContent() {
        self.attributedText = NSAttributedString()
        resetStreamDisplay()
    }
    
    /// 滚动到底部
    public func scrollToBottom() {
        let bottomOffset = CGPoint(x: 0, y: max(0, contentSize.height - bounds.height))
        setContentOffset(bottomOffset, animated: false)
    }
    
    // MARK: - Override Methods
    
    open override var textContainerInset: UIEdgeInsets {
        didSet {
            // 文本容器插入变化时需要重新布局附加的子视图
            if isSubviewAttachingEnabled {
                attachmentBehavior.layoutAttachedSubviews()
            }
        }
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        // 确保子视图正确布局
        if isSubviewAttachingEnabled {
            attachmentBehavior.layoutAttachedSubviews()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateAttachmentBehavior() {
        if isSubviewAttachingEnabled {
            layoutManager.delegate = attachmentBehavior
            textStorage.delegate = attachmentBehavior
        } else {
            if layoutManager.delegate === attachmentBehavior {
                layoutManager.delegate = nil
            }
            if textStorage.delegate === attachmentBehavior {
                textStorage.delegate = nil
            }
            attachmentBehavior.removeAllAttachedSubviews()
        }
    }
    
    @objc public func complexityMarkdownContent( _ content: String, renderContent: Bool, completion: @escaping(NSAttributedString) -> Void ) {
        Task {
            // 显式切换到后台线程，执行耗时任务
            let (attributedText): (NSAttributedString) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let document = GMarkParser().parseMarkdown(from: content)
                    var visitor = GMarkupAttachVisitor(style: style)
                    visitor.imageLoader = YSTNukeImageLoader()
                    let attributedText = visitor.visit(document)
                    continuation.resume(returning: (attributedText))
                }
            }
            // 切回主线程设置 UI 和回调
            await MainActor.run {
                let finalText: NSAttributedString
                if attributedText.length > 0 {
                    finalText = attributedText
                } else {
                    finalText = NSAttributedString(string: "")
                }
                if renderContent {
                    self.attributedText = finalText
                }
                completion(finalText)
            }
        }
    }
    

    // MARK: - Stream Markdown

    /// 流式输入内容（接收服务端返回的累计 content 内容）。
    /// - Parameters:
    ///   - content: 当前累计的完整内容
    ///   - status: 服务端是否已经结束当前内容返回
    @objc public func streamInputContent(_ content: String, withInputStatus status: Bool) {
        currentContent = content
        inputFinished = status
        if content.count < currentIndex {
            currentIndex = 0
            latestStreamRenderContent = ""
            lastStreamCallbackContent = ""
            lastRenderedStreamContent = ""
            lastRenderedStreamModel = nil
        }
        if displayLink == nil {
            startDisplayLink()
        }
    }

    /// 新增：直接获取当前逐字渲染进度模型，方便 Objective-C 侧主动读取。
    @objc public func currentStreamMarkdownModel() -> StreamMarkdownModel {
        let model = getCurrentTranslatedModel()
        model.exchangeStatus = inputFinished && currentIndex >= currentContent.count
        return model
    }

    /// 设置流式显示进度回调。
    @objc public func setStreamProgressCallback(_ callback: @escaping (StreamMarkdownModel) -> Void) {
        streamProgressCallback = callback
    }

    /// 重置流式显示状态。
    @objc public func resetStreamDisplay() {
        stopDisplayLink()
        currentIndex = 0
        currentContent = ""
        inputFinished = false
        latestStreamRenderContent = ""
        lastStreamCallbackContent = ""
        lastRenderedStreamContent = ""
        lastRenderedStreamModel = nil
        streamProgressCallback = nil
        streamDelegate = nil
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let weakTarget = WeakDisplayLinkTarget(target: self)
        displayLinkTarget = weakTarget
        displayLink = CADisplayLink(target: weakTarget, selector: #selector(WeakDisplayLinkTarget.tick))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120)
        } else if #available(iOS 10.0, *) {
            displayLink?.preferredFramesPerSecond = 60
        } else {
            displayLink?.frameInterval = 1
        }
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
    }

    fileprivate func updateStreamTranslation() {
        if currentIndex < currentContent.count {
            translateOneCharacter()
        } else if inputFinished {
            let model = currentStreamMarkdownModel()
            stopDisplayLink()
            streamProgressCallback?(model)
            streamDelegate?.markdownTextView?(self, didUpdateStreamModel: model)
            let callback = streamProgressCallback
            let delegate = streamDelegate
            currentIndex = 0
            currentContent = ""
            inputFinished = false
            latestStreamRenderContent = ""
            lastStreamCallbackContent = ""
            lastRenderedStreamContent = ""
            lastRenderedStreamModel = nil
            streamProgressCallback = callback
            streamDelegate = delegate
        }
    }

    private func translateOneCharacter() {
        let contentCount = currentContent.count
        guard currentIndex < contentCount else { return }
        currentIndex = min(currentIndex + streamCharactersPerFrame(remainingCount: contentCount - currentIndex), contentCount)
        let model = getCurrentTranslatedModel()
        let shouldForceCallback = inputFinished && currentIndex >= contentCount
        guard shouldForceCallback || latestStreamRenderContent != lastStreamCallbackContent else { return }
        lastStreamCallbackContent = latestStreamRenderContent
        streamProgressCallback?(model)
        streamDelegate?.markdownTextView?(self, didUpdateStreamModel: model)
    }

    private func streamCharactersPerFrame(remainingCount: Int) -> Int {
        guard remainingCount > 0 else { return 0 }
        let baseStep = inputFinished ? finishedStreamCharactersPerFrame : normalStreamCharactersPerFrame
        // 内容积压越多，单帧推进越多；服务端 END 后再额外提速，使本地尽快追上完整 Markdown。
        let backlogStep = inputFinished ? max(baseStep, remainingCount / 8) : max(baseStep, remainingCount / 80)
        return max(1, min(maxStreamCharactersPerFrame, backlogStep, remainingCount))
    }

    private func getCurrentTranslatedModel() -> StreamMarkdownModel {
        let model = StreamMarkdownModel()
        let partialContent = String(currentContent.prefix(currentIndex))
        // 表格是 NSTextAttachment 子视图渲染，如果每推进 1 个字符都重建整张表，会导致 TableAttachment/Cell 高度抖动。
        // 这里保留“已经完整换行”的表格内容按真实表格渲染，只把正在输入中的最后一行临时降级为普通文本；
        // 这样逐词阶段也能看到表格，且表格主体只按行追加，避免逐字重建造成闪缩。
        let shouldRenderFinalMarkdown = inputFinished && currentIndex >= currentContent.count
        let streamingContent = shouldRenderFinalMarkdown ? (content: partialContent, containsTable: false) : stabilizedMarkdownForStreaming(partialContent)
        latestStreamRenderContent = streamingContent.content
        if !shouldRenderFinalMarkdown,
           streamingContent.content == lastRenderedStreamContent,
           let cachedModel = lastRenderedStreamModel?.copy() as? StreamMarkdownModel {
            cachedModel.exchangeStatus = false
            return cachedModel
        }
        let attributedText = renderMarkdownSync(streamingContent.content)
        model.markdownContent = attributedText
        model.renderedSourceContent = partialContent
        model.markdownHeight = attributedText.height(withWidth: style.maxContainerWidth)
        model.containsStreamingTable = streamingContent.containsTable
        model.exchangeStatus = false
        lastRenderedStreamContent = streamingContent.content
        lastRenderedStreamModel = model.copy() as? StreamMarkdownModel
        return model
    }

    /// 流式过程中稳定 Markdown 表格：完整行继续走真实 TableAttachment，当前未完成的表格尾行才降级为普通文本。
    /// 这样既不会把整张表都显示成 Markdown 标签，也避免每个字符都刷新表格附件导致 Cell 闪缩。
    private func stabilizedMarkdownForStreaming(_ content: String) -> (content: String, containsTable: Bool) {
        guard content.contains("|") else { return (content, false) }

        let lines = content.components(separatedBy: "\n")
        guard lines.count > 1 else { return (content, false) }

        var result = lines
        var containsTable = false
        var index = 0
        var inCodeFence = false
        let contentEndsWithNewline = content.hasSuffix("\n")

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if isMarkdownFenceLine(trimmed) {
                inCodeFence.toggle()
                index += 1
                continue
            }

            guard !inCodeFence else {
                index += 1
                continue
            }

            if index + 1 < lines.count,
               isMarkdownTableHeaderLine(lines[index]),
               isMarkdownTableSeparatorCandidateLine(lines[index + 1]) {
                var tableLineIndex = index
                while tableLineIndex < lines.count {
                    let tableLine = lines[tableLineIndex]
                    let tableTrimmed = tableLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if tableTrimmed.isEmpty || isMarkdownFenceLine(tableTrimmed) {
                        break
                    }
                    if tableLineIndex > index + 1 && !tableLine.contains("|") {
                        break
                    }

                    let isLastLine = tableLineIndex == lines.count - 1
                    let isCompleteLine = !isLastLine || contentEndsWithNewline
                    if !isCompleteLine {
                        // 当前正在逐字输入的表格尾行不参与真实表格解析，也不参与 UI 回调；表格按完整行追加更稳定。
                        // 如果是分隔行尚未完整，则连同 header 一起降级，等分隔行完整后再出现真实表格。
                        if tableLineIndex == index + 1 {
                            result[index] = disablingMarkdownTablePipes(in: lines[index])
                        }
                        result[tableLineIndex] = ""
                        containsTable = true
                        tableLineIndex += 1
                        break
                    }

                    if tableLineIndex == index + 1 && !isMarkdownTableSeparatorLine(tableLine) {
                        // 分隔行候选还不满足完整表格语法，先保持普通文本。
                        result[index] = disablingMarkdownTablePipes(in: lines[index])
                        result[tableLineIndex] = ""
                        containsTable = true
                        tableLineIndex += 1
                        break
                    }

                    containsTable = true
                    tableLineIndex += 1
                }
                index = max(tableLineIndex, index + 1)
            } else {
                index += 1
            }
        }

        return (result.joined(separator: "\n"), containsTable)
    }

    private func isMarkdownFenceLine(_ trimmedLine: String) -> Bool {
        return trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private func isMarkdownTableHeaderLine(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        let nonEmptyParts = parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonEmptyParts.count >= 2
    }

    private func isMarkdownTableSeparatorCandidateLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return false }
        let tableSeparatorCharacterSet = CharacterSet(charactersIn: "|:- \t")
        return trimmed.unicodeScalars.allSatisfy { tableSeparatorCharacterSet.contains($0) }
    }

    private func isMarkdownTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let tableSeparatorCharacterSet = CharacterSet(charactersIn: "|:- \t")
        guard trimmed.unicodeScalars.allSatisfy({ tableSeparatorCharacterSet.contains($0) }) else { return false }

        let trimmedPipes = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        let parts = trimmedPipes.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }

        return parts.allSatisfy { part in
            let cell = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cell.contains("-") else { return false }
            return cell.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private func disablingMarkdownTablePipes(in line: String) -> String {
        var result = ""
        var previousWasBackslash = false
        for character in line {
            if character == "|" && !previousWasBackslash {
                // 不能只转义成 \|：部分 Markdown 表格解析器仍可能按表格分隔符处理。
                // 流式阶段替换成全角竖线，视觉上仍像表格，语法上则不会生成 TableAttachment。
                result.append("｜")
                previousWasBackslash = false
            } else {
                result.append(character)
                previousWasBackslash = character == "\\" && !previousWasBackslash
            }
        }
        return result
    }

    private func renderMarkdownSync(_ content: String) -> NSAttributedString {
        let document = GMarkParser().parseMarkdown(from: content)
        var visitor = GMarkupAttachVisitor(style: style)
        visitor.imageLoader = YSTNukeImageLoader()
        let attributedText = visitor.visit(document)
        if attributedText.length > 0 {
            return attributedText
        } else {
            return NSAttributedString(string: "")
        }
    }

    @objc public func simplenessMarkdownContent(_ content: String) -> NSAttributedString {
        let document = GMarkParser().parseMarkdown(from: content)
        var visitor = GMarkupAttachVisitor(style: style)
        visitor.imageLoader = YSTNukeImageLoader()
        let attributedText = visitor.visit(document)
        let finalText: NSAttributedString
        if attributedText.length > 0 {
            finalText = attributedText
        } else {
            finalText = NSAttributedString(string: "")
        }
        return finalText
    }
}

@objcMembers
public class AttributedStringTool: NSObject {
    
    @objc public static func height(for attributedString: NSAttributedString, width: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        return attributedString.boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height.rounded(.up)
    }

    @objc public static func size(for attributedString: NSAttributedString, width: CGFloat) -> CGSize {
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let rect = attributedString.boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}

class YSTNukeImageLoader: @preconcurrency ImageLoader {
    
    @MainActor
    func loadImage(from source: String, into imageView: UIImageView) {
        guard let url = URL(string: source) else { return }
        
        imageView.sd_setImage(
            with: url,
            placeholderImage: UIImage.image(withColor: .lightGray),
            options: [.retryFailed, .continueInBackground],
            completed: nil
        )
    }
    
    func download(from source: String) async -> UIImage? {
        guard let url = URL(string: source) else { return nil }
        
        return await withCheckedContinuation { continuation in
            SDWebImageManager.shared.loadImage(
                with: url,
                options: [.retryFailed, .continueInBackground],
                progress: nil
            ) { image, _, error, _, _, _ in
                if let error = error {
                    print("Error downloading image: \(error)")
                }
                continuation.resume(returning: image)
            }
        }
    }
}

extension UIImage {
    
    /// 创建一个纯色的图片
    /// - Parameters:
    ///   - color: 图片的颜色
    ///   - size: 图片的尺寸
    /// - Returns: 生成的纯色图片
    static func image(withColor color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage? {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
}

extension NSAttributedString {
    
    /// 计算富文本在指定宽度下的高度
    /// - Parameter width: 限制宽度
    /// - Returns: 计算出的高度
    func height(withWidth width: CGFloat) -> CGFloat {
        return height(withConstrainedSize: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }
    
    /// 计算富文本在指定尺寸约束下的高度
    /// - Parameter size: 限制尺寸
    /// - Returns: 计算出的高度
    func height(withConstrainedSize size: CGSize) -> CGFloat {
        let actualSize = self.size(withConstrainedSize: size)
        return actualSize.height
    }
    
    /// 计算富文本的实际尺寸
    /// - Parameter width: 限制宽度
    /// - Returns: 实际尺寸
    func size(withWidth width: CGFloat) -> CGSize {
        return size(withConstrainedSize: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }
    
    /// 计算富文本在指定约束下的实际尺寸
    /// - Parameter size: 约束尺寸
    /// - Returns: 实际尺寸
    func size(withConstrainedSize size: CGSize) -> CGSize {
        guard self.length > 0 else {
            return CGSize.zero
        }
        
        let rect = self.boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        // 向上取整，避免显示不全
        return CGSize(width: ceil(rect.size.width), height: ceil(rect.size.height))
    }
}

@objc public extension MarkdownTextView {
    /// 设置统一字体
    @objc func setGlobalFont(_ font: UIFont) {
        style.fonts.current = font
        style.fonts.h1 = font
        style.fonts.h2 = font
        style.fonts.h3 = font
        style.fonts.h4 = font
        style.fonts.h5 = font
        style.fonts.h6 = font
        style.fonts.paragraph = font
        style.fonts.inlineCodeFont = font
        style.fonts.quoteFont = font
        style.blockquoteStyle.font = font;
    }

    /// 设置统一颜色
    @objc func setGlobalTextColor(_ color: UIColor) {
        style.colors.current = color
        style.colors.h1 = color
        style.colors.h2 = color
        style.colors.h3 = color
        style.colors.h4 = color
        style.colors.h5 = color
        style.colors.h6 = color
        style.colors.inlineCodeForeground = color
        style.colors.inlineCodeBackground = color
        style.colors.link = color
        style.colors.paragraph = color
        style.colors.quoteBackground = color
        style.colors.quoteForeground = color
        style.blockquoteStyle.textColor = color;
    }
}
