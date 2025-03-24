import SwiftUI
import UIKit
import PhotosUI
import MarkdownUI
import Photos

// 测试Markdown渲染视图
struct MarkdownTestView: View {
    let markdownText = """
    # 测试标题

    这是**粗体文本**和*斜体文本*。

    ## 列表测试
    
    * 列表项1
    * 列表项2
    * 列表项3
    
    ```swift
    let code = "代码块测试"
    print(code)
    ```
    """
    
    var body: some View {
        VStack {
            Text("测试原始文本").font(.headline)
            Text(markdownText)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            
            Text("测试Markdown渲染").font(.headline)
            Markdown(markdownText)
                .markdownTheme(Theme.custom)
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
    }
}

// 自定义Markdown主题
extension Theme {
    static var custom: Theme {
        Theme()
            .code {
                FontFamilyVariant(.monospaced)
                FontWeight(.medium)
                BackgroundColor(Color(.systemGray6))
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.8))
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.medium)
                        FontSize(.em(1.2))
                    }
            }
            .link {
                ForegroundColor(.blue)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.25), bottom: .em(0.25))
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

// 图片查看器 - 超简单实现
struct SimpleImageViewer: View {
    let imageData: Data  // 使用Data而不是UIImage
    @Binding var isPresented: Bool
    @State private var uiImage: UIImage?
    
    init(imageData: Data, isPresented: Binding<Bool>) {
        self.imageData = imageData
        self._isPresented = isPresented
        print("初始化SimpleImageViewer，数据大小：\(imageData.count)字节")
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color.black
                .edgesIgnoringSafeArea(.all)
                .zIndex(999)
                .onTapGesture {
                    isPresented = false
                }
            
            // 内容
            VStack(spacing: 20) {
                // 关闭按钮
                HStack {
                    Button(action: {
                        print("关闭按钮被点击")
                        isPresented = false
                    }) {
                        Text("关闭")
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(20)
                    }
                    .padding(.top, 50)
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                Spacer()
                
                if let image = uiImage {
                    Text("图片尺寸: \(Int(image.size.width)) x \(Int(image.size.height))")
                        .foregroundColor(.white)
                        .padding()
                    
                    // 图片
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                } else {
                    Text("正在加载图片...")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .onAppear {
                            print("图片视图出现但尚未加载图片")
                        }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1000)
        }
        .transition(.opacity)
        .onAppear {
            print("SimpleImageViewer已显示")
            // 确保在显示时加载图片
            if uiImage == nil {
                loadImage()
            }
        }
    }
    
    private func loadImage() {
        if let image = UIImage(data: imageData) {
            print("成功加载图片，尺寸：\(image.size.width) x \(image.size.height)")
            self.uiImage = image
        } else {
            print("无法从数据创建图片，数据大小：\(imageData.count)")
        }
    }
}

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showingExamples = false
    @State private var imagePickerVisible = false
    @State private var selectedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var messageCounter: Int = 0
    
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
                                .onChange(of: message.content) { _, _ in
                                    DispatchQueue.main.async {
                                        // 强制刷新整个UI
                                        self.messageCounter += 1
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                    .id(messageCounter) // 使用计数器强制刷新
                }
                .background(Color(.systemBackground))
                .shadow(radius: 5)
                .padding()
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom()
                }
                .onChange(of: messageCounter) { _, _ in
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
    let message: ChatMessage
    @State private var imageScale: CGFloat = 1.0
    @State private var viewId = UUID() // 添加唯一ID用于强制刷新
    @State private var isImageViewerPresented = false
    @State private var selectedImageData: Data? = nil  // 使用Data而不是UIImage
    
    // 检查是否为欢迎消息
    private var isWelcomeMessage: Bool {
        if message.role == .assistant,
           case .markdown(let content) = message.content,
           content.contains("请您上传您想要调整的图片") {
            return true
        }
        return false
    }
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading) {
                // 依据消息角色决定头像显示
                if message.role != .user {
                    HStack {
                        Image(systemName: "brain")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.purple))
                        
                        Text("Gemini")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
                
                switch message.content {
                case .text(let text):
                    // 移除换行相关的判断，直接统一使用Text渲染
                    Text(text)
                        .padding(10)
                        .background(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    
                case .markdown(let markdownText):
                    // 直接使用Markdown组件渲染，确保保留所有格式
                    Markdown(markdownText)
                        .textSelection(.enabled)
                        .markdownTheme(Theme.custom)
                        .padding(10)
                        .background(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .fixedSize(horizontal: false, vertical: true)
                        .onAppear {
                            print("渲染Markdown内容，长度: \(markdownText.count), 前缀: \(markdownText.prefix(50))")
                            // 打印所有换行符位置
                            let newlineIndexes = markdownText.indices.filter { markdownText[$0] == "\n" }
                            print("换行符位置: \(newlineIndexes.count)个")
                        }
                    
                case .image(let image):
                    Button(action: {
                        if let imageData = image.jpegData(compressionQuality: 1.0) ?? image.pngData() {
                            print("准备显示图片，数据大小：\(imageData.count)字节")
                            self.selectedImageData = imageData
                            DispatchQueue.main.async {
                                self.isImageViewerPresented = true
                                print("已设置isImageViewerPresented=true")
                            }
                        } else {
                            print("无法获取图片数据")
                        }
                    }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .cornerRadius(10)
                            .overlay(
                                Text("点击查看大图")
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(5)
                                    .padding(10),
                                alignment: .bottom
                            )
                    }
                    
                case .mixedContent(let items):
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            switch item {
                            case .text(let text, _):
                                // 检测text内容是否包含markdown格式
                                if text.contains("**") || text.contains("*") || 
                                   text.contains("#") || text.contains("```") || 
                                   text.contains("•") || text.contains("- ") || 
                                   text.contains("* ") {
                                    // 如果包含markdown标记，使用Markdown渲染
                                    Markdown(text)
                                        .textSelection(.enabled)
                                        .markdownTheme(Theme.custom)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(4)
                                } else {
                                    // 否则使用普通Text渲染
                                    Text(text)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                            case .markdown(let markdownText, _):
                                // Markdown内容，始终使用Markdown组件渲染
                                Markdown(markdownText)
                                    .textSelection(.enabled)
                                    .markdownTheme(Theme.custom)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                            case .image(let image, _):
                                Button(action: {
                                    if let imageData = image.jpegData(compressionQuality: 1.0) ?? image.pngData() {
                                        print("准备显示混合内容图片，数据大小：\(imageData.count)字节")
                                        self.selectedImageData = imageData
                                        DispatchQueue.main.async {
                                            self.isImageViewerPresented = true
                                            print("已设置混合内容isImageViewerPresented=true")
                                        }
                                    } else {
                                        print("无法获取混合内容图片数据")
                                    }
                                }) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 300, maxHeight: 300)
                                        .cornerRadius(10)
                                        .overlay(
                                            Text("点击查看大图")
                                                .foregroundColor(.white)
                                                .padding(6)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(5)
                                                .padding(10),
                                            alignment: .bottom
                                        )
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(10)
                }
                
                // 如果消息处于生成中状态，显示指示器
                if message.isGenerating {
                    HStack {
                        Text("正在生成...")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TypingIndicator()
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: message.role == .user ? .trailing : .leading)
            .onChange(of: message.content) { _, _ in
                // 当内容变化时强制更新视图
                viewId = UUID()
            }
            .id(viewId) // 使用viewId强制刷新
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .fullScreenCover(isPresented: $isImageViewerPresented, onDismiss: {
            print("图片查看器已关闭")
            selectedImageData = nil
        }) {
            if let imageData = selectedImageData {
                SimpleImageViewer(imageData: imageData, isPresented: $isImageViewerPresented)
            } else {
                Text("无图片数据")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        isImageViewerPresented = false
                    }
            }
        }
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