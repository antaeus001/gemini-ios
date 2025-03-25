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
    var contentItems: [ContentItem]
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
    var currentContentItems: [ContentItem] = []
    var isStreamActive: Bool = false
    var currentUpdateHandler: ContentUpdateHandler? = nil
    private var chunkCounter: Int = 0
    private var completeStreamLog: String = ""
    private var streamStartTime: Date = Date()
    
    // 清除聊天历史
    func clearChatHistory() {
        chatHistory.removeAll()
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
        
        guard let candidates = responseDict["candidates"] as? [[String: Any]],
              candidates.count > 0,
              let content = candidates[0]["content"] as? [String: Any],
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
            if let inlineData = part["inlineData"] as? [String: Any],
               let data = inlineData["data"] as? String,
               let mimeType = inlineData["mimeType"] as? String,
               mimeType.hasPrefix("image/") {
                
                printResponseContent("图像内容: MimeType=\(mimeType), 数据长度=\(data.count)字节", type: "图像")
                
                if let imageData = Data(base64Encoded: data) {
                    print("成功解码图像数据，大小: \(imageData.count)字节")
                    let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        self.currentUpdateHandler?(contentItem)
                    }
                } else {
                    print("无法解码Base64图像数据")
                }
            }
        }
    }
    
    // 流式生成内容
    func generateContent(prompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 重置状态
        currentContentItems = []
        isStreamActive = true
        currentUpdateHandler = updateHandler
        chunkCounter = 0
        completeStreamLog = "=== 流式生成内容开始 ===\n时间: \(Date())\n请求提示: \(prompt)\n"
        streamStartTime = Date()
        
        print("\n=== 开始流式生成内容 ===")
        print("请求提示: \(prompt)")
        
        // 创建URL
        //let urlString = "\(baseUrlString)/\(modelName):streamGenerateContent?key=\(geminiApiKey)&alt=sse"
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
        
        // 构建用户消息
        let userMessage = GeminiChatMessage(
            role: "user",
            parts: [["text": prompt]],
            contentItems: [ContentItem(type: .text(prompt), timestamp: Date())]
        )
        chatHistory.append(userMessage)
        
        // 准备contents数组
        var contents: [[String: Any]] = []
        
        // 添加所有历史消息
        for message in chatHistory {
            let messageDict: [String: Any] = [
                "role": message.role,
                "parts": message.parts
            ]
            contents.append(messageDict)
        }
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain",
                "responseModalities": [
                    "image",
                    "text"
                ]
            ],
            "safety_settings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]
        
        // 序列化请求体为JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
            
            // 打印请求数据，用于调试
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("请求JSON数据: \(jsonString)")
            }
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
    func generateContentWithImage(prompt: String, image: UIImage, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 重置状态
        currentContentItems = []
        isStreamActive = true
        currentUpdateHandler = updateHandler
        chunkCounter = 0
        completeStreamLog = "=== 流式生成带图片的内容开始 ===\n时间: \(Date())\n请求提示: \(prompt)\n图像尺寸: \(image.size.width) x \(image.size.height)\n"
        streamStartTime = Date()
        
        print("\n=== 开始流式生成带图片的内容 ===")
        print("请求提示: \(prompt)")
        
        // 创建URL
        let urlString = "\(baseUrlString)/\(modelName):streamGenerateContent?key=\(geminiApiKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        
        // 将图片转换为base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "GeminiService", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法将图片转换为数据"])
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // 构建用户消息，包含文本和图像
        let userMessage = GeminiChatMessage(
            role: "user",
            parts: [
                ["text": prompt],
                [
                    "inlineData": [
                        "mimeType": "image/jpeg",
                        "data": base64Image
                    ]
                ]
            ],
            contentItems: [
                ContentItem(type: .text(prompt), timestamp: Date()),
                ContentItem(type: .image(imageData), timestamp: Date())
            ]
        )
        chatHistory.append(userMessage)
        
        // 准备contents数组
        var contents: [[String: Any]] = []
        
        // 添加所有历史消息
        for message in chatHistory {
            let messageDict: [String: Any] = [
                "role": message.role,
                "parts": message.parts
            ]
            contents.append(messageDict)
        }
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
                "responseMimeType": "text/plain",
                "responseModalities": [
                    "image",
                    "text"
                ]
            ],
            "safety_settings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]
        
        // 序列化请求体为JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
            
            // 打印请求数据，用于调试
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("请求JSON数据: \(jsonString)")
            }
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
}
