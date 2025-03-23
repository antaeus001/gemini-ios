import SwiftUI
import UIKit
import PhotosUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showingExamples = false
    @State private var imagePickerVisible = false
    @State private var selectedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    
    // 修复MainActor初始化问题
    init(viewModel: ChatViewModel? = nil) {
        // 如果传入了viewModel就使用它，否则创建一个新的
        if let viewModel = viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            // 使用Task创建，因为MainActor初始化是异步的
            let tempViewModel = ChatViewModel()
            _viewModel = StateObject(wrappedValue: tempViewModel)
        }
    }
    
    func scrollToBottom() {
        if let lastMessage = viewModel.messages.last {
            withAnimation {
                scrollViewProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    @State private var scrollViewProxy: ScrollViewProxy?
    
    var body: some View {
        VStack {
            // 显示聊天记录
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .background(Color(.systemBackground))
                .shadow(radius: 5)
                .padding()
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom()
                }
                .onAppear {
                    scrollViewProxy = scrollView
                    scrollToBottom()
                }
            }
            
            // 如果有选择的图片，显示预览和提示
            if let userImage = viewModel.userImage {
                HStack {
                    Image(uiImage: userImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .cornerRadius(8)
                    
                    Text("请输入提示词来编辑此图片")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.userImage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
            }
            
            // 显示错误信息（如果有）
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
            
            // 输入区域
            HStack {
                // 图片选择按钮
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .disabled(viewModel.isLoading)
                .onChange(of: photoItem) { _, newItem in
                    if let newItem {
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                await MainActor.run {
                                    viewModel.setUserImage(image)
                                    photoItem = nil
                                }
                            }
                        }
                    }
                }
                
                // 消息输入框
                TextField("想要生成什么？", text: $viewModel.inputMessage)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .disabled(viewModel.isLoading)
                
                // 加载指示器或发送按钮
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.horizontal, 10)
                } else {
                    Button(action: {
                        Task {
                            await viewModel.sendMessage()
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.blue)
                    }
                    .disabled(viewModel.inputMessage.isEmpty && viewModel.userImage == nil)
                }
            }
            .padding()
            
            // 示例按钮
            Button("查看示例提示") {
                showingExamples = true
            }
            .padding(.bottom)
            .actionSheet(isPresented: $showingExamples) {
                ActionSheet(
                    title: Text("选择示例提示"),
                    message: Text("选择一个示例来尝试Gemini的能力"),
                    buttons: [
                        .default(Text("图像生成")) {
                            viewModel.useExamplePrompt(type: .imageEdit)
                        },
                        .default(Text("故事生成")) {
                            viewModel.useExamplePrompt(type: .storyGeneration)
                        },
                        .default(Text("设计生成")) {
                            viewModel.useExamplePrompt(type: .designGeneration)
                        },
                        .cancel()
                    ]
                )
            }
        }
    }
}

// 消息视图
struct MessageView: View {
    @ObservedObject var message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // 根据消息内容类型显示不同的视图
                switch message.content {
                case .text(let text):
                    Text(text)
                        .padding(12)
                        .background(message.role == .user ? Color.blue : Color(.systemGray5))
                        .foregroundColor(message.role == .user ? .white : .primary)
                        .cornerRadius(16)
                        .textSelection(.enabled)
                        .onAppear {
                            print("显示文本消息: \(String(text.prefix(20)))...")
                        }
                
                case .image(let image):
                    VStack(alignment: .center, spacing: 4) {
                        Text(message.role == .user ? "上传的图片" : "生成的图片")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        GeometryReader { geo in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: min(geo.size.width * 0.9, 300), height: 300)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .onAppear {
                                    print("显示图像: \(image.size.width) x \(image.size.height)")
                                }
                        }
                        .frame(height: 300)
                    }
                    .frame(maxWidth: 300)
                    .padding(12)
                    .background(message.role == .user ? Color.blue.opacity(0.2) : Color(.systemGray6))
                    .cornerRadius(16)
                    .onAppear {
                        print("显示图像消息，图像尺寸: \(image.size.width) x \(image.size.height)")
                    }
                
                case .mixedContent(let items):
                    VStack(alignment: .leading, spacing: 12) {
                        if items.isEmpty && message.isGenerating {
                            // 显示正在生成的指示器
                            TypingIndicator()
                                .frame(width: 40, height: 20)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(items, id: \.id) { item in
                                switch item {
                                case .text(let text):
                                    Text(text)
                                        .padding([.horizontal, .top], 8)
                                        .textSelection(.enabled)
                                
                                case .image(let image):
                                    VStack(alignment: .center, spacing: 4) {
                                        Text("生成的图片")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        GeometryReader { geo in
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: min(geo.size.width * 0.9, 300), height: 300)
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                                )
                                        }
                                        .frame(height: 300)
                                    }
                                    .frame(maxWidth: 300)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray5))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 4)
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .id(UUID()) // 强制每次刷新
    }
}

// 输入指示器
struct TypingIndicator: View {
    @State private var animationOffset = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .offset(y: sin(animationOffset + Double(index) * 0.5) * 2)
            }
        }
        .foregroundColor(.gray)
        .onAppear {
            withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                animationOffset = 2 * .pi
            }
        }
    }
}

#Preview {
    ChatView()
}