import Foundation
import SwiftUI
import UIKit

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var userImages: [UIImage] = [] // 修改为数组以支持多张图片
    
    var currentlyGeneratingMessage: ChatMessage? = nil
    let geminiService = GeminiService.shared
    var chatListId: String // 保存当前聊天列表ID
    
    // 初始化方法
    init() {
        print("ChatViewModel初始化 - 使用简化的文本合并逻辑")
        // 生成一个唯一的聊天列表ID
        self.chatListId = UUID().uuidString
        // 设置当前聊天列表ID
        geminiService.setChatList(id: self.chatListId)
        print("已设置聊天列表ID: \(chatListId)")
        // 在初始化时自动启动欢迎对话
        startWelcomeChat()
    }
    
    // 添加创建新聊天的方法
    func createNewChat() {
        // 清除现有消息
        messages.removeAll()
        // 生成新的聊天列表ID
        chatListId = UUID().uuidString
        // 设置新的聊天列表ID
        geminiService.setChatList(id: chatListId)
        print("已创建新聊天，ID: \(chatListId)")
        // 启动欢迎对话
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
        
        print("创建欢迎消息，使用Markdown格式: \(welcomePrompt)")
        
        // 直接创建特定内容的欢迎消息
        let welcomeMessage = """
        # 欢迎使用Gemini图像处理助手
        
        请您上传您想要调整的图片。
        
        **一旦您上传图片，我会尝试进行以下调整：**
        
        * 提高亮度：使图像整体看起来更明亮
        * 增加对比度：拉大图像中亮部和暗部的差异，增强层次感和立体感
        
        请您耐心等待我处理完成后的效果。
        """
        
        // 确保使用.markdown内容类型
        let assistantMessage = ChatMessage(role: .assistant, content: .markdown(welcomeMessage))
        messages.append(assistantMessage)
        
        // 打印所有消息的类型
        print("当前所有消息：")
        for (index, msg) in messages.enumerated() {
            print("消息 \(index): 角色=\(msg.role), 类型=\(type(of: msg.content))")
            switch msg.content {
            case .text(let text):
                print(" - 文本内容: \(text.prefix(50))...")
            case .markdown(let md):
                print(" - Markdown内容: \(md.prefix(50))...")
            case .mixedContent(let items):
                print(" - 混合内容，项目数: \(items.count)")
            case .image:
                print(" - 图像内容")
            case .imageUrl(let url):
                print(" - 图像URL内容: \(url)")
            }
        }
        
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
        self.userImages.append(image)
        
        // 不再立即添加图片到聊天界面，而是等到用户点击发送按钮时才添加
        objectWillChange.send()  // 确保触发UI更新
    }
    
    // 上传用户选择的图片
    func uploadUserImage() async -> String? {
        guard let image = userImages.first else { return nil }
        
        // 设置加载状态
        isLoading = true
        error = nil
        
        // 使用defer确保在函数结束时重置状态
        defer {
            isLoading = false
            objectWillChange.send()
        }
        
        do {
            // 上传图片并获取URL
            let imageUrl = try await ImageUploader.shared.uploadImage(image)
            print("图片上传成功，URL: \(imageUrl)")
            return imageUrl
        } catch {
            self.error = "图片上传失败: \(error.localizedDescription)"
            print("图片上传失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // 发送带图片URL的消息
    func sendMessageWithImageUrl(prompt: String, imageUrl: String) async throws {
        // 确保设置了当前聊天列表ID
        geminiService.setChatList(id: chatListId)
        
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
            // 使用URL发送请求
            try await geminiService.generateContentWithImageUrl(prompt: prompt, imageUrl: imageUrl) { [weak self] contentItem in
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
            userImages.removeAll()
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
    
    // 发送带多张图片的消息（支持单张和多张图片）
    func sendMessageWithImages(prompt: String, savedImages: [UIImage], useImageUpload: Bool = true) async {
        guard !savedImages.isEmpty else { return }
        
        // 确保设置了当前聊天列表ID
        geminiService.setChatList(id: chatListId)
        
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
            // 如果需要上传图片，先上传获取URLs
            if useImageUpload {
                // 处理所有图片，获取URL列表
                var imageUrls: [String] = []
                
                for (index, image) in savedImages.enumerated() {
                    do {
                        let imageUrl = try await ImageUploader.shared.uploadImage(image)
                        imageUrls.append(imageUrl)
                        print("已获取图片\(index+1)URL: \(imageUrl)")
                    } catch {
                        print("上传图片\(index+1)失败: \(error.localizedDescription)")
                        // 继续处理其他图片，即使有一些上传失败
                    }
                }
                
                if imageUrls.isEmpty {
                    throw NSError(domain: "ChatViewModel", code: 1001, userInfo: [NSLocalizedDescriptionKey: "所有图片上传失败"])
                }
                
                // 使用URLs列表发送请求
                try await geminiService.generateContentWithMultipleImageUrls(prompt: prompt, imageUrls: imageUrls) { [weak self] contentItem in
                    guard let self = self else { return }
                    
                    // 捕获任何处理过程中的错误
                    do {
                        // 使用handleContentUpdate处理内容项
                        self.handleContentUpdate(contentItem)
                    } catch {
                        print("处理内容更新时出错: \(error.localizedDescription)")
                    }
                }
            } else {
                // 使用base64方式（不推荐使用此方式）- 处理所有图片
                try await geminiService.generateContentWithMultipleImages(prompt: prompt, images: savedImages, useImageUpload: false) { [weak self] contentItem in
                    guard let self = self else { return }
                    
                    // 捕获任何处理过程中的错误
                    do {
                        // 使用handleContentUpdate处理内容项
                        self.handleContentUpdate(contentItem)
                    } catch {
                        print("处理内容更新时出错: \(error.localizedDescription)")
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
            userImages.removeAll()
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
    
    // 发送消息
    func sendMessage() async {
        guard !inputMessage.isEmpty || !userImages.isEmpty else { return }
        
        // 确保设置了当前聊天列表ID
        geminiService.setChatList(id: chatListId)
        
        // 保存图片的临时变量
        let tempImages = userImages
        // 保存输入框内容
        let messageToSend = inputMessage
        
        // 立即清空输入框，确保UI立刻更新
        inputMessage = ""
        objectWillChange.send()  // 添加这一行确保UI立即更新输入框
        
        // 如果有用户图片，先将图片添加到聊天列表
        for image in tempImages {
            let userImageMessage = ChatMessage(role: .user, content: .image(image, UUID()))
            messages.append(userImageMessage)
        }
        
        // 在这里立即清除userImages，使预览区域消失
        userImages.removeAll()
        objectWillChange.send()  // 确保UI更新
        
        // 如果有用户图片，则调用带图片的方法
        if !tempImages.isEmpty {
            await sendMessageWithImages(prompt: messageToSend, savedImages: tempImages)
            objectWillChange.send()  // 确保UI更新
            return
        }
        
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
            
            // 只修剪文本开头和结尾的空白字符，绝对保留内部换行符和格式
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            guard !trimmedText.isEmpty else { return }
            
            print("接收到文本: '\(trimmedText)'")
            
            // 检查是否包含markdown标记
            let containsMarkdown = trimmedText.contains("**") || 
                                   trimmedText.contains("*") || 
                                   trimmedText.contains("#") || 
                                   trimmedText.contains("```") ||
                                   trimmedText.contains("•") || 
                                   trimmedText.contains("- ") || 
                                   trimmedText.contains("* ")
            
            // 直接合并任何文本，无条件，并保留所有换行符
            if let lastIndex = mixedItems.indices.last {
                if case .text(let existingText, let id) = mixedItems[lastIndex] {
                    // 直接合并文本，保留所有换行符和格式
                    let newText = existingText + trimmedText
                    // 如果检测到markdown标记，转换为markdown类型
                    if containsMarkdown {
                        mixedItems[lastIndex] = .markdown(newText, id)
                        print("升级并合并到markdown: '\(existingText)' + '\(trimmedText)'")
                    } else {
                        mixedItems[lastIndex] = .text(newText, id)
                        print("已合并到现有文本: '\(existingText)' + '\(trimmedText)'")
                    }
                } else if case .markdown(let existingText, let id) = mixedItems[lastIndex] {
                    // 直接合并到markdown
                    let newText = existingText + trimmedText
                    mixedItems[lastIndex] = .markdown(newText, id)
                    print("已合并到现有markdown: '\(existingText)' + '\(trimmedText)'")
                } else {
                    // 创建新项
                    if containsMarkdown {
                        mixedItems.append(.markdown(trimmedText))
                        print("添加为新markdown项: '\(trimmedText)'")
                    } else {
                        mixedItems.append(.text(trimmedText))
                        print("添加为新文本项: '\(trimmedText)'")
                    }
                }
            } else {
                // 创建第一个项
                if containsMarkdown {
                    mixedItems.append(.markdown(trimmedText))
                    print("添加为第一个markdown项: '\(trimmedText)'")
                } else {
                    mixedItems.append(.text(trimmedText))
                    print("添加为第一个文本项: '\(trimmedText)'")
                }
            }
            
        case .markdown(let markdownText):
            // 跳过空markdown
            guard !markdownText.isEmpty else { return }
            
            // 只修剪markdown文本开头和结尾的空白字符，绝对保留内部换行和格式
            let trimmedMarkdown = markdownText.trimmingCharacters(in: .whitespaces)
            guard !trimmedMarkdown.isEmpty else { return }
            
            print("接收到markdown: '\(trimmedMarkdown)'")
            
            // 直接合并任何markdown，保留所有换行符
            if let lastIndex = mixedItems.indices.last {
                if case .markdown(let existingText, let id) = mixedItems[lastIndex] {
                    // 直接合并markdown
                    let newText = existingText + trimmedMarkdown
                    mixedItems[lastIndex] = .markdown(newText, id)
                    print("已合并到现有markdown: '\(existingText)' + '\(trimmedMarkdown)'")
                } else if case .text(let existingText, let id) = mixedItems[lastIndex] {
                    // 直接合并到文本并升级为markdown
                    let newText = existingText + trimmedMarkdown
                    mixedItems[lastIndex] = .markdown(newText, id)
                    print("升级并合并到markdown: '\(existingText)' + '\(trimmedMarkdown)'")
                } else {
                    // 创建新markdown项
                    mixedItems.append(.markdown(trimmedMarkdown))
                    print("添加为新markdown项: '\(trimmedMarkdown)'")
                }
            } else {
                // 创建新markdown项
                mixedItems.append(.markdown(trimmedMarkdown))
                print("添加为第一个markdown项: '\(trimmedMarkdown)'")
            }
            
        case .image(let imageData):
            if let image = UIImage(data: imageData) {
                // 添加图像项，自动生成新ID
                mixedItems.append(.image(image, UUID()))
                print("添加图像内容项，大小: \(imageData.count) 字节")
            } else {
                print("警告: 无法从数据创建图像，大小: \(imageData.count) 字节")
            }
            
        case .imageUrl(let url):
            // 添加图像URL项，自动生成新ID
            mixedItems.append(.imageUrl(url, UUID()))
            print("添加图像URL内容项: \(url)")
        }
        
        // 仅当有内容变化时才更新
        if !mixedItems.isEmpty {
            // 保存所有修改后的内容
            updateGeneratingMessageWithItems(mixedItems)
        }
    }
    
    // 更新当前生成的消息
    private func updateGeneratingMessageWithItems(_ items: [MixedContentItem]) {
        guard let index = messages.firstIndex(where: { $0.id == currentlyGeneratingMessage?.id }) else {
            print("未找到当前生成的消息，无法更新")
            return
        }
        
        // 直接用当前收集的所有项目更新消息
        messages[index].content = .mixedContent(items)
        
        // 更新引用
        currentlyGeneratingMessage = messages[index]
        
        // 触发UI更新
        objectWillChange.send()
        
        print("更新消息[ID: \(currentlyGeneratingMessage?.id.uuidString ?? "nil")]，当前项数: \(items.count)")
    }
    
    // 使用示例提示
    func useExamplePrompt(type: PromptExampleType) {
        switch type {
        case .imageEdit:
            inputMessage = "生成一个未来城市的图像，它拥有飞行汽车和高耸入云的摩天大楼。"
        case .storyGeneration:
            inputMessage = "写一个关于探索外星球的短篇科幻故事。"
        case .designGeneration:
            inputMessage = "创建一个现代简约风格的网站首页设计，针对一家高端咖啡品牌。"
        }
        
        // 立即发送示例提示
        Task {
            await sendMessage()
        }
    }
    
    // 清除所有消息，开始新会话
    func clearMessages() {
        self.messages = []
        self.currentlyGeneratingMessage = nil
        self.error = nil
        // 生成新的聊天列表ID
        chatListId = UUID().uuidString
        // 设置新的聊天列表ID
        geminiService.setChatList(id: chatListId)
        print("已清除所有消息，准备开始新会话，新聊天列表ID: \(chatListId)")
    }
    
    // 在ChatViewModel类中添加新方法
    func addImageUrlToChat(imageUrl: String) {
        // 确保设置了当前聊天列表ID
        geminiService.setChatList(id: chatListId)
        
        // 创建包含URL图片的用户消息
        let userMessage = ChatMessage(role: .user, content: .imageUrl(imageUrl))
        messages.append(userMessage)
        objectWillChange.send()  // 确保触发UI更新
    }
    
    // 在ChatViewModel类中添加新方法
    func loadImageFromUrl(imageUrl: String) async {
        // 确保URL有效
        guard let url = URL(string: imageUrl) else {
            print("图片URL无效: \(imageUrl)")
            return
        }
        
        do {
            // 使用URLSession加载图片
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // 检查HTTP响应状态码
            if let httpResponse = response as? HTTPURLResponse, 
               !(200...299).contains(httpResponse.statusCode) {
                print("加载图片失败，HTTP状态码: \(httpResponse.statusCode)")
                return
            }
            
            // 从数据创建图像
            if let image = UIImage(data: data) {
                // 在主线程更新UI
                await MainActor.run {
                    // 将图片添加到聊天界面
                    let assistantMessage = ChatMessage(role: .assistant, content: .image(image, UUID()))
                    messages.append(assistantMessage)
                    objectWillChange.send()  // 确保触发UI更新
                }
            } else {
                print("无法从数据创建图像")
            }
        } catch {
            print("加载图片出错: \(error.localizedDescription)")
        }
    }
    
    // 通用的生成内容聊天方法
    func startGenerationChat(prompt: String) async {
        // 确保设置了当前聊天列表ID
        geminiService.setChatList(id: chatListId)
        
        // 如果有用户图片，则调用带图片的方法
        if !userImages.isEmpty {
            // 保存图片引用
            let tempImages = userImages
            // 立即清除图片预览
            userImages.removeAll()
            objectWillChange.send()
            
            // 使用保存的图片引用
            await sendMessageWithImages(prompt: prompt, savedImages: tempImages)
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
            // 重置GeminiService的对话历史（因为这是开始新的对话）
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
}

// 示例提示类型
enum PromptExampleType {
    case imageEdit
    case storyGeneration
    case designGeneration
}
