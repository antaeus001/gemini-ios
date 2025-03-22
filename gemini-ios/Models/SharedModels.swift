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
    case text(String)
    case image(UIImage)
    
    public var id: UUID {
        UUID()
    }
    
    public static func == (lhs: MixedContentItem, rhs: MixedContentItem) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsText), .text(let rhsText)):
            return lhsText == rhsText
        case (.image(let lhsImage), .image(let rhsImage)):
            // 由于UIImage没有原生实现Equatable，我们可以比较它们的pngData
            if let lhsData = lhsImage.pngData(), let rhsData = rhsImage.pngData() {
                return lhsData == rhsData
            }
            return false
        default:
            // 不同类型的项目不相等
            return false
        }
    }
}

// 然后在ChatMessage.swift和GeminiService.swift中导入这个模块并使用这些共享类型
