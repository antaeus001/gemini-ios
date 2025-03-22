import Foundation
import SwiftUI
import UIKit

// 枚举定义消息内容类型
enum ChatContentType: Equatable {
    case text(String)
    case image(UIImage)
    case mixedContent([MixedContentItem])
    
    static func == (lhs: ChatContentType, rhs: ChatContentType) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsText), .text(let rhsText)):
            return lhsText == rhsText
        case (.image(let lhsImage), .image(let rhsImage)):
            // 由于UIImage没有原生实现Equatable，我们可以比较它们的pngData
            if let lhsData = lhsImage.pngData(), let rhsData = rhsImage.pngData() {
                return lhsData == rhsData
            }
            return false
        case (.mixedContent(let lhsItems), .mixedContent(let rhsItems)):
            guard lhsItems.count == rhsItems.count else { return false }
            // 比较每个项目
            for (index, lhsItem) in lhsItems.enumerated() {
                if lhsItem != rhsItems[index] {
                    return false
                }
            }
            return true
        default:
            // 不同类型的内容不相等
            return false
        }
    }
}

// 聊天消息类
class ChatMessage: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    let role: ChatRole
    let timestamp = Date()
    
    @Published var content: ChatContentType
    var isGenerating: Bool = false
    
    init(role: ChatRole, content: ChatContentType) {
        self.role = role
        self.content = content
    }
    
    // 实现Equatable协议
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        // 只比较内容和角色，忽略ID和时间戳
        return lhs.role == rhs.role && lhs.content == rhs.content
    }
}