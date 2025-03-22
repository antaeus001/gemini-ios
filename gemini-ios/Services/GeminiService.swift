import Foundation
import SwiftUI
import UIKit

// API响应结构
struct APIResponse {
    var text: String?
    var imageData: Data?
}

// 流式内容项类型
enum ContentItemType {
    case text(String)
    case image(Data)
}

// 流式内容项
struct ContentItem {
    let type: ContentItemType
    let timestamp: Date
    let id = UUID() // 用于标识唯一内容项
}

// 流式内容更新处理器
typealias ContentUpdateHandler = (ContentItem) -> Void

// 消息结构
struct GeminiChatMessage {
    let role: String // "user" 或 "model"
    let parts: [[String: Any]]
    let contentItems: [ContentItem]
}

// GeminiService类用于直接调用Google Gemini API
class GeminiService {
    private let geminiApiKey: String
    private let baseUrlString = "https://generativelanguage.googleapis.com/v1beta/models"
    private let modelName = "gemini-2.0-flash-exp-image-generation"
    private var chatHistory: [GeminiChatMessage] = []
    
    // 保存当前的处理器
    private var currentUpdateHandler: ContentUpdateHandler?
    private var currentContentItems: [ContentItem] = []
    private var isStreamActive = false
    
    // 初始化API服务
    init() {
        // 从环境变量获取API密钥
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] else {
            fatalError("需要设置GEMINI_API_KEY环境变量")
        }
        
        self.geminiApiKey = apiKey
    }
    
    // 开始聊天会话（返回初始响应）
    func startChat(initialPrompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 清空历史记录
        chatHistory = []
        try await generateContent(prompt: initialPrompt, updateHandler: updateHandler)
    }
    
    // 发送消息并获取内容项
    func sendMessage(prompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        try await generateContent(prompt: prompt, updateHandler: updateHandler)
    }
    
    // 使用预设提示开始图像编辑聊天
    func startChatWithImageEdit(prompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 清空历史记录
        chatHistory = []
        try await generateContent(prompt: prompt, updateHandler: updateHandler)
    }
    
    // 使用预设提示开始故事生成聊天
    func startChatForStoryGeneration(prompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 清空历史记录
        chatHistory = []
        try await generateContent(prompt: prompt, updateHandler: updateHandler)
    }
    
    // 使用预设提示开始设计生成聊天
    func startChatForDesignGeneration(prompt: String, updateHandler: @escaping ContentUpdateHandler) async throws {
        // 清空历史记录
        chatHistory = []
        try await generateContent(prompt: prompt, updateHandler: updateHandler)
    }
    
    // 清空对话历史
    func clearChatHistory() {
        chatHistory = []
    }
    
    // 停止当前流
    func stopStream() {
        isStreamActive = false
    }
    
    // 核心方法：流式生成内容（文本和图像）
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
        
        print("请求URL: \(urlString)")
        print("验证API密钥长度: \(geminiApiKey.count)字符")
        
        // 构建可供测试的完整URL（去掉API密钥）
        let apiEndpoint = "\(baseUrlString)/\(modelName):generateContent"
        print("API端点: \(apiEndpoint)")

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // 增加超时时间到60秒
        
        // 将用户消息添加到聊天历史
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
                // 添加所有安全设置类别，设置为最低阈值
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
    
    // 处理单行SSE数据
    private func handleSSELine(_ line: String, modelParts: inout [[String: Any]]) async {
        // 忽略空行
        if line.isEmpty {
            return
        }
        
        // 忽略注释行
        if line.hasPrefix(":") {
            print("SSE注释行: \(line)")
            return
        }
        
        // 处理数据行
        if line.hasPrefix("data: ") {
            let jsonString = line.dropFirst(6) // 删除"data: "前缀
            
            // 忽略空数据
            if jsonString.isEmpty {
                return
            }
            
            print("SSE数据行: \(jsonString.prefix(50))...")
            
            // 尝试解析JSON
            if let jsonData = String(jsonString).data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        print("成功解析JSON数据")
                        
                        // 先检查是否包含错误信息
                        if let error = json["error"] as? [String: Any] {
                            let code = error["code"] as? Int ?? 0
                            let message = error["message"] as? String ?? "未知错误"
                            let status = error["status"] as? String ?? "UNKNOWN"
                            
                            print("API错误: 代码=\(code), 状态=\(status), 消息=\(message)")
                            
                            // 保存错误响应用于调试
                            let errorFilename = "gemini_error_\(Date().timeIntervalSince1970).json"
                            saveResponseDataToFile(data: jsonData, filename: errorFilename)
                            
                            // 创建错误内容项
                            let errorText = "API错误: \(message)"
                            let errorItem = ContentItem(type: .text(errorText), timestamp: Date())
                            currentContentItems.append(errorItem)
                            
                            // 通知UI显示错误信息
                            await MainActor.run {
                                currentUpdateHandler?(errorItem)
                            }
                            
                            // 添加错误信息到模型部分
                            modelParts.append(["text": errorText])
                            
                            // 停止流
                            isStreamActive = false
                            return
                        }
                        
                        // 保存用于调试
                        let responseFilename = "gemini_sse_\(Date().timeIntervalSince1970).json"
                        saveResponseDataToFile(data: jsonData, filename: responseFilename)
                        
                        // 处理JSON
                        await processStreamChunk(json: json, modelParts: &modelParts)
                    }
                } catch {
                    print("JSON解析错误: \(error.localizedDescription)")
                    print("原始JSON字符串: \(jsonString)")
                }
            }
        } else {
            print("未知的SSE行: \(line)")
        }
    }
    
    // 处理流式响应块
    private func processStreamChunk(json: [String: Any], modelParts: inout [[String: Any]]) async {
        // 打印完整JSON结构
        print("流式块JSON结构: \(json.keys)")
        
        // 检查candidates
        if let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty {
            print("找到候选项: \(candidates.count)个")
            
            for (candidateIndex, candidate) in candidates.enumerated() {
                print("处理候选项 #\(candidateIndex): \(candidate.keys)")
                
                // 检查是否有finishReason，表示流结束
                if let finishReason = candidate["finishReason"] as? String {
                    print("发现结束原因: \(finishReason)")
                    continue
                }
                
                if let content = candidate["content"] as? [String: Any] {
                    print("候选项内容键: \(content.keys)")
                    
                    if let parts = content["parts"] as? [[String: Any]] {
                        print("内容部分数量: \(parts.count)")
                        
                        for (index, part) in parts.enumerated() {
                            print("处理部分 #\(index + 1): \(part.keys)")
                            
                            // 处理文本部分
                            if let text = part["text"] as? String {
                                // 打印完整文本内容
                                print("收到文本内容 [\(text.count)字符]: \(text)")
                                
                                // 创建文本内容项
                                let textItem = ContentItem(type: .text(text), timestamp: Date())
                                currentContentItems.append(textItem)
                                
                                // 调用处理器返回文本更新
                                await MainActor.run {
                                    print("发送文本更新到UI: \(text)")
                                    currentUpdateHandler?(textItem)
                                }
                                
                                // 收集模型部分
                                modelParts.append(["text": text])
                            }
                            
                            // 处理图像部分 - 多种可能的格式
                            if let inlineData = part["inlineData"] as? [String: Any] {
                                await processImageData(inlineData: inlineData, keyFormat: "驼峰", modelParts: &modelParts)
                            }
                            else if let inlineData = part["inline_data"] as? [String: Any] {
                                await processImageData(inlineData: inlineData, keyFormat: "下划线", modelParts: &modelParts)
                            }
                            else if let fileData = part["fileData"] as? [String: Any] {
                                print("检测到fileData: \(fileData)")
                                // 这里不做处理，因为需要额外的下载步骤
                            }
                            else if part.keys.count > 0 && !part.keys.contains("text") {
                                // 检查是否有其他可能的键
                                print("没有找到标准格式的文本或图像数据，检查其他键: \(part.keys)")
                            }
                        }
                    } else {
                        print("候选项内容不包含parts数组或格式不正确")
                    }
                } else {
                    print("候选项不包含content字段或格式不正确")
                }
            }
        } else {
            print("响应不包含有效的candidates数组，完整JSON: \(json)")
        }
    }
    
    // 处理图像数据的辅助方法
    private func processImageData(inlineData: [String: Any], keyFormat: String, modelParts: inout [[String: Any]]) async {
        print("检测到图像数据 (\(keyFormat)格式): \(inlineData.keys)")
        
        // 根据格式确定键名
        let mimeTypeKey = keyFormat == "驼峰" ? "mimeType" : "mime_type"
        
        if let mimeType = inlineData[mimeTypeKey] as? String,
           let base64Data = inlineData["data"] as? String,
           mimeType.starts(with: "image/") {
            
            print("图像MIME类型: \(mimeType), 数据长度: \(base64Data.count)")
            
            if base64Data.isEmpty {
                print("警告：图像base64数据为空")
                return
            }
            
            if let imageData = Data(base64Encoded: base64Data) {
                print("成功从base64解码图像数据，大小: \(imageData.count)字节")
                
                // 创建图像内容项
                let imageItem = ContentItem(type: .image(imageData), timestamp: Date())
                currentContentItems.append(imageItem)
                
                // 保存图像到文件，用于调试
                let filename = "generated_image_\(Date().timeIntervalSince1970).png"
                saveImageToFile(imageData: imageData, filename: filename)
                print("图像已保存到: \(filename)")
                
                // 调用处理器返回图像更新
                await MainActor.run {
                    print("发送图像更新到UI: \(imageData.count)字节")
                    currentUpdateHandler?(imageItem)
                }
                
                // 添加到模型部分（使用标准化格式）
                var dataDict: [String: Any] = [:]
                dataDict = [
                    "inlineData": [
                        "mimeType": mimeType,
                        "data": base64Data
                    ]
                ]
                
                modelParts.append(dataDict)
            } else {
                print("无法从base64字符串解码图像数据")
            }
        } else {
            print("inlineData缺少必要的字段或不是图像类型: mimeType=\(inlineData[mimeTypeKey] ?? "nil"), dataLength=\(inlineData["data"] != nil ? "非空" : "nil")")
        }
    }
    
    // 保存响应数据到文件，用于调试
    private func saveResponseDataToFile(data: Data, filename: String) {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法访问文档目录")
            return
        }
        
        let fileURL = documentDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            print("响应数据已保存到: \(fileURL.path)")
        } catch {
            print("保存响应数据失败: \(error.localizedDescription)")
        }
    }
    
    // 保存图像到文件，用于调试
    private func saveImageToFile(imageData: Data, filename: String) {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法访问文档目录")
            return
        }
        
        let fileURL = documentDirectory.appendingPathComponent(filename)
        do {
            try imageData.write(to: fileURL)
            print("图像已保存到: \(fileURL.path)")
        } catch {
            print("保存图像失败: \(error.localizedDescription)")
        }
    }
}