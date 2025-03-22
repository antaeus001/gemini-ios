import Foundation
import UIKit

// 内容项类型定义
enum ContentItemType {
    case text(String)
    case image(Data)
}

// 内容项结构
struct ContentItem: Identifiable {
    let id = UUID()
    let type: ContentItemType
    let timestamp: Date
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
    // API配置
    private let baseUrlString = "https://generativelanguage.googleapis.com/v1beta/models"
    private let modelName = "gemini-2.0-flash-exp-image-generation"
    private let geminiApiKey = "AIzaSyDtaceYdTFwn4H0RIA6u5fHS-BDUJoEK04"
    
    // 状态变量
    var chatHistory: [GeminiChatMessage] = []
    var currentContentItems: [ContentItem] = []
    var isStreamActive: Bool = false
    var currentUpdateHandler: ContentUpdateHandler? = nil
    
    // 清除聊天历史
    func clearChatHistory() {
        chatHistory.removeAll()
        currentContentItems.removeAll()
    }
    
    // 停止流式生成
    func stopStream() {
        isStreamActive = false
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
        if line.hasPrefix("data:") {
            let dataContent = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if dataContent == "[DONE]" {
                isStreamActive = false
                return
            }
            
            // 尝试解析JSON数据
            if let data = dataContent.data(using: .utf8),
               let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await processResponseData(responseDict, modelParts: &modelParts)
            }
        }
    }
    
    // 处理API响应数据
    private func processResponseData(_ responseDict: [String: Any], modelParts: inout [[String: Any]]) async {
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
                let contentItem = ContentItem(type: .text(text), timestamp: Date())
                currentContentItems.append(contentItem)
                await MainActor.run {
                    self.currentUpdateHandler?(contentItem)
                }
            }
            
            // 处理内联数据（图像）
            if let inlineData = part["inlineData"] as? [String: Any],
               let data = inlineData["data"] as? String,
               let mimeType = inlineData["mimeType"] as? String,
               mimeType.hasPrefix("image/") {
                
                if let imageData = Data(base64Encoded: data) {
                    let contentItem = ContentItem(type: .image(imageData), timestamp: Date())
                    currentContentItems.append(contentItem)
                    await MainActor.run {
                        self.currentUpdateHandler?(contentItem)
                    }
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
        
        print("开始流式生成内容，请求提示: \(prompt)")
        
        // 创建URL
        let urlString = "\(baseUrlString)/\(modelName):streamGenerateContent?key=\(geminiApiKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
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
                "temperature": 1.0,
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
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            // 检查HTTP响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("HTTP响应状态: \(httpResponse.statusCode)")
            
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
        } catch {
            throw NSError(domain: "GeminiService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "API请求失败: \(error.localizedDescription)"])
        }
    }
    
    // 发送带图片的请求
    func generateContentWithImage(prompt: String, image: UIImage, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 重置状态
        currentContentItems = []
        isStreamActive = true
        currentUpdateHandler = updateHandler
        
        print("开始流式生成带图片的内容，请求提示: \(prompt)")
        
        // 创建URL
        let urlString = "\(baseUrlString)/\(modelName):streamGenerateContent?key=\(geminiApiKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
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
                "temperature": 1.0,
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
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            // 检查HTTP响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "GeminiService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("HTTP响应状态: \(httpResponse.statusCode)")
            
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
        } catch {
            throw NSError(domain: "GeminiService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "API请求失败: \(error.localizedDescription)"])
        }
    }
}