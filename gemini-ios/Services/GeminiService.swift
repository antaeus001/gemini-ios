import Foundation
import UIKit

// 内容项类型定义
enum ContentItemType {
    case text(String)
    case image(Data)
    case markdown(String)
}

// 内容项结构
struct ContentItem: Identifiable {
    var id = UUID()
    let type: ContentItemType
    let timestamp: Date
    let isIncremental: Bool
    
    init(type: ContentItemType, timestamp: Date = Date(), isIncremental: Bool = false) {
        self.type = type
        self.timestamp = timestamp
        self.isIncremental = isIncremental
    }
}

// 内容项更新处理器类型
typealias ContentUpdateHandler = (ContentItem) -> Void

// 聊天消息内容类型
enum ChatMessageContent {
    case text(String)
    case image(UIImage)
    case mixedContent([MixedContentItem])
}

// Gemini聊天消息
struct GeminiChatMessage {
    let role: String
    let parts: [[String: Any]]
    let contentItems: [ContentItem]?
    
    init(role: String, parts: [[String: Any]], contentItems: [ContentItem]? = nil) {
        self.role = role
        self.parts = parts
        self.contentItems = contentItems
    }
}

class GeminiService {
    // 共享实例
    static let shared = GeminiService()
    
    // API配置
    private let baseUrlString = "https://huohuaai.com/v1/gemini/image-generation"
    private let modelName = "gemini-2.0-flash-exp-image-generation"
    private let geminiApiKey = "AIzaSyDtaceYdTFwn4H0RIA6u5fHS-BDUJoEK04"
    
    // 创建自定义URLSession配置，设置较长的超时时间
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600 // 请求超时时间5分钟
        config.timeoutIntervalForResource = 600 // 资源下载超时时间5分钟
        return URLSession(configuration: config)
    }()
    
    // 状态变量
    var chatHistory: [GeminiChatMessage] = []
    var currentChatListId: String? = nil // 当前聊天列表的ID
    var chatLists: [String: [GeminiChatMessage]] = [:] // 所有聊天列表
    var currentContentItems: [ContentItem] = []
    var isStreamActive: Bool = false
    var currentUpdateHandler: ContentUpdateHandler? = nil
    private var chunkCounter: Int = 0
    private var completeStreamLog: String = ""
    private var streamStartTime: Date = Date()
    
    // 设置当前聊天列表
    func setChatList(id: String) {
        currentChatListId = id
        if chatLists[id] == nil {
            chatLists[id] = []
        }
        // 将当前聊天列表的消息加载到chatHistory
        chatHistory = chatLists[id] ?? []
        print("切换到聊天列表: \(id), 消息数量: \(chatHistory.count)")
    }
    
    // 清除当前聊天列表
    func clearCurrentChatList() {
        if let id = currentChatListId {
            chatLists[id] = []
            chatHistory = []
            currentContentItems = []
            print("已清空当前聊天列表: \(id)")
        } else {
            print("警告: 没有设置当前聊天列表ID")
        }
    }
    
    // 清除聊天历史
    func clearChatHistory() {
        chatHistory.removeAll()
        if let id = currentChatListId {
            chatLists[id] = []
        }
        currentContentItems.removeAll()
    }
    
    // 开始新的会话
    func startNewSession() {
        print("开始新会话，清空之前的聊天历史")
        chatHistory.removeAll()
        if let id = currentChatListId {
            chatLists[id] = []
        }
        currentContentItems.removeAll()
    }
    
    // 停止流式生成
    func stopStream() {
        isStreamActive = false
    }
    
    // 保存流式响应日志到文件
    private func saveStreamLogToFile() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: streamStartTime)
        let logFilePath = documentsPath.appendingPathComponent("gemini_stream_log_\(dateString).txt")
        
        do {
            try completeStreamLog.write(to: logFilePath, atomically: true, encoding: .utf8)
            print("完整流式响应日志已保存到: \(logFilePath.path)")
        } catch {
            print("保存流式响应日志失败: \(error.localizedDescription)")
        }
    }
    
    // 打印流式响应内容
    private func printResponseContent(_ content: String, type: String) {
        let border = String(repeating: "=", count: 60)
        let formattedContent = """
        \(border)
        [流式响应块 #\(chunkCounter)] - 类型: \(type)
        \(border)
        \(content)
        \(border)
        
        """
        print(formattedContent)
        
        // 添加到完整日志
        let logEntry = """
        
        --- 块 #\(chunkCounter) (\(type)) ---
        \(content)
        """
        completeStreamLog += logEntry
        
        chunkCounter += 1
    }
    
    // 解析SERVER-SENT EVENT行
    private func parseSSELine(_ line: String) -> (String, String)? {
        if line.isEmpty { return nil }
        
        let components = line.components(separatedBy: ": ")
        if components.count < 2 { return nil }
        
        let event = components[0]
        let data = components[1...].joined(separator: ": ")
        
        return (event, data)
    }
    
    // 处理SSE行
    private func handleSSELine(_ line: String, modelParts: inout [[String: Any]]) async {
        // 打印原始SSE行
        print("收到SSE行: \(line)")
        
        if line.hasPrefix("data:") {
            let dataContent = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if dataContent == "[DONE]" {
                print("流式响应完成: [DONE]")
                isStreamActive = false
                return
            }
            
            // 尝试解析JSON数据
            if let data = dataContent.data(using: .utf8),
               let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("解析SSE数据成功: \(responseDict.keys)")
                await processResponseData(responseDict, modelParts: &modelParts)
            } else {
                print("无法解析SSE数据: \(dataContent)")
            }
        }
    }
    
    // 处理API响应数据
    private func processResponseData(_ responseDict: [String: Any], modelParts: inout [[String: Any]]) async {
        print("收到响应数据: \(responseDict)")
        
        // 支持驼峰命名的字段
        var candidates: [[String: Any]]? = nil
        
        // 检查候选项字段（支持驼峰命名和下划线命名）
        if let candidatesData = responseDict["candidates"] as? [[String: Any]] {
            candidates = candidatesData
        }
        
        guard let candidates = candidates,
              candidates.count > 0 else {
            print("响应中未找到候选项: \(responseDict)")
            return
        }
        
        // 检查内容字段（支持驼峰命名）
        guard let content = candidates[0]["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            print("不完整或无效的响应: \(responseDict)")
            return
        }
        
        // 处理部分数据
        for part in parts {
            // 添加部分到模型部分
            modelParts.append(part)
            
            // 处理文本内容
            if let text = part["text"] as? String, !text.isEmpty {
                printResponseContent(text, type: "文本")
                
                // 检查文本是否包含Markdown格式
                let markdownPatterns = [
                    "^#+ ", // 标题
                    "```", // 代码块
                    "`[^`]+`", // 行内代码
                    "\\*\\*[^\\*]+\\*\\*", // 粗体
                    "_[^_]+_", // 斜体
                    "\\*[^\\*]+\\*", // 斜体（另一种表示）
                    "^>", // 引用
                    "^- ", // 无序列表
                    "^\\d+\\. ", // 有序列表
                    "\\[.+\\]\\(.+\\)", // 链接
                    "!\\[.+\\]\\(.+\\)", // 图片
                    "\\|[^\\|]+\\|", // 表格
                    "^----*$" // 分隔线
                ]
                
                // 使用正则表达式检查文本是否包含Markdown格式
                let containsMarkdown = markdownPatterns.contains { pattern in
                    if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                        let range = NSRange(location: 0, length: text.utf16.count)
                        return regex.firstMatch(in: text, options: [], range: range) != nil
                    }
                    return false
                }

                // 完全简化文本处理逻辑，保留换行符
                // 无论是markdown还是普通文本，如果增量内容直接追加，保留所有格式
                if let lastIndex = currentContentItems.indices.last {
                    if case .markdown(let lastText) = currentContentItems[lastIndex].type {
                        // 更新服务器端记录，保留所有换行和格式
                        let updatedText = lastText + text
                        currentContentItems[lastIndex] = ContentItem(type: .markdown(updatedText), timestamp: Date())
                        
                        // 发送增量文本给UI更新，标记为增量
                        let incrementalItem = ContentItem(type: .markdown(text), timestamp: Date(), isIncremental: true)
                        await MainActor.run {
                            print("发送增量markdown: '\(text)'")
                            self.currentUpdateHandler?(incrementalItem)
                        }
                    } else if case .text(let lastText) = currentContentItems[lastIndex].type {
                        // 检查是否有markdown标记
                        let containsMarkdown = containsMarkdown || text.contains("**") || 
                                              text.contains("*") || text.contains("#") || 
                                              text.contains("```") || text.contains("- ") || 
                                              text.contains("* ") || text.contains("•")
                        
                        if containsMarkdown {
                            // 如果发现markdown标记，将整个内容升级为markdown
                            let updatedText = lastText + text
                            currentContentItems[lastIndex] = ContentItem(type: .markdown(updatedText), timestamp: Date())
                            
                            // 发送增量文本，但标记为markdown类型
                            let incrementalItem = ContentItem(type: .markdown(text), timestamp: Date(), isIncremental: true)
                            await MainActor.run {
                                print("发现markdown标记，升级并发送增量markdown: '\(text)'")
                                self.currentUpdateHandler?(incrementalItem)
                            }
                        } else {
                            // 更新服务器端记录，保留所有换行和格式
                            let updatedText = lastText + text
                            currentContentItems[lastIndex] = ContentItem(type: .text(updatedText), timestamp: Date())
                            
                            // 发送增量文本给UI更新
                            let incrementalItem = ContentItem(type: .text(text), timestamp: Date(), isIncremental: true)
                            await MainActor.run {
                                print("发送增量文本: '\(text)'")
                                self.currentUpdateHandler?(incrementalItem)
                            }
                        }
                    } else {
                        // 创建新的内容项
                        let contentItem = containsMarkdown ? 
                            ContentItem(type: .markdown(text), timestamp: Date()) :
                            ContentItem(type: .text(text), timestamp: Date())
                        currentContentItems.append(contentItem)
                        await MainActor.run {
                            print("发送新内容项: '\(text)'")
                            self.currentUpdateHandler?(contentItem)
                        }
                    }
                } else {
                    // 创建第一个内容项
                    let contentItem = containsMarkdown ? 
                        ContentItem(type: .markdown(text), timestamp: Date()) :
                        ContentItem(type: .text(text), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        print("发送第一个内容项: '\(text)'")
                        self.currentUpdateHandler?(contentItem)
                    }
                }
            }
            
            // 处理内联数据（图像）
            if let inlineData = part["inline_data"] as? [String: Any],
               let data = inlineData["data"] as? String,
               let mimeType = inlineData["mime_type"] as? String,
               mimeType.hasPrefix("image/") {
                
                printResponseContent("图像内容: MimeType=\(mimeType), 数据长度=\(data.count)字节", type: "图像")
                
                // 检查数据是否为URL
                if data.hasPrefix("http") {
                    // 是URL路径，确保使用https
                    var imageUrl = data
                    if data.hasPrefix("http:") {
                        imageUrl = "https:" + data.dropFirst(5)
                    }
                    
                    print("图像URL: \(imageUrl)")
                    
                    do {
                        // 下载图片并转换为Base64
                        let base64Data = try await downloadImageAndConvertToBase64(from: imageUrl)
                        
                        // 创建图片内容项
                        if let imageData = Data(base64Encoded: base64Data) {
                            let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                            currentContentItems.append(contentItem)
                            await MainActor.run {
                                self.currentUpdateHandler?(contentItem)
                            }
                        }
                    } catch {
                        print("下载或处理图片时出错: \(error.localizedDescription)")
                        // 如果下载失败，仍然创建Markdown格式的图片内容作为备选
                    let markdownImage = "![生成的图像](\(imageUrl))"
                    let contentItem = ContentItem(type: .markdown(markdownImage), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        self.currentUpdateHandler?(contentItem)
                        }
                    }
                } else if let imageData = Data(base64Encoded: data) {
                    // 兼容旧格式：base64编码的图像数据
                    print("成功解码图像数据，大小: \(imageData.count)字节")
                    let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        self.currentUpdateHandler?(contentItem)
                    }
                } else {
                    print("无法解码图像数据: 既不是有效URL也不是Base64数据")
                }
            }
            // 处理内联数据的另一种形式（兼容不同API版本）
            else if let inlineData = part["inlineData"] as? [String: Any],
                    let data = inlineData["data"] as? String,
                    let mimeType = inlineData["mimeType"] as? String,
                    mimeType.hasPrefix("image/") {
                
                printResponseContent("图像内容(旧格式): MimeType=\(mimeType), 数据长度=\(data.count)字节", type: "图像")
                
                // 检查数据是否为URL
                if data.hasPrefix("http") {
                    // 是URL路径，确保使用https
                    var imageUrl = data
                    if data.hasPrefix("http:") {
                        imageUrl = "https:" + data.dropFirst(5)
                    }
                    
                    print("图像URL: \(imageUrl)")
                    
                    do {
                        // 下载图片并转换为Base64
                        let base64Data = try await downloadImageAndConvertToBase64(from: imageUrl)
                        
                        // 创建图片内容项
                        if let imageData = Data(base64Encoded: base64Data) {
                            let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                            currentContentItems.append(contentItem)
                            await MainActor.run {
                                self.currentUpdateHandler?(contentItem)
                            }
                        }
                    } catch {
                        print("下载或处理图片时出错: \(error.localizedDescription)")
                        // 如果下载失败，仍然创建Markdown格式的图片内容作为备选
                        let markdownImage = "![生成的图像](\(imageUrl))"
                        let contentItem = ContentItem(type: .markdown(markdownImage), timestamp: Date())
                        currentContentItems.append(contentItem)
                        await MainActor.run {
                            self.currentUpdateHandler?(contentItem)
                        }
                    }
                } else if let imageData = Data(base64Encoded: data) {
                    // 兼容旧格式：base64编码的图像数据
                    print("成功解码图像数据，大小: \(imageData.count)字节")
                    let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        self.currentUpdateHandler?(contentItem)
                    }
                } else {
                    print("无法解码图像数据: 既不是有效URL也不是Base64数据")
                }
            }
            // 处理文件数据（来自fileData的图像）
            else if let fileData = part["fileData"] as? [String: Any],
                    let fileUri = fileData["fileUri"] as? String,
                    let mimeType = fileData["mimeType"] as? String,
                    mimeType.hasPrefix("image/") {
                
                printResponseContent("图像文件内容: MimeType=\(mimeType), URI=\(fileUri.prefix(50))...", type: "图像文件")
                
                // 处理文件URI（可能是图片URL或data:URL）
                if fileUri.hasPrefix("data:") {
                    // 处理内联的data:URL格式
                    if let base64Data = extractBase64FromDataURL(fileUri),
                       let imageData = Data(base64Encoded: base64Data) {
                        print("从data:URL格式成功提取图像数据，大小: \(imageData.count)字节")
                        let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                        currentContentItems.append(contentItem)
                        await MainActor.run {
                            self.currentUpdateHandler?(contentItem)
                        }
                    } else {
                        print("无法从data:URL格式提取有效的图像数据")
                    }
                } else if fileUri.hasPrefix("${FILE_URI_") {
                    print("检测到占位符文件URI: \(fileUri)")
                    
                    // 为占位符创建一个提示，表明图像将在此处生成
                    let placeholderText = "【这里将显示生成的图像：\(fileUri)】"
                    let contentItem = ContentItem(type: .markdown(placeholderText), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        self.currentUpdateHandler?(contentItem)
                    }
                } else if fileUri.hasPrefix("http") {
                    // 是URL路径，确保使用https
                    var imageUrl = fileUri
                    if fileUri.hasPrefix("http:") {
                        imageUrl = "https:" + fileUri.dropFirst(5)
                    }
                    
                    print("图像文件URL: \(imageUrl)")
                    
                    do {
                        // 下载图片并转换为Base64
                        let base64Data = try await downloadImageAndConvertToBase64(from: imageUrl)
                        
                        // 创建图片内容项
                        if let imageData = Data(base64Encoded: base64Data) {
                            let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                            currentContentItems.append(contentItem)
                            await MainActor.run {
                                self.currentUpdateHandler?(contentItem)
                            }
                        }
                    } catch {
                        print("下载或处理图片时出错: \(error.localizedDescription)")
                        // 如果下载失败，仍然创建Markdown格式的图片内容作为备选
                        let markdownImage = "![生成的图像](\(imageUrl))"
                        let contentItem = ContentItem(type: .markdown(markdownImage), timestamp: Date())
                        currentContentItems.append(contentItem)
                        await MainActor.run {
                            self.currentUpdateHandler?(contentItem)
                        }
                    }
                } else {
                    print("无法处理的文件URI格式: \(fileUri)")
                }
            }
        }
    }
    
    // 下载图片并转换为Base64
    private func downloadImageAndConvertToBase64(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "无效的图片URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return data.base64EncodedString()
    }
    
    // 从data:URL中提取base64数据
    private func extractBase64FromDataURL(_ dataURL: String) -> String? {
        let components = dataURL.components(separatedBy: ",")
        if components.count >= 2 {
            return components[1]
        }
        return nil
    }
    
    // 合并连续的model消息
    private func consolidateModelMessages(_ history: [GeminiChatMessage]) -> [GeminiChatMessage] {
        var consolidatedHistory: [GeminiChatMessage] = []
        var currentModelParts: [[String: Any]] = []
        var currentModelContentItems: [ContentItem] = []
        
        for (index, message) in history.enumerated() {
            if message.role == "model" {
                // 收集model消息的parts
                currentModelParts.append(contentsOf: message.parts)
                if let contentItems = message.contentItems {
                    currentModelContentItems.append(contentsOf: contentItems)
                }
                
                // 如果下一条消息不是model或者这是最后一条消息，合并所有收集的parts
                if index == history.count - 1 || history[index + 1].role != "model" {
                    if !currentModelParts.isEmpty {
                        let consolidatedMessage = GeminiChatMessage(
                            role: "model",
                            parts: currentModelParts,
                            contentItems: currentModelContentItems
                        )
                        consolidatedHistory.append(consolidatedMessage)
                        currentModelParts = []
                        currentModelContentItems = []
                    }
                }
            } else {
                // 非model消息直接添加
                consolidatedHistory.append(message)
            }
        }
        
        return consolidatedHistory
    }
    
    // 准备请求内容，替换INSERT_INPUT_HERE占位符
    private func prepareRequestContents(_ history: [GeminiChatMessage], userPrompt: String) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        
        print("准备请求内容，历史消息数: \(history.count), 用户提示: \(userPrompt)")
        
        for (index, message) in history.enumerated() {
            var messageParts = message.parts
            
            // 如果是最后一条用户消息，替换INSERT_INPUT_HERE占位符
            if index == history.count - 1 && message.role == "user" {
                var newParts: [[String: Any]] = []
                
                for part in messageParts {
                    if let text = part["text"] as? String, text == "INSERT_INPUT_HERE" {
                        newParts.append(["text": userPrompt])
                        print("替换了INSERT_INPUT_HERE占位符为: \(userPrompt)")
                    } else {
                        newParts.append(part)
                    }
                }
                
                messageParts = newParts
            }
            
            contents.append([
                "role": message.role,
                "parts": messageParts
            ])
        }
        
        // 打印请求内容结构，确保格式正确
        print("准备发送请求，内容结构:")
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: contents, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("无法序列化请求内容: \(error.localizedDescription)")
        }
        
        return contents
    }
    
    // 流式生成内容
    func generateContent(prompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 确保有当前聊天列表ID
        guard let chatListId = currentChatListId else {
            throw NSError(domain: "GeminiService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "未设置当前聊天列表ID"])
        }
        
        // 重置状态
        currentContentItems = []
        isStreamActive = true
        currentUpdateHandler = updateHandler
        chunkCounter = 0
        completeStreamLog = "=== 流式生成内容开始 ===\n时间: \(Date())\n请求提示: \(prompt)\n"
        streamStartTime = Date()
        
        print("\n=== 开始流式生成内容 ===")
        print("请求提示: \(prompt)")
        print("当前聊天列表ID: \(chatListId), 历史消息数量: \(chatHistory.count)")
        
        // 创建URL
        //let urlString = "\(baseUrlString)/\(modelName):streamGenerateContent?key=\(geminiApiKey)&alt=sse"
        
        // 创建URL
        let urlString = "\(baseUrlString)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbnRhZXVzMDAxIiwiaWF0IjoxNzM1NjI0NDAzLCJleHAiOjE3NDQyNjQ0MDN9.ZrV6qOhbk1Ct4J8o3gvLcoeycQz_yItasitVfS5sR50", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        
        // 创建用户消息
        let userMessage = GeminiChatMessage(
            role: "user",
            parts: [
                ["text": prompt]
            ],
            contentItems: [
                ContentItem(type: .text(prompt), timestamp: Date())
            ]
        )
        
        // 添加到聊天历史
        chatHistory.append(userMessage)
        // 同时更新chatLists中的记录
        if let id = currentChatListId {
            chatLists[id] = chatHistory
        }
        
        // 整合连续的model消息
        let consolidatedHistory = consolidateModelMessages(chatHistory)
        
        // 准备请求内容，替换占位符
        let requestContents = prepareRequestContents(consolidatedHistory, userPrompt: prompt)
        
        // 构建请求体
        var requestBody: [String: Any] = [
            "contents": requestContents,
            "generationConfig": [
                "temperature": 1.0,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain",
                "responseModalities": ["image", "text"]
            ]
        ]
        
        // 打印完整请求体，用于调试
        print("完整请求体:")
        do {
            let debugJsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            if let jsonString = String(data: debugJsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("无法序列化完整请求体用于调试: \(error.localizedDescription)")
        }
        
        // 序列化请求体为JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            throw NSError(domain: "GeminiService", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON序列化失败: \(error.localizedDescription)"])
        }
        
        // 创建模型响应部分集合
        var modelParts: [[String: Any]] = []
        
        // 使用URLSession发送请求并读取流式响应
        guard let url = request.url else {
            throw NSError(domain: "GeminiService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        print("发起API请求: \(url.absoluteString)")
        print("使用模型: \(modelName)")
        
        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            
            // 检查HTTP响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("HTTP响应状态: \(httpResponse.statusCode)")
            print("HTTP响应头: \(httpResponse.allHeaderFields)")
            
            // 检查非200状态码
            if httpResponse.statusCode != 200 {
                // 读取错误消息
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                
                if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                } else if let errorText = String(data: errorData, encoding: .utf8) {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode): \(errorText)"])
                } else {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode)"])
                }
            }
            
            // 保存SSE响应到文件（用于调试）
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let timeStamp = Date().timeIntervalSince1970
            let filePath = documentsPath.appendingPathComponent("gemini_sse_\(timeStamp).json")
            
            // 先创建文件，避免"file doesn't exist"错误
            FileManager.default.createFile(atPath: filePath.path, contents: nil, attributes: nil)
            
            let fileHandle = try FileHandle(forWritingTo: filePath)
            defer { fileHandle.closeFile() }
            
            print("将响应保存到: \(filePath.path)")
            
            // 处理流式响应
            var characterBuffer = [UInt8]()
            
            for try await byte in bytes {
                // 如果停止标志被设置，退出循环
                if !isStreamActive {
                    print("流已被手动停止")
                    break
                }
                
                // 添加字节到字符缓冲区
                characterBuffer.append(byte)
                
                // 写入调试文件
                fileHandle.write(Data([byte]))
                
                // 当遇到换行符时处理一行
                if byte == 10 { // 换行符 '\n'
                    if let line = String(bytes: characterBuffer, encoding: .utf8) {
                        await handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines), modelParts: &modelParts)
                    }
                    characterBuffer.removeAll()
                }
            }
            
            // 处理可能的最后一行（没有换行符结束）
            if !characterBuffer.isEmpty {
                if let line = String(bytes: characterBuffer, encoding: .utf8) {
                    await handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines), modelParts: &modelParts)
                }
            }
            
            // 将完整的模型响应添加到聊天历史
            if !modelParts.isEmpty || !currentContentItems.isEmpty {
                let modelMessage = GeminiChatMessage(
                    role: "model",
                    parts: modelParts,
                    contentItems: currentContentItems
                )
                chatHistory.append(modelMessage)
                // 同时更新chatLists中的记录
                if let id = currentChatListId {
                    chatLists[id] = chatHistory
                }
                print("添加模型消息到聊天历史，部分数量: \(modelParts.count), 内容项数量: \(currentContentItems.count)")
            } else {
                print("没有收集到任何模型部分，无法添加到聊天历史")
            }
            
            // 添加结束信息到日志并保存
            let elapsedTime = Date().timeIntervalSince(streamStartTime)
            completeStreamLog += "\n=== 流式生成内容结束 ===\n耗时: \(elapsedTime)秒\n"
            saveStreamLogToFile()
            
            print("=== 流式生成内容结束 ===\n")
        } catch {
            // 添加错误信息到日志并保存
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    errorMessage = "请求超时，请重试。对于大型内容生成，可能需要更长的处理时间。"
                case .notConnectedToInternet:
                    errorMessage = "网络连接错误，请检查您的网络连接后重试。"
                case .cancelled:
                    errorMessage = "请求已取消。"
                default:
                    errorMessage = "网络错误: \(urlError.localizedDescription)"
                }
            } else {
                errorMessage = "API请求失败: \(error.localizedDescription)"
            }
            
            completeStreamLog += "\n=== 流式生成内容出错 ===\n错误: \(errorMessage)\n"
            saveStreamLogToFile()
            
            print("=== 流式生成内容出错 ===\n错误详情: \(error)")
            throw NSError(domain: "GeminiService", code: 1002, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
    
    // 发送带图片的请求
    func generateContentWithImage(prompt: String, image: UIImage, useImageUpload: Bool = false, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 确保有当前聊天列表ID
        guard let chatListId = currentChatListId else {
            throw NSError(domain: "GeminiService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "未设置当前聊天列表ID"])
        }
        
        // 重置状态
        currentContentItems = []
        isStreamActive = true
        currentUpdateHandler = updateHandler
        chunkCounter = 0
        completeStreamLog = "=== 流式生成带图片的内容开始 ===\n时间: \(Date())\n请求提示: \(prompt)\n图像尺寸: \(image.size.width) x \(image.size.height)\n"
        streamStartTime = Date()
        
        print("\n=== 开始流式生成带图片的内容 ===")
        print("请求提示: \(prompt)")
        print("当前聊天列表ID: \(chatListId), 历史消息数量: \(chatHistory.count)")
        print("图片处理方式: \(useImageUpload ? "上传图片获取URL" : "直接使用base64编码")")
        
        // 创建URL
        let urlString = "\(baseUrlString)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbnRhZXVzMDAxIiwiaWF0IjoxNzM1NjI0NDAzLCJleHAiOjE3NDQyNjQ0MDN9.ZrV6qOhbk1Ct4J8o3gvLcoeycQz_yItasitVfS5sR50", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 180
        
        // 处理图片：或者使用base64编码，或者上传图片获取URL
        let imageData: Data
        let inlineDataDict: [String: Any]
        
        // 首先将图片转换为JPEG数据
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "GeminiService", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法将图片转换为数据"])
        }
        
        imageData = jpegData
        
        if useImageUpload {
            // 上传图片并获取URL
            do {
                let imageUrl = try await uploadImage(image: image)
                inlineDataDict = [
                    "mimeType": "image/jpeg",
                    "data": imageUrl
                ]
                print("使用上传的图片URL: \(imageUrl)")
            } catch {
                print("图片上传失败，尝试使用base64编码: \(error.localizedDescription)")
                // 如果上传失败，回退到base64编码
        let base64Image = imageData.base64EncodedString()
                inlineDataDict = [
                    "mimeType": "image/jpeg",
                    "data": base64Image
                ]
                
                // 打印base64编码的调试信息
                print("Base64图片前20个字符: \(base64Image.prefix(20))...")
                print("Base64图片长度: \(base64Image.count)字节")
                print("Base64图片是否有效: \(Data(base64Encoded: base64Image) != nil)")
            }
        } else {
            // 直接使用base64编码
            let base64Image = imageData.base64EncodedString()
            inlineDataDict = [
                "mimeType": "image/jpeg",
                "data": base64Image
            ]
            
            // 打印base64编码的调试信息
            print("Base64图片前20个字符: \(base64Image.prefix(20))...")
            print("Base64图片长度: \(base64Image.count)字节")
            print("Base64图片是否有效: \(Data(base64Encoded: base64Image) != nil)")
        }
        
        // 构建用户消息，包含文本和图像
        let userMessage = GeminiChatMessage(
            role: "user",
            parts: [
                ["text": prompt],
                ["inlineData": inlineDataDict]
            ],
            contentItems: [
                ContentItem(type: .text(prompt), timestamp: Date()),
                ContentItem(type: .image(imageData), timestamp: Date())
            ]
        )
        
        // 添加到聊天历史
        chatHistory.append(userMessage)
        // 同时更新chatLists中的记录
        if let id = currentChatListId {
            chatLists[id] = chatHistory
        }
        
        // 整合连续的model消息
        let consolidatedHistory = consolidateModelMessages(chatHistory)
        
        // 准备请求内容，替换占位符
        let requestContents = prepareRequestContents(consolidatedHistory, userPrompt: prompt)
        
        // 构建请求体
        var requestBody: [String: Any] = [
            "contents": requestContents,
            "generationConfig": [
                "temperature": 1.0,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain",
                "responseModalities": ["image", "text"]
            ]
        ]
        
        // 打印完整请求体，用于调试
        print("完整请求体:")
        do {
            let debugJsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            if let jsonString = String(data: debugJsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("无法序列化完整请求体用于调试: \(error.localizedDescription)")
        }
        
        // 序列化请求体为JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            throw NSError(domain: "GeminiService", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON序列化失败: \(error.localizedDescription)"])
        }
        
        // 创建模型响应部分集合
        var modelParts: [[String: Any]] = []
        
        // 使用URLSession发送请求并读取流式响应
        guard let url = request.url else {
            throw NSError(domain: "GeminiService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        print("发起带图片的API请求: \(url.absoluteString)")
        print("使用模型: \(modelName)")
        print("图片大小: \(image.size.width) x \(image.size.height), 数据大小: \(imageData.count)")
        
        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            
            // 检查HTTP响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("HTTP响应状态: \(httpResponse.statusCode)")
            print("HTTP响应头: \(httpResponse.allHeaderFields)")
            
            // 检查非200状态码
            if httpResponse.statusCode != 200 {
                // 读取错误消息
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                
                if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                } else if let errorText = String(data: errorData, encoding: .utf8) {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode): \(errorText)"])
                } else {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode)"])
                }
            }
            
            // 保存SSE响应到文件（用于调试）
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let timeStamp = Date().timeIntervalSince1970
            let filePath = documentsPath.appendingPathComponent("gemini_sse_\(timeStamp).json")
            
            // 先创建文件，避免"file doesn't exist"错误
            FileManager.default.createFile(atPath: filePath.path, contents: nil, attributes: nil)
            
            let fileHandle = try FileHandle(forWritingTo: filePath)
            defer { fileHandle.closeFile() }
            
            print("将响应保存到: \(filePath.path)")
            
            // 处理流式响应
            var characterBuffer = [UInt8]()
            
            for try await byte in bytes {
                // 如果停止标志被设置，退出循环
                if !isStreamActive {
                    print("流已被手动停止")
                    break
                }
                
                // 添加字节到字符缓冲区
                characterBuffer.append(byte)
                
                // 写入调试文件
                fileHandle.write(Data([byte]))
                
                // 当遇到换行符时处理一行
                if byte == 10 { // 换行符 '\n'
                    if let line = String(bytes: characterBuffer, encoding: .utf8) {
                        await handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines), modelParts: &modelParts)
                    }
                    characterBuffer.removeAll()
                }
            }
            
            // 处理可能的最后一行（没有换行符结束）
            if !characterBuffer.isEmpty {
                if let line = String(bytes: characterBuffer, encoding: .utf8) {
                    await handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines), modelParts: &modelParts)
                }
            }
            
            // 将完整的模型响应添加到聊天历史
            if !modelParts.isEmpty || !currentContentItems.isEmpty {
                let modelMessage = GeminiChatMessage(
                    role: "model",
                    parts: modelParts,
                    contentItems: currentContentItems
                )
                chatHistory.append(modelMessage)
                // 同时更新chatLists中的记录
                if let id = currentChatListId {
                    chatLists[id] = chatHistory
                }
                print("添加模型消息到聊天历史，部分数量: \(modelParts.count), 内容项数量: \(currentContentItems.count)")
            } else {
                print("没有收集到任何模型部分，无法添加到聊天历史")
            }
            
            // 添加结束信息到日志并保存
            let elapsedTime = Date().timeIntervalSince(streamStartTime)
            completeStreamLog += "\n=== 流式生成带图片的内容结束 ===\n耗时: \(elapsedTime)秒\n"
            saveStreamLogToFile()
            
            print("=== 流式生成带图片的内容结束 ===\n")
        } catch {
            // 添加错误信息到日志并保存
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    errorMessage = "请求超时，请重试。对于大型内容生成，可能需要更长的处理时间。"
                case .notConnectedToInternet:
                    errorMessage = "网络连接错误，请检查您的网络连接后重试。"
                case .cancelled:
                    errorMessage = "请求已取消。"
                default:
                    errorMessage = "网络错误: \(urlError.localizedDescription)"
                }
            } else {
                errorMessage = "API请求失败: \(error.localizedDescription)"
            }
            
            completeStreamLog += "\n=== 流式生成带图片的内容出错 ===\n错误: \(errorMessage)\n"
            saveStreamLogToFile()
            
            print("=== 流式生成带图片的内容出错 ===\n错误详情: \(error)")
            throw NSError(domain: "GeminiService", code: 1002, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
    
    // 上传图片到服务器
    func uploadImage(image: UIImage) async throws -> String {
        print("开始上传图片，尺寸: \(image.size.width) x \(image.size.height)")
        
        // 创建URL
        let urlString = "https://huohuaai.com/api/v1/images/upload"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的图片上传URL"])
        }
        
        // 将图片转换为JPEG数据
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "GeminiService", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法将图片转换为数据"])
        }
        
        // 生成唯一的边界字符串
        let boundary = UUID().uuidString
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbnRhZXVzMDAxIiwiaWF0IjoxNzM1NjI0NDAzLCJleHAiOjE3NDQyNjQ0MDN9.ZrV6qOhbk1Ct4J8o3gvLcoeycQz_yItasitVfS5sR50", forHTTPHeaderField: "Authorization")
        
        // 创建表单数据
        var body = Data()
        
        // 添加文件数据
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 添加结束边界
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // 设置请求体
        request.httpBody = body
        
        // 发送请求
        do {
            print("发送图片上传请求，图片大小: \(imageData.count) 字节")
            let (data, response) = try await urlSession.data(for: request)
            
            // 检查HTTP响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("图片上传HTTP响应状态: \(httpResponse.statusCode)")
            
            // 解析响应数据
            if let responseString = String(data: data, encoding: .utf8) {
                print("图片上传响应: \(responseString)")
            }
            
            // 检查非200状态码
            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorJson["message"] as? String {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                } else if let errorText = String(data: data, encoding: .utf8) {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode): \(errorText)"])
                } else {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode)"])
                }
            }
            
            // 解析响应JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int else {
                throw NSError(domain: "GeminiService", code: 7, userInfo: [NSLocalizedDescriptionKey: "无法解析响应JSON"])
            }
            
            // 检查响应码
            if code == 0, let imageUrl = json["data"] as? String {
                print("图片上传成功，URL: \(imageUrl)")
                return imageUrl
            } else {
                let message = json["message"] as? String ?? "未知错误"
                throw NSError(domain: "GeminiService", code: 8, userInfo: [NSLocalizedDescriptionKey: "上传失败: \(message)"])
            }
        } catch {
            print("图片上传错误: \(error.localizedDescription)")
            throw NSError(domain: "GeminiService", code: 9, userInfo: [NSLocalizedDescriptionKey: "图片上传失败: \(error.localizedDescription)"])
        }
    }
    
    // 使用图片URL发送带图片的请求
    func generateContentWithImageUrl(prompt: String, imageUrl: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 确保有当前聊天列表ID
        guard let chatListId = currentChatListId else {
            throw NSError(domain: "GeminiService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "未设置当前聊天列表ID"])
        }
        
        // 重置状态
        currentContentItems = []
        isStreamActive = true
        currentUpdateHandler = updateHandler
        chunkCounter = 0
        completeStreamLog = "=== 流式生成带图片URL的内容开始 ===\n时间: \(Date())\n请求提示: \(prompt)\n图像URL: \(imageUrl)\n"
        streamStartTime = Date()
        
        print("\n=== 开始流式生成带图片URL的内容 ===")
        print("请求提示: \(prompt)")
        print("当前聊天列表ID: \(chatListId), 历史消息数量: \(chatHistory.count)")
        print("使用图片URL: \(imageUrl)")
        
        // 创建URL
        let urlString = "\(baseUrlString)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbnRhZXVzMDAxIiwiaWF0IjoxNzM1NjI0NDAzLCJleHAiOjE3NDQyNjQ0MDN9.ZrV6qOhbk1Ct4J8o3gvLcoeycQz_yItasitVfS5sR50", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 180
        
        // 创建内联数据字典，使用URL
        let inlineDataDict: [String: Any] = [
            "mimeType": "image/jpeg",
            "data": imageUrl
        ]
        
        // 创建一个无图像数据的ContentItem，只用于UI显示
        let dummyImageData = Data() // 空数据，因为实际图像数据在服务器上
        
        // 构建用户消息，包含文本和图像URL
        let userMessage = GeminiChatMessage(
            role: "user",
            parts: [
                ["text": prompt],
                ["inlineData": inlineDataDict]
            ],
            contentItems: [
                ContentItem(type: .text(prompt), timestamp: Date()),
                ContentItem(type: .image(dummyImageData), timestamp: Date()) // 仅用于UI显示
            ]
        )
        
        // 添加到聊天历史
        chatHistory.append(userMessage)
        // 同时更新chatLists中的记录
        if let id = currentChatListId {
            chatLists[id] = chatHistory
        }
        
        // 整合连续的model消息
        let consolidatedHistory = consolidateModelMessages(chatHistory)
        
        // 准备请求内容，替换占位符
        let requestContents = prepareRequestContents(consolidatedHistory, userPrompt: prompt)
        
        // 构建请求体
        var requestBody: [String: Any] = [
            "contents": requestContents,
            "generationConfig": [
                "temperature": 1.0,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain",
                "responseModalities": ["image", "text"]
            ]
        ]
        
        // 打印完整请求体，用于调试
        print("完整请求体:")
        do {
            let debugJsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            if let jsonString = String(data: debugJsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("无法序列化完整请求体用于调试: \(error.localizedDescription)")
        }
        
        // 序列化请求体为JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            throw NSError(domain: "GeminiService", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON序列化失败: \(error.localizedDescription)"])
        }
        
        // 创建模型响应部分集合
        var modelParts: [[String: Any]] = []
        
        // 使用URLSession发送请求并读取流式响应
        guard let url = request.url else {
            throw NSError(domain: "GeminiService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        print("发起带图片URL的API请求: \(url.absoluteString)")
        print("使用模型: \(modelName)")
        
        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            
            // 检查HTTP响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("HTTP响应状态: \(httpResponse.statusCode)")
            print("HTTP响应头: \(httpResponse.allHeaderFields)")
            
            // 检查非200状态码
            if httpResponse.statusCode != 200 {
                // 读取错误消息
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                
                if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                } else if let errorText = String(data: errorData, encoding: .utf8) {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode): \(errorText)"])
                } else {
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误 \(httpResponse.statusCode)"])
                }
            }
            
            // 保存SSE响应到文件（用于调试）
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let timeStamp = Date().timeIntervalSince1970
            let filePath = documentsPath.appendingPathComponent("gemini_sse_\(timeStamp).json")
            
            // 先创建文件，避免"file doesn't exist"错误
            FileManager.default.createFile(atPath: filePath.path, contents: nil, attributes: nil)
            
            let fileHandle = try FileHandle(forWritingTo: filePath)
            defer { fileHandle.closeFile() }
            
            print("将响应保存到: \(filePath.path)")
            
            // 处理流式响应
            var characterBuffer = [UInt8]()
            
            for try await byte in bytes {
                // 如果停止标志被设置，退出循环
                if !isStreamActive {
                    print("流已被手动停止")
                    break
                }
                
                // 添加字节到字符缓冲区
                characterBuffer.append(byte)
                
                // 写入调试文件
                fileHandle.write(Data([byte]))
                
                // 当遇到换行符时处理一行
                if byte == 10 { // 换行符 '\n'
                    if let line = String(bytes: characterBuffer, encoding: .utf8) {
                        await handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines), modelParts: &modelParts)
                    }
                    characterBuffer.removeAll()
                }
            }
            
            // 处理可能的最后一行（没有换行符结束）
            if !characterBuffer.isEmpty {
                if let line = String(bytes: characterBuffer, encoding: .utf8) {
                    await handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines), modelParts: &modelParts)
                }
            }
            
            // 将完整的模型响应添加到聊天历史
            if !modelParts.isEmpty || !currentContentItems.isEmpty {
                let modelMessage = GeminiChatMessage(
                    role: "model",
                    parts: modelParts,
                    contentItems: currentContentItems
                )
                chatHistory.append(modelMessage)
                // 同时更新chatLists中的记录
                if let id = currentChatListId {
                    chatLists[id] = chatHistory
                }
                print("添加模型消息到聊天历史，部分数量: \(modelParts.count), 内容项数量: \(currentContentItems.count)")
            } else {
                print("没有收集到任何模型部分，无法添加到聊天历史")
            }
            
            // 添加结束信息到日志并保存
            let elapsedTime = Date().timeIntervalSince(streamStartTime)
            completeStreamLog += "\n=== 流式生成带图片URL的内容结束 ===\n耗时: \(elapsedTime)秒\n"
            saveStreamLogToFile()
            
            print("=== 流式生成带图片URL的内容结束 ===\n")
        } catch {
            // 添加错误信息到日志并保存
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    errorMessage = "请求超时，请重试。对于大型内容生成，可能需要更长的处理时间。"
                case .notConnectedToInternet:
                    errorMessage = "网络连接错误，请检查您的网络连接后重试。"
                case .cancelled:
                    errorMessage = "请求已取消。"
                default:
                    errorMessage = "网络错误: \(urlError.localizedDescription)"
                }
            } else {
                errorMessage = "API请求失败: \(error.localizedDescription)"
            }
            
            completeStreamLog += "\n=== 流式生成内容出错 ===\n错误: \(errorMessage)\n"
            saveStreamLogToFile()
            
            print("=== 流式生成内容出错 ===\n错误详情: \(error)")
            throw NSError(domain: "GeminiService", code: 1002, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
}
