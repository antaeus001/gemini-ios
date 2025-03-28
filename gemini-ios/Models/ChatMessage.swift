import Foundation
import SwiftUI
import UIKit

// 枚举定义消息内容类型
enum ChatContentType: Equatable {
    case text(String)
    case image(UIImage, UUID = UUID())
    case mixedContent([MixedContentItem])
    case markdown(String)
    case imageUrl(String)
    
    static func == (lhs: ChatContentType, rhs: ChatContentType) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsText), .text(let rhsText)):
            return lhsText == rhsText
        case (.image(_, let lhsUUID), .image(_, let rhsUUID)):
            // 比较UUID而不是图像数据
            return lhsUUID == rhsUUID
        case (.mixedContent(let lhsItems), .mixedContent(let rhsItems)):
            guard lhsItems.count == rhsItems.count else { return false }
            // 比较每个项目
            for (index, lhsItem) in lhsItems.enumerated() {
                if lhsItem != rhsItems[index] {
                    return false
                }
            }
            return true
        case (.markdown(let lhsText), .markdown(let rhsText)):
            return lhsText == rhsText
        case (.imageUrl(let lhsUrl), .imageUrl(let rhsUrl)):
            return lhsUrl == rhsUrl
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
    
    // 监听内容变化，并触发objectWillChange
    @Published var content: ChatContentType {
        willSet {
            // 确保在修改之前触发UI更新
            objectWillChange.send()
        }
    }
    
    @Published var isGenerating: Bool = false {
        willSet {
            // 确保在修改之前触发UI更新
            objectWillChange.send()
        }
    }
    
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