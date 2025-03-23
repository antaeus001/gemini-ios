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
            if case .text(let text1, let id1) = optimizedItems[i], case .text(let text2, _) = optimizedItems[i+1] {
                // 如果后一个文本不以换行符开头，合并两个文本项
                if !text2.hasPrefix("\n") {
                    optimizedItems[i] = .text(text1 + text2, id1)
                    optimizedItems.remove(at: i+1)
                    // 不递增i，因为我们需要检查合并后的项和下一项
                } else {
                    i += 1
                }
            } else if case .markdown(let md1, let id1) = optimizedItems[i], case .markdown(let md2, _) = optimizedItems[i+1] {
                // 同样合并连续的markdown项
                if !md2.hasPrefix("\n") {
                    optimizedItems[i] = .markdown(md1 + md2, id1)
                    optimizedItems.remove(at: i+1)
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
            
            // 如果是增量文本且已有文本内容，合并到最后一个文本项
            if contentItem.isIncremental, 
               let lastIndex = mixedItems.indices.last,
               case .text(let existingText, let id) = mixedItems[lastIndex] {
                // 合并文本，保留原ID
                mixedItems[lastIndex] = .text(existingText + text, id)
            } else {
                // 添加新的文本项，自动生成新ID
                mixedItems.append(.text(text))
            }
            
        case .markdown(let markdownText):
            // 跳过空markdown
            guard !markdownText.isEmpty else { return }
            
            // 如果是增量markdown且已有markdown内容，合并到最后一个markdown项
            if contentItem.isIncremental, 
               let lastIndex = mixedItems.indices.last,
               case .markdown(let existingText, let id) = mixedItems[lastIndex] {
                // 合并markdown文本，保留原ID
                mixedItems[lastIndex] = .markdown(existingText + markdownText, id)
            } else {
                // 添加新的markdown项，自动生成新ID
                mixedItems.append(.markdown(markdownText))
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