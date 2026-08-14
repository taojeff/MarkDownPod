//
//  File.swift
//  GMarkdown
//
//  Created by GIKI on 2025/3/14.
//

import Foundation
import UIKit
import MPITextKit

class GMarkTextCell: UICollectionViewCell, MPILabelDelegate, ChunkCellConfigurable {
    public var handlerChain: GMarkHandlerChain?

    static let reuseIdentifier = "GMarkTextCell"

    private let label: MPILabel = {
        let label = MPILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        label.delegate = self
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -0),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -0),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with chunk: GMarkChunk) {
        if let textRender = chunk.textRender {
            label.textRenderer = textRender
            return
        }
        label.attributedText = chunk.attributedText
    }

    // MARK: - MPILabelDelegate
    
    func label(_ label: MPILabel, didInteractWith link: MPITextLink, forAttributedText attributedText: NSAttributedString, in characterRange: NSRange, interaction: MPITextItemInteraction) {
        
        guard interaction == .tap else { return }
        
        let value = link.value
        
        // 处理URL类型的value
        if let url = value as? URL {
            handleURL(url)
        }
        // 处理字符串类型的value
        else if let urlString = value as? String {
            if let url = URL(string: urlString) {
                handleURL(url)
            }
        }
    }

    private func handleURL(_ url: URL) {
        switch url.scheme {
        case "tel": // 电话链接
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        case "http", "https": // 网页链接
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        case "mailto": // 邮件链接
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        default: // 其他自定义协议
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}
