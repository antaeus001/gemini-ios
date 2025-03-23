import Foundation
import SwiftUI
import UIKit

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var currentlyGeneratingMessage: ChatMessage? = nil
    @Published var userImage: UIImage? = nil
    
    private let geminiService = GeminiService()
    
    init() {
        // 在初始化时自动启动欢迎对话
        startWelcomeChat()
    }
    
    // 启动欢迎对话
    func startWelcomeChat() {
        let welcomePrompt = """
        好的，请您上传您想要调整的图片。

        **一旦您上传图片，我会尝试进行以下调整：**

        • 提高亮度：使图像整体看起来更明亮
        • 增加对比度：拉大图像中亮部和暗部的差异，增强层次感和立体感。

        请您耐心等待我处理完成后的效果。
        """
        
        let assistantMessage = ChatMessage(role: .assistant, content: .markdown(welcomePrompt))
        messages.append(assistantMessage)
        objectWillChange.send()  // 确保UI更新
    }
    
    // 启动图像编辑聊天
    func startImageEditChat(prompt: String) {
        Task {
            await startGenerationChat(prompt: prompt)
        }
    }
    
    // 启动故事生成聊天
    func startStoryGenerationChat(prompt: String) {
        Task {
            await startGenerationChat(prompt: prompt)
        }
    }
    
    // 启动设计生成聊天
    func startDesignGenerationChat(prompt: String) {
        Task {
            await startGenerationChat(prompt: prompt)
        }
    }
    
    // 设置用户选择的图片
    func setUserImage(_ image: UIImage) {
        self.userImage = image
        
        // 添加图片到聊天界面
        let userMessage = ChatMessage(role: .user, content: .image(image))
        messages.append(userMessage)
        objectWillChange.send()  // 确保触发UI更新
    }
    
    // 发送带图片的消息
    func sendMessageWithImage(prompt: String) async {
        guard let image = userImage else { return }
        
        // 添加用户文本消息
        if !prompt.isEmpty {
            let userTextMessage = ChatMessage(role: .user, content: .text(prompt))
            messages.append(userTextMessage)
            objectWillChange.send()  // 确保UI更新
        }
        
        // 创建一个初始的助手消息，使用空的混合内容数组
        let initialAssistantMessage = ChatMessage(role: .assistant, content: .mixedContent([]))
        initialAssistantMessage.isGenerating = true
        currentlyGeneratingMessage = initialAssistantMessage
        messages.append(initialAssistantMessage)
        objectWillChange.send()
        
        isLoading = true
        error = nil
        
        do {
            // 重置GeminiService的对话历史
            geminiService.clearChatHistory()
            
            // 使用流式API发送带图片的消息
            try await geminiService.generateContentWithImage(prompt: prompt, image: image) { [weak self] contentItem in
                guard let self = self else { return }
                
                // 捕获任何处理过程中的错误
                do {
                    // 使用handleContentUpdate处理内容项
                    self.handleContentUpdate(contentItem)
                } catch {
                    print("处理内容更新时出错: \(error.localizedDescription)")
                }
            }
            
            // 完成生成后，设置为非生成状态
            if let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) {
                messages[index].isGenerating = false
                objectWillChange.send()
            }
            currentlyGeneratingMessage = nil
            
            // 清除用户图片
            userImage = nil
            objectWillChange.send()  // 确保UI更新
            
        } catch {
            self.error = error.localizedDescription
            print("API调用错误: \(error.localizedDescription)")
            
            // 移除正在生成的空消息
            if let lastMessage = messages.last, lastMessage.id == currentlyGeneratingMessage?.id {
                if case .mixedContent(let items) = lastMessage.content, items.isEmpty {
                    messages.removeLast()
                }
            }
            
            // 添加一个友好的错误消息
            let assistantMessage = ChatMessage(role: .assistant, content: .text("很抱歉，处理您的请求时遇到问题。错误信息：\(error.localizedDescription)"))
            messages.append(assistantMessage)
            currentlyGeneratingMessage = nil
            objectWillChange.send()
        }
        
        isLoading = false
        objectWillChange.send()  // 确保UI更新加载状态
    }
    
    // 通用的生成内容聊天方法
    func startGenerationChat(prompt: String) async {
        // 如果有用户图片，则调用带图片的方法
        if userImage != nil {
            await sendMessageWithImage(prompt: prompt)
            return
        }
        
        // 清除现有消息
        messages.removeAll()
        objectWillChange.send()  // 确保UI更新
        
        // 添加用户消息到UI
        let userMessage = ChatMessage(role: .user, content: .text(prompt))
        messages.append(userMessage)
        
        // 创建一个初始的助手消息，使用空的混合内容数组
        let initialAssistantMessage = ChatMessage(role: .assistant, content: .mixedContent([]))
        initialAssistantMessage.isGenerating = true
        currentlyGeneratingMessage = initialAssistantMessage
        messages.append(initialAssistantMessage)
        objectWillChange.send()  // 显式触发UI更新
        
        isLoading = true
        error = nil
        
        do {
            // 重置GeminiService的对话历史
            geminiService.clearChatHistory()
            
            // 使用流式API
            try await geminiService.generateContent(prompt: prompt) { [weak self] contentItem in
                guard let self = self else { return }
                
                Task { @MainActor in  // 确保在主线程上处理UI更新
                    // 使用handleContentUpdate处理内容项
                    self.handleContentUpdate(contentItem)
                }
            }
            
            // 完成生成后，设置为非生成状态
            if let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) {
                messages[index].isGenerating = false
                objectWillChange.send()  // 显式触发UI更新
            }
            currentlyGeneratingMessage = nil
            
        } catch {
            self.error = error.localizedDescription
            print("API调用错误: \(error.localizedDescription)")
            
            // 移除正在生成的空消息
            if let lastMessage = messages.last, lastMessage.id == currentlyGeneratingMessage?.id {
                if case .mixedContent(let items) = lastMessage.content, items.isEmpty {
                    messages.removeLast()
                }
            }
            
            // 添加一个友好的错误消息
            let assistantMessage = ChatMessage(role: .assistant, content: .text("很抱歉，处理您的请求时遇到问题。错误信息：\(error.localizedDescription)"))
            messages.append(assistantMessage)
            currentlyGeneratingMessage = nil
            objectWillChange.send()  // 显式触发UI更新
        }
        
        isLoading = false
        objectWillChange.send()  // 确保UI更新加载状态
    }
    
    // 更新当前生成的消息
    private func updateGeneratingMessageWithItems(_ items: [MixedContentItem]) {
        guard let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) else {
            print("未找到当前生成的消息，无法更新")
            return
        }
        
        // 检查是否有多个文本项，可以进行合并
        var optimizedItems = items
        
        // 优化多个连续文本项
        var i = 0
        while i < optimizedItems.count - 1 {
            // 合并连续的文本项
            if case .text(let text1, let id1) = optimizedItems[i], case .text(let text2, _) = optimizedItems[i+1] {
                // 检查是否应该合并这两个文本项
                var shouldMerge = true
                
                // 如果后一个文本以换行符开头，需要特殊处理
                // 在列表和段落之间，我们希望保留换行
                // 但在同一个句子被错误分割的情况下，应该合并
                if text2.hasPrefix("\n") {
                    // 检查是否为段落分隔（例如两个空行）或列表项
                    // 在这些情况下，不合并
                    if text2.hasPrefix("\n\n") || text2.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("•") {
                        shouldMerge = false
                    }
                }
                
                if shouldMerge {
                    // 处理空格问题
                    // 如果text1不以空格结尾且text2不以空格开头，添加一个空格
                    var combinedText = text1
                    let needsSpace = !combinedText.hasSuffix(" ") && 
                                    !text2.hasPrefix(" ") && 
                                    !combinedText.isEmpty &&
                                    !combinedText.hasSuffix("\n") &&
                                    !".,:;?!".contains(combinedText.last!)
                    
                    if needsSpace {
                        combinedText += " "
                    }
                    
                    optimizedItems[i] = .text(combinedText + text2, id1)
                    optimizedItems.remove(at: i+1)
                    // 不递增i，因为我们需要检查合并后的项和下一项
                } else {
                    i += 1
                }
            } 
            // 合并连续的markdown项
            else if case .markdown(let md1, let id1) = optimizedItems[i], case .markdown(let md2, _) = optimizedItems[i+1] {
                // 检查是否应该合并这两个markdown项
                var shouldMerge = true
                
                // 如果后一个markdown以换行符开头，需要特殊处理
                if md2.hasPrefix("\n") {
                    // 检查是否为段落分隔（例如两个空行）或列表项
                    // 在这些情况下，不合并
                    if md2.hasPrefix("\n\n") || md2.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("•") {
                        shouldMerge = false
                    }
                }
                
                if shouldMerge {
                    // 处理空格问题
                    // 如果md1不以空格结尾且md2不以空格开头，添加一个空格
                    var combinedMd = md1
                    let needsSpace = !combinedMd.hasSuffix(" ") && 
                                    !md2.hasPrefix(" ") && 
                                    !combinedMd.isEmpty &&
                                    !combinedMd.hasSuffix("\n") &&
                                    !".,:;?!".contains(combinedMd.last!)
                    
                    if needsSpace {
                        combinedMd += " "
                    }
                    
                    optimizedItems[i] = .markdown(combinedMd + md2, id1)
                    optimizedItems.remove(at: i+1)
                    // 不递增i，因为我们需要检查合并后的项和下一项
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        
        // 直接用当前收集的所有项目更新消息
        messages[index].content = .mixedContent(optimizedItems)
        
        // 更新引用
        currentlyGeneratingMessage = messages[index]
        
        // 触发UI更新
        objectWillChange.send()
        
        print("更新消息[ID: \(currentlyGeneratingMessage?.id.uuidString ?? "nil")]，当前项数: \(optimizedItems.count)")
    }
    
    // 发送消息
    func sendMessage() async {
        guard !inputMessage.isEmpty else { return }
        
        // 如果有用户图片，则调用带图片的方法
        if userImage != nil {
            await sendMessageWithImage(prompt: inputMessage)
            inputMessage = ""
            objectWillChange.send()  // 确保UI更新
            return
        }
        
        let messageToSend = inputMessage
        inputMessage = ""
        objectWillChange.send()  // 确保UI更新输入框
        
        // 添加用户消息
        let userMessage = ChatMessage(role: .user, content: .text(messageToSend))
        messages.append(userMessage)
        
        // 创建一个初始的助手消息，使用空的混合内容数组
        let initialAssistantMessage = ChatMessage(role: .assistant, content: .mixedContent([]))
        initialAssistantMessage.isGenerating = true
        currentlyGeneratingMessage = initialAssistantMessage
        messages.append(initialAssistantMessage)
        objectWillChange.send()  // 显式触发UI更新
        
        isLoading = true
        error = nil
        
        do {
            // 使用流式API
            try await geminiService.generateContent(prompt: messageToSend) { [weak self] contentItem in
                guard let self = self else { return }
                
                Task { @MainActor in  // 确保在主线程上处理UI更新
                    // 使用handleContentUpdate处理内容项
                    self.handleContentUpdate(contentItem)
                }
            }
            
            // 完成生成后，设置为非生成状态
            if let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) {
                messages[index].isGenerating = false
                objectWillChange.send()  // 显式触发UI更新
            }
            currentlyGeneratingMessage = nil
            
        } catch {
            self.error = error.localizedDescription
            print("API调用错误: \(error.localizedDescription)")
            
            // 移除正在生成的空消息
            if let lastMessage = messages.last, lastMessage.id == currentlyGeneratingMessage?.id {
                if case .mixedContent(let items) = lastMessage.content, items.isEmpty {
                    messages.removeLast()
                    objectWillChange.send()  // 确保UI更新
                }
            }
            
            // 添加一个友好的错误消息
            let assistantMessage = ChatMessage(role: .assistant, content: .text("很抱歉，处理您的请求时遇到问题。错误信息：\(error.localizedDescription)"))
            messages.append(assistantMessage)
            currentlyGeneratingMessage = nil
            objectWillChange.send()  // 显式触发UI更新
        }
        
        isLoading = false
        objectWillChange.send()  // 确保UI更新加载状态
    }
    
    // 使用示例提示
    func useExamplePrompt(type: ExamplePromptType) {
        // 根据类型选择不同的示例提示
        var prompt = ""
        
        switch type {
        case .imageEdit:
            prompt = """
            **图像编辑助手**
            
            上传一张照片，我可以帮你:
            • 调整亮度和对比度
            • 增强细节和锐度
            • 应用艺术滤镜效果
            • 移除不需要的元素
            
            请上传你想编辑的图片，并告诉我你想要的效果。
            """
            
        case .storyGeneration:
            prompt = """
            **创意故事生成器**
            
            我可以根据你的想法创作引人入胜的故事。
            
            提供以下要素，我将为你创作一个完整的故事:
            • 主角特点（年龄、性格等）
            • 故事发生的背景/时代
            • 核心冲突或挑战
            • 故事主题或你希望传达的信息
            
            请分享你的创意元素！
            """
            
        case .designGeneration:
            prompt = """
            **UI/UX设计助手**
            
            我可以帮你:
            • 生成设计理念和灵感
            • 分析设计趋势和最佳实践
            • 提供色彩搭配建议
            • 评估界面布局和用户体验
            
            请描述你的设计项目和需求，我会提供专业建议。
            """
        }
        
        // 添加AI助手消息
        let assistantMessage = ChatMessage(role: .assistant, content: .markdown(prompt))
        messages.removeAll() // 清除现有消息
        messages.append(assistantMessage)
        objectWillChange.send()
    }
    
    // 处理内容更新
    func handleContentUpdate(_ contentItem: ContentItem) {
        // 确保当前生成消息存在
        guard let currentMessage = currentlyGeneratingMessage else {
            print("没有当前生成的消息，无法处理内容更新")
            return
        }
        
        // 创建混合内容项目数组
        var mixedItems: [MixedContentItem] = []
        
        // 如果消息已有内容，获取现有混合内容
        if case .mixedContent(let existingItems) = currentMessage.content {
            mixedItems = existingItems
        }
        
        // 处理不同类型的内容项
        switch contentItem.type {
        case .text(let text):
            // 跳过空文本
            guard !text.isEmpty else { return }
            
            // 修剪文本开头和结尾的空白字符，但保留内部格式
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }
            
            // 检查文本是否包含Markdown标记
            let containsMarkdown = trimmedText.contains("**") || 
                                   trimmedText.contains("*") || 
                                   trimmedText.contains("##") || 
                                   trimmedText.contains("#") || 
                                   trimmedText.contains("```") || 
                                   trimmedText.contains("`") || 
                                   (trimmedText.contains("[") && trimmedText.contains("]("))
            
            // 如果包含Markdown，则作为markdown类型处理
            if containsMarkdown {
                // 如果是增量文本且已有markdown内容，合并到最后一个markdown项
                if contentItem.isIncremental, 
                   let lastIndex = mixedItems.indices.last,
                   case .markdown(let existingText, let id) = mixedItems[lastIndex] {
                    // 处理合并时的空白字符
                    var combinedText = existingText
                    
                    // 如果现有文本不以空格结尾且新文本不以空格开头，且现有文本不以标点符号结尾，添加一个空格
                    let needsSpace = !combinedText.hasSuffix(" ") && 
                                    !trimmedText.hasPrefix(" ") && 
                                    !combinedText.isEmpty &&
                                    !combinedText.hasSuffix("\n") &&
                                    !".,:;?!".contains(combinedText.last!)
                    
                    if needsSpace {
                        combinedText += " "
                    }
                    
                    // 合并markdown文本，保留原ID
                    mixedItems[lastIndex] = .markdown(combinedText + trimmedText, id)
                } else {
                    // 添加新的markdown项，自动生成新ID
                    mixedItems.append(.markdown(trimmedText))
                }
            } else {
                // 如果是普通文本，则作为text类型处理
                // 如果是增量文本且已有文本内容，合并到最后一个文本项
                if contentItem.isIncremental, 
                   let lastIndex = mixedItems.indices.last,
                   case .text(let existingText, let id) = mixedItems[lastIndex] {
                    // 处理合并时的空白字符
                    var combinedText = existingText
                    
                    // 如果现有文本不以空格结尾且新文本不以空格开头，且现有文本不以标点符号结尾，添加一个空格
                    let needsSpace = !combinedText.hasSuffix(" ") && 
                                    !trimmedText.hasPrefix(" ") && 
                                    !combinedText.isEmpty &&
                                    !combinedText.hasSuffix("\n") &&
                                    !".,:;?!".contains(combinedText.last!)
                    
                    if needsSpace {
                        combinedText += " "
                    }
                    
                    // 合并文本，保留原ID
                    mixedItems[lastIndex] = .text(combinedText + trimmedText, id)
                } else {
                    // 添加新的文本项，自动生成新ID
                    mixedItems.append(.text(trimmedText))
                }
            }
            
        case .markdown(let markdownText):
            // 跳过空markdown
            guard !markdownText.isEmpty else { return }
            
            // 修剪markdown文本开头和结尾的空白字符，但保留内部格式
            let trimmedMarkdown = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMarkdown.isEmpty else { return }
            
            // 如果是增量markdown且已有markdown内容，合并到最后一个markdown项
            if contentItem.isIncremental, 
               let lastIndex = mixedItems.indices.last,
               case .markdown(let existingText, let id) = mixedItems[lastIndex] {
                // 处理合并时的空白字符
                var combinedText = existingText
                
                // 如果现有文本不以空格结尾且新文本不以空格开头，且现有文本不以标点符号结尾，添加一个空格
                let needsSpace = !combinedText.hasSuffix(" ") && 
                                !trimmedMarkdown.hasPrefix(" ") && 
                                !combinedText.isEmpty &&
                                !combinedText.hasSuffix("\n") &&
                                !".,:;?!".contains(combinedText.last!)
                
                if needsSpace {
                    combinedText += " "
                }
                
                // 合并markdown文本，保留原ID
                mixedItems[lastIndex] = .markdown(combinedText + trimmedMarkdown, id)
            } else {
                // 添加新的markdown项，自动生成新ID
                mixedItems.append(.markdown(trimmedMarkdown))
            }
            
        case .image(let imageData):
            if let image = UIImage(data: imageData) {
                // 添加图像项，自动生成新ID
                mixedItems.append(.image(image))
                print("添加图像内容项，大小: \(imageData.count) 字节")
            } else {
                print("警告: 无法从数据创建图像，大小: \(imageData.count) 字节")
            }
        }
        
        // 仅当有内容变化时才更新
        if !mixedItems.isEmpty {
            // 更新消息内容
            updateGeneratingMessageWithItems(mixedItems)
        }
    }
}

// 示例提示类型
enum ExamplePromptType {
    case imageEdit
    case storyGeneration
    case designGeneration
}