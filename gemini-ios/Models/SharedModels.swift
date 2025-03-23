// 这是用于替换的代码

import Foundation
import UIKit

// 枚举定义消息角色
public enum ChatRole: Equatable {
    case user
    case assistant
}

// 混合内容项
public enum MixedContentItem: Identifiable, Equatable {
    case text(String, UUID = UUID())
    case image(UIImage, UUID = UUID())
    case markdown(String, UUID = UUID())
    
    // 使用计算属性获取关联值中的UUID
    public var id: UUID {
        switch self {
        case .text(_, let id):
            return id
        case .image(_, let id):
            return id
        case .markdown(_, let id):
            return id
        }
    }
    
    public static func == (lhs: MixedContentItem, rhs: MixedContentItem) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsText, _), .text(let rhsText, _)):
            return lhsText == rhsText
        case (.image(let lhsImage, _), .image(let rhsImage, _)):
            // 由于UIImage没有原生实现Equatable，我们可以比较它们的pngData
            if let lhsData = lhsImage.pngData(), let rhsData = rhsImage.pngData() {
                return lhsData == rhsData
            }
            return false
        case (.markdown(let lhsText, _), .markdown(let rhsText, _)):
            return lhsText == rhsText
        default:
            // 不同类型的项目不相等
            return false
        }
    }
}

// 然后在ChatMessage.swift和GeminiService.swift中导入这个模块并使用这些共享类型
