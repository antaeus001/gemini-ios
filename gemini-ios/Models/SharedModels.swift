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
    case imageUrl(String, UUID = UUID())
    
    // 使用计算属性获取关联值中的UUID
    public var id: UUID {
        switch self {
        case .text(_, let id):
            return id
        case .image(_, let id):
            return id
        case .markdown(_, let id):
            return id
        case .imageUrl(_, let id):
            return id
        }
    }
    
    public static func == (lhs: MixedContentItem, rhs: MixedContentItem) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsText, _), .text(let rhsText, _)):
            return lhsText == rhsText
        case (.image(_, let lhsUUID), .image(_, let rhsUUID)):
            return lhsUUID == rhsUUID
//        case (.image(let lhsImage, _), .image(let rhsImage, _)):
//            // 由于UIImage没有原生实现Equatable，我们可以比较它们的pngData
//            // 这里pngData()是个耗时操作，会导致卡顿
//            if let lhsData = lhsImage.pngData(), let rhsData = rhsImage.pngData() {
//                return lhsData == rhsData
//            }
//            return false
        case (.markdown(let lhsText, _), .markdown(let rhsText, _)):
            return lhsText == rhsText
        case (.imageUrl(let lhsUrl, _), .imageUrl(let rhsUrl, _)):
            return lhsUrl == rhsUrl
        default:
            // 不同类型的项目不相等
            return false
        }
    }
}

// 然后在ChatMessage.swift和GeminiService.swift中导入这个模块并使用这些共享类型

// 图片上传管理器
class ImageUploader {
    static let shared = ImageUploader()
    
    // 上传图片方法，使用GeminiService的uploadImage方法
    func uploadImage(_ image: UIImage) async throws -> String {
        return try await GeminiService.shared.uploadImage(image: image)
    }
    
    // 提供一个便利方法，直接从URL获取图片
    func getImage(from url: String) async throws -> UIImage? {
        guard let url = URL(string: url) else {
            throw NSError(domain: "ImageUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的图片URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "ImageUploader", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法从数据创建图片"])
        }
        
        return image
    }
}
