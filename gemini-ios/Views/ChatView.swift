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
    @State private var viewId = UUID()
    @State private var enlargedImage: UIImage? = nil
    
    var body: some View {
        ZStack {
            // 正常的消息内容
            if enlargedImage == nil {
                messageContent
            }
            
            // 放大的图片覆盖层
            if let image = enlargedImage {
                ZStack {
                    // 背景遮罩
                    Color.black.opacity(0.9)
                        .edgesIgnoringSafeArea(.all)
                    
                    // 图片和控制按钮
                    VStack(spacing: 0) {
                        // 顶部工具栏
                        HStack {
                            Button {
                                enlargedImage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.black.opacity(0.7)))
                            }
                            .padding(.leading, 20)
                            
                            Spacer()
                        }
                        .padding(.top, 50)
                        .padding(.bottom, 20)
                        
                        // 图片显示 - 占满中间区域
                        Spacer()
                        ImageViewer(image: image, onClose: {
                            enlargedImage = nil
                        })
                        Spacer()
                    }
                }
                .zIndex(999) // 确保在最上层
                .transition(.opacity)
                .edgesIgnoringSafeArea(.all)
            }
        }
    }
    
    // 正常消息内容视图
    private var messageContent: some View {
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
                    Text(text)
                        .padding(10)
                        .background(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    
                case .markdown(let markdownText):
                    Markdown(markdownText)
                        .textSelection(.enabled)
                        .markdownTheme(Theme.custom)
                        .padding(10)
                        .background(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .fixedSize(horizontal: false, vertical: true)
                    
                case .image(let image):
                    Button(action: {
                        print("直接显示图片: \(image.size.width) x \(image.size.height)")
                        self.enlargedImage = image
                    }) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .cornerRadius(10)
                            .overlay(
                                Text("点击查看大图")
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .padding(8),
                                alignment: .bottom
                            )
                    }
                    
                case .mixedContent(let items):
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            switch item {
                            case .text(let text, _):
                                if text.contains("**") || text.contains("*") || 
                                   text.contains("#") || text.contains("```") || 
                                   text.contains("•") || text.contains("- ") || 
                                   text.contains("* ") {
                                    Markdown(text)
                                        .textSelection(.enabled)
                                        .markdownTheme(Theme.custom)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(4)
                                } else {
                                    Text(text)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                            case .markdown(let markdownText, _):
                                Markdown(markdownText)
                                    .textSelection(.enabled)
                                    .markdownTheme(Theme.custom)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                            case .image(let image, _):
                                Button(action: {
                                    print("直接显示混合内容图片: \(image.size.width) x \(image.size.height)")
                                    self.enlargedImage = image
                                }) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 300, maxHeight: 300)
                                        .cornerRadius(10)
                                        .overlay(
                                            Text("点击查看大图")
                                                .font(.caption)
                                                .padding(4)
                                                .background(Color.black.opacity(0.7))
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                                .padding(8),
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
                viewId = UUID()
            }
            .id(viewId)
            
            if message.role == .assistant {
                Spacer()
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

// 图片保存工具类 - 处理保存回调
class ImageSaver: NSObject {
    var completion: (Bool, Error?) -> Void
    
    init(completion: @escaping (Bool, Error?) -> Void) {
        self.completion = completion
        super.init()
    }
    
    // 图片保存回调
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            completion(false, error)
        } else {
            completion(true, nil)
        }
    }
    
    // 保存图片到相册
    func saveToPhotos(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
}

// 带手势支持的图片查看器组件
struct ImageViewer: View {
    let image: UIImage
    let onClose: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    
    var body: some View {
        ZStack {
            // 图片区域
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            // 限制缩放范围
                            let newScale = scale * delta
                            scale = min(max(newScale, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                            offset = newOffset
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation {
                                if scale > 1.5 {
                                    // 如果放大了，双击恢复原始大小
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    // 如果是原始大小，双击放大到2倍
                                    scale = 2.0
                                }
                            }
                        }
                )
                .onTapGesture {
                    // 单击关闭（仅当未放大时）
                    if scale <= 1.1 {
                        onClose()
                    }
                }
            
            // 工具按钮浮层
            VStack {
                HStack {
                    // 直接保存到相册按钮
                    Button {
                        saveImageDirectlyToPhotos()
                    } label: {
                        HStack {
                            Image(systemName: "photo")
                                .font(.title3)
                            Text("保存")
                                .font(.subheadline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.leading, 20)
                    
                    Spacer()
                    
                    // 分享按钮
                    Button {
                        saveImageToPhotos()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.trailing, 20)
                }
                
                Spacer()
            }
            .padding(.top, 20)
        }
        .onAppear {
            print("图片查看器已显示，尺寸: \(image.size.width) x \(image.size.height)")
        }
        .alert(isPresented: $showSaveAlert) {
            Alert(title: Text("提示"), message: Text(saveAlertMessage), dismissButton: .default(Text("确定")))
        }
    }
    
    // 直接保存到相册
    private func saveImageDirectlyToPhotos() {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    // 使用辅助类保存图片
                    let imageSaver = ImageSaver { success, error in
                        DispatchQueue.main.async {
                            if success {
                                print("图片已成功保存到相册")
                                self.saveAlertMessage = "图片已保存到相册"
                            } else {
                                print("保存图片错误: \(error?.localizedDescription ?? "未知错误")")
                                self.saveAlertMessage = "保存图片失败: \(error?.localizedDescription ?? "未知错误")"
                            }
                            self.showSaveAlert = true
                        }
                    }
                    imageSaver.saveToPhotos(image: self.image)
                    
                case .denied, .restricted:
                    self.saveAlertMessage = "无法保存图片，请在设置中允许应用访问您的相册"
                    self.showSaveAlert = true
                case .notDetermined:
                    self.saveAlertMessage = "请先授权访问相册"
                    self.showSaveAlert = true
                @unknown default:
                    self.saveAlertMessage = "未知错误，无法保存图片"
                    self.showSaveAlert = true
                }
            }
        }
    }
    
    // 使用分享菜单保存图片
    private func saveImageToPhotos() {
        // 先尝试使用ActivityViewController分享
        let imageToShare = image
        
        // 创建一个临时图片文件URL
        let imageName = "Gemini_Image_\(Date().timeIntervalSince1970).jpeg"
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
        let imageFileURL = tempDirectoryURL.appendingPathComponent(imageName)
        
        do {
            // 将图片保存为JPEG文件
            if let jpegData = imageToShare.jpegData(compressionQuality: 0.9) {
                try jpegData.write(to: imageFileURL)
                
                // 创建活动视图控制器
                let activityItems: [Any] = [imageFileURL]
                let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                
                // 在iPad上设置弹出框的来源视图
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    activityVC.popoverPresentationController?.sourceView = rootViewController.view
                    activityVC.popoverPresentationController?.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
                    activityVC.popoverPresentationController?.permittedArrowDirections = []
                    
                    // 显示分享表单
                    rootViewController.present(activityVC, animated: true, completion: nil)
                    
                    // 处理完成回调（可选）
                    activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, error in
                        // 删除临时文件
                        do {
                            try fileManager.removeItem(at: imageFileURL)
                        } catch {
                            print("无法删除临时文件: \(error.localizedDescription)")
                        }
                        
                        // 显示结果
                        DispatchQueue.main.async {
                            if let error = error {
                                self.saveAlertMessage = "图片分享失败: \(error.localizedDescription)"
                                self.showSaveAlert = true
                            } else if completed {
                                self.saveAlertMessage = "操作已完成"
                                self.showSaveAlert = true
                            }
                        }
                    }
                }
            } else {
                self.saveAlertMessage = "无法创建图片数据"
                self.showSaveAlert = true
            }
        } catch {
            print("保存图片错误: \(error.localizedDescription)")
            self.saveAlertMessage = "保存图片失败: \(error.localizedDescription)"
            self.showSaveAlert = true
        }
    }
}

#Preview {
    ChatView()
}