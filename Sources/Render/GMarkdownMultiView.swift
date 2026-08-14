//
//  GMarkdownMultiView.swift
//  GMarkRender
//
//  Created by GIKI on 2024/7/25.
//

import Markdown
import MPITextKit
import UIKit

// MARK: - Protocols

protocol ChunkCellConfigurable {
    func configure(with chunk: GMarkChunk)
}

protocol ChunkCellProvider {
    static var cellClass: AnyClass { get }
    static var reuseIdentifier: String { get }
    func dequeueConfiguredCell(for collectionView: UICollectionView, at indexPath: IndexPath, with chunk: GMarkChunk) -> UICollectionViewCell
}

// MARK: - ChunkCellProvider Implementation

struct DefaultChunkCellProvider<T: UICollectionViewCell & ChunkCellConfigurable>: ChunkCellProvider {
    static var cellClass: AnyClass { T.self }
    static var reuseIdentifier: String { String(describing: T.self) }
    
    func dequeueConfiguredCell(for collectionView: UICollectionView, at indexPath: IndexPath, with chunk: GMarkChunk) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseIdentifier, for: indexPath) as! T
        cell.configure(with: chunk)
        return cell
    }
}

extension ChunkCellConfigurable {
    func configure(with _: GMarkChunk) {}
}

// MARK: - CellProvider Factory

class ChunkCellProviderFactory {
    
    static func provider(for chunk: GMarkChunk) -> ChunkCellProvider {
        switch chunk.chunkType {
        case .Text:
            return DefaultChunkCellProvider<GMarkTextCell>()
        case .Code:
            return DefaultChunkCellProvider<GMarkCodeCell>()
        case .Table:
            return DefaultChunkCellProvider<GMarkTableCell>()
        case .Thematic:
            return DefaultChunkCellProvider<GMarkThematicCell>()
        case .Latex:
            if chunk.latexImage != nil {
                return DefaultChunkCellProvider<GMarkLatexCell>()
            } else {
                return DefaultChunkCellProvider<GMarkTextCell>()
            }
        default:
            return DefaultChunkCellProvider<GMarkTextCell>()
        }
    }
    
    static var allProviders: [ChunkCellProvider.Type] {
        return [
            DefaultChunkCellProvider<GMarkTextCell>.self,
            DefaultChunkCellProvider<GMarkCodeCell>.self,
            DefaultChunkCellProvider<GMarkTableCell>.self,
            DefaultChunkCellProvider<GMarkThematicCell>.self,
            DefaultChunkCellProvider<GMarkLatexCell>.self,
        ]
    }
}

// MARK: - UICollectionView Extension

extension UICollectionView {
    func registerCells(_ providers: [ChunkCellProvider.Type]) {
        for provider in providers {
            register(provider.cellClass, forCellWithReuseIdentifier: provider.reuseIdentifier)
        }
    }
}

@objcMembers
public class MarkdownResult: NSObject {
    public var chunks: [GMarkChunk] = []
    public var totalHeight: CGFloat = 0
}

@objcMembers
public class GMarkdownMultiView: UIView {
    // MARK: - Properties
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, GMarkChunk>!
    
    public var handlerChain: GMarkHandlerChain = .init()
    private let imageLoader = YSTNukeImageLoader()
    public var style = MarkdownStyle.defaultStyle()
    public var generator = GMarkChunkGenerator()
    public var maxContainerWidth: CGFloat {
        get {
            return style.maxContainerWidth > 0 ? style.maxContainerWidth : UIScreen.main.bounds.width - 16*2
        }
        set {
            style.maxContainerWidth = newValue
            generator.style = style
        }
    }
    
    public var currentFont: UIFont {
        get {
            style.fonts.current
        }
        set {
            style.fonts.current = newValue
            generator.style = style
        }
    }
    
    public var currentColor: UIColor {
        get {
            style.colors.current
        }
        set {
            style.colors.current = newValue
            generator.style = style
        }
    }
    // MARK: - Initialization
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        addHandlers()
        style.fonts.current = UIFont(name: "PingFangSC-Regular", size: 16) ?? .systemFont(ofSize: 16)
        style.colors.current = UIColor(hex: "#333333")
        style.paragraphStyle.lineSpacing = 2;
        style.paragraphStyle.paragraphSpacing = 10
        generator.style = style
        generator.imageLoader = YSTNukeImageLoader()
        generator.addLaTexHandler()
        setupCollectionView()
        configureDataSource()
    
    }
    
    // MARK: - Setup
    
    private func setupCollectionView() {
        let layout = createLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        configureCollectionView()
        addCollectionViewConstraints()
        registerCells()
    }
    
    private func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = .zero
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        return layout
    }
    
    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.allowsSelection = false
        collectionView.delegate = self
        addSubview(collectionView)
    }
    
    private func addCollectionViewConstraints() {
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func registerCells() {
        collectionView.registerCells(ChunkCellProviderFactory.allProviders)
    }
    
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, GMarkChunk>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            let provider = ChunkCellProviderFactory.provider(for: item)
            item.maxContainerWidth = self!.style.maxContainerWidth
            let cell = provider.dequeueConfiguredCell(for: collectionView, at: indexPath, with: item)
            self?.configureHandlerChain(for: cell)
            return cell
        }
    }
    
    private func configureHandlerChain(for cell: UICollectionViewCell) {
        if let textCell = cell as? GMarkTextCell {
            textCell.handlerChain = handlerChain
        } else if let codeCell = cell as? GMarkCodeCell {
            codeCell.handlerChain = handlerChain
        } else if let tableCell = cell as? GMarkTableCell {
            tableCell.handlerChain = handlerChain
        }
    }
    
    // MARK: - Public Methods
    
    public func updateMarkdown(_ items: [GMarkChunk]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, GMarkChunk>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    public func loadMarkdown(contentString: String) async -> ([GMarkChunk], CGFloat) {
        let chunks = await parseMarkdown(contentString)
        let totalHeight = chunks.reduce(0) { $0 + $1.itemSize.height }
        clearAllCache()
        return (chunks, totalHeight)
    }
    
    @objc public func updateStreamContent(partialContent: String, completion: @escaping ([GMarkChunk], CGFloat) -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            let chunks = await self.parseMarkdown(partialContent)
            let totalHeight = chunks.reduce(0) { $0 + $1.itemSize.height }
            await MainActor.run { [weak self] in
                self?.updateMarkdown(chunks)
            }
            completion(chunks, totalHeight)
        }
    }
    
    public func loadMarkdownSync(contentString: String) -> MarkdownResult? {
        let result = MarkdownResult()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let chunks = await parseMarkdown(contentString)
            let height = chunks.reduce(0) { $0 + $1.itemSize.height }
            result.chunks = chunks;
            result.totalHeight = height
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    public func parseMarkdown(_ content: String) async -> [GMarkChunk] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let processor = GMarkProcessor(parser: GMarkParser(), chunkGenerator: generator)
                let chunks = processor.process(markdown: content)
                continuation.resume(returning: chunks)
            }
        }
    }
    
    public func clearAllCache (){
        GMarkCachedManager.shared.clearAllCache()
    }
}

extension GMarkdownMultiView: UICollectionViewDelegateFlowLayout {
    public func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return CGSize(width: UIScreen.main.bounds.width, height: 0.00)
        }
        
        let width = min(item.style.maxContainerWidth, UIScreen.main.bounds.width)
        return CGSize(width: width, height: item.itemSize.height)
    }
}

extension GMarkdownMultiView {
    func addHandlers() {
        let handler = DefaultMarkHandler()
        handlerChain.addHandler(handler)
    }
}

// MARK: - Supporting Types

enum Section {
    case main
}

class GMarkThematicCell: UICollectionViewCell, ChunkCellConfigurable {
    static let reuseIdentifier = "GMarkThematicCell"
    private let line = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(line)
        line.backgroundColor = .lightGray
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        line.frame = CGRect(x: 4, y: 0.5 * (contentView.bounds.height - 1), width: contentView.bounds.width - 8, height: 1)
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with _: GMarkChunk) {}
}
