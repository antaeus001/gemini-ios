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
        let welcomePrompt = "你好，我是基于Gemini 2.0 Flash的AI助手。我可以帮你生成文本和图像。请告诉我你想创建什么？"
        
        let assistantMessage = ChatMessage(role: .assistant, content: .text(welcomePrompt))
        messages.append(assistantMessage)
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
        objectWillChange.send()
    }
    
    // 发送带图片的消息
    func sendMessageWithImage(prompt: String) async {
        guard let image = userImage else { return }
        
        // 添加用户文本消息
        if !prompt.isEmpty {
            let userTextMessage = ChatMessage(role: .user, content: .text(prompt))
            messages.append(userTextMessage)
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
            
            // 保存接收到的内容项
            var mixedItems: [MixedContentItem] = []
            
            // 使用流式API发送带图片的消息
            try await geminiService.generateContentWithImage(prompt: prompt, image: image) { [weak self] contentItem in
                guard let self = self else { return }
                
                if case .text(let newText) = contentItem.type {
                    print("接收到文本: \(newText)")
                    
                    // 添加文本内容项
                    mixedItems.append(.text(newText))
                    
                    // 更新消息
                    self.updateGeneratingMessageWithItems(mixedItems)
                }
                
                if case .image(let imageData) = contentItem.type, let image = UIImage(data: imageData) {
                    // 检查图像是否有效
                    if image.size.width > 10 && image.size.height > 10 {
                        print("接收到有效图像: \(image.size.width) x \(image.size.height)")
                        
                        // 添加图像内容项
                        mixedItems.append(.image(image))
                        
                        // 更新消息
                        self.updateGeneratingMessageWithItems(mixedItems)
                    } else {
                        print("接收到的图像尺寸太小: \(image.size.width) x \(image.size.height)")
                    }
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
        
        // 添加用户消息到UI
        let userMessage = ChatMessage(role: .user, content: .text(prompt))
        messages.append(userMessage)
        
        // 创建一个初始的助手消息，使用空的混合内容数组
        let initialAssistantMessage = ChatMessage(role: .assistant, content: .mixedContent([]))
        initialAssistantMessage.isGenerating = true
        currentlyGeneratingMessage = initialAssistantMessage
        messages.append(initialAssistantMessage)
        objectWillChange.send() // 显式触发UI更新
        
        isLoading = true
        error = nil
        
        do {
            // 重置GeminiService的对话历史
            geminiService.clearChatHistory()
            
            // 保存接收到的内容项
            var mixedItems: [MixedContentItem] = []
            
            // 使用流式API
            try await geminiService.generateContent(prompt: prompt) { [weak self] contentItem in
                guard let self = self else { return }
                
                if case .text(let newText) = contentItem.type {
                    print("接收到文本: \(newText)")
                    
                    // 添加文本内容项
                    mixedItems.append(.text(newText))
                    
                    // 更新消息
                    self.updateGeneratingMessageWithItems(mixedItems)
                }
                
                if case .image(let imageData) = contentItem.type, let image = UIImage(data: imageData) {
                    // 检查图像是否有效
                    if image.size.width > 10 && image.size.height > 10 {
                        print("接收到有效图像: \(image.size.width) x \(image.size.height)")
                        
                        // 添加图像内容项
                        mixedItems.append(.image(image))
                        
                        // 更新消息
                        self.updateGeneratingMessageWithItems(mixedItems)
                    } else {
                        print("接收到的图像尺寸太小: \(image.size.width) x \(image.size.height)")
                    }
                }
            }
            
            // 完成生成后，设置为非生成状态
            if let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) {
                messages[index].isGenerating = false
                objectWillChange.send() // 显式触发UI更新
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
            objectWillChange.send() // 显式触发UI更新
        }
        
        isLoading = false
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
            if case .text(let text1) = optimizedItems[i], case .text(let text2) = optimizedItems[i+1] {
                // 如果后一个文本不以换行符开头，合并两个文本项
                if !text2.hasPrefix("\n") {
                    optimizedItems[i] = .text(text1 + text2)
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
            return
        }
        
        let messageToSend = inputMessage
        inputMessage = ""
        
        // 添加用户消息
        let userMessage = ChatMessage(role: .user, content: .text(messageToSend))
        messages.append(userMessage)
        
        // 创建一个初始的助手消息，使用空的混合内容数组
        let initialAssistantMessage = ChatMessage(role: .assistant, content: .mixedContent([]))
        initialAssistantMessage.isGenerating = true
        currentlyGeneratingMessage = initialAssistantMessage
        messages.append(initialAssistantMessage)
        objectWillChange.send() // 显式触发UI更新
        
        isLoading = true
        error = nil
        
        do {
            // 保存接收到的内容项
            var mixedItems: [MixedContentItem] = []
            
            // 使用流式API
            try await geminiService.generateContent(prompt: messageToSend) { [weak self] contentItem in
                guard let self = self else { return }
                
                if case .text(let newText) = contentItem.type {
                    // 添加文本内容项
                    mixedItems.append(.text(newText))
                    
                    // 更新消息
                    self.updateGeneratingMessageWithItems(mixedItems)
                }
                
                if case .image(let imageData) = contentItem.type, let image = UIImage(data: imageData) {
                    // 检查图像是否有效
                    if image.size.width > 10 && image.size.height > 10 {
                        // 添加图像内容项
                        mixedItems.append(.image(image))
                        
                        // 更新消息
                        self.updateGeneratingMessageWithItems(mixedItems)
                    }
                }
            }
            
            // 完成生成后，设置为非生成状态
            if let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) {
                messages[index].isGenerating = false
                objectWillChange.send() // 显式触发UI更新
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
            objectWillChange.send() // 显式触发UI更新
        }
        
        isLoading = false
    }
    
    // 使用预设的示例提示
    func useExamplePrompt(type: ExamplePromptType) {
        switch type {
        case .imageEdit:
            let prompt = "为羊角面包添加一些巧克力涂层。"
            startImageEditChat(prompt: prompt)
            
        case .storyGeneration:
            let prompt = "生成一个关于白色小山羊在农场冒险的故事，采用3D卡通动画风格。为每个场景生成一张图片。"
            startStoryGenerationChat(prompt: prompt)
            
        case .designGeneration:
            let prompt = """
            生成一个生日贺卡设计，带有美丽的花卉装饰。文字应该很大，内容为：
            "生日快乐！
            祝你的一天充满欢乐、笑声和你最喜欢的一切。
            愿来年成为你最美好的一年，带给你激动人心的冒险和美妙的回忆。
            为你干杯！"
            """
            startDesignGenerationChat(prompt: prompt)
        }
    }
    
    // 处理GeminiService回调的内容更新
    private func handleContentUpdate(contentItem: ContentItem) {
        // 生成新的或更新现有的消息
        guard let lastMessage = messages.last,
              lastMessage.role == .assistant else {
            
            // 创建新的模型消息
            let newMessage: ChatMessage
            
            switch contentItem.type {
            case .text(let text):
                newMessage = ChatMessage(role: .assistant, content: .text(text))
            case .image(let imageData):
                if let image = UIImage(data: imageData) {
                    newMessage = ChatMessage(role: .assistant, content: .image(image))
                } else {
                    print("无法从数据创建UIImage，跳过此内容项")
                    return
                }
            }
            
            messages.append(newMessage)
            return
        }
        
        // 更新现有的助手消息
        switch (lastMessage.content, contentItem.type) {
        case (.text(let existingText), .text(let newText)):
            // 检查是否是增量更新
            if contentItem.isIncremental {
                // 只追加新的文本，不替换整个消息
                lastMessage.content = .text(existingText + newText)
            } else {
                // 完全替换内容
                lastMessage.content = .text(newText)
            }
            
        case (.image, .text(let text)):
            // 从图像转换为文本 - 应该很少发生
            lastMessage.content = .text(text)
        
        case (.text, .image(let imageData)):
            // 从文本转换为图像 - 应该很少发生
            if let image = UIImage(data: imageData) {
                lastMessage.content = .image(image)
            }
        
        case (.image, .image(let imageData)):
            // 更新图像
            if let image = UIImage(data: imageData) {
                lastMessage.content = .image(image)
            }
        
        case (.mixedContent(var items), .text(let newText)):
            // 更新混合内容的最后一个文本项或添加新的文本项
            if let lastIndex = items.indices.last,
               case .text(let existingText) = items[lastIndex], 
               contentItem.isIncremental {
                // 如果是增量更新并且最后一项是文本，则追加
                items[lastIndex] = .text(existingText + newText)
            } else {
                // 否则添加新的文本项
                items.append(.text(newText))
            }
            lastMessage.content = .mixedContent(items)
        
        case (.mixedContent(var items), .image(let imageData)):
            // 添加新的图像项
            if let image = UIImage(data: imageData) {
                items.append(.image(image))
                lastMessage.content = .mixedContent(items)
            }
        
        default:
            // 将现有内容转换为混合内容
            var mixedItems: [MixedContentItem] = []
            
            // 首先添加现有内容
            switch lastMessage.content {
            case .text(let text):
                mixedItems.append(.text(text))
            case .image(let image):
                mixedItems.append(.image(image))
            case .mixedContent(let items):
                mixedItems.append(contentsOf: items)
            }
            
            // 然后添加新内容
            switch contentItem.type {
            case .text(let text):
                mixedItems.append(.text(text))
            case .image(let imageData):
                if let image = UIImage(data: imageData) {
                    mixedItems.append(.image(image))
                }
            }
            
            lastMessage.content = .mixedContent(mixedItems)
        }
    }
}

// 示例提示类型
enum ExamplePromptType {
    case imageEdit
    case storyGeneration
    case designGeneration
}