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
    @State private var imagePickerVisible = false
    @State private var selectedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var messageCounter: Int = 0
    @FocusState private var isInputFocused: Bool
    
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
        VStack(spacing: 0) {
            // 显示聊天记录
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                                .onChange(of: message.content) { _, _ in
                                    DispatchQueue.main.async {
                                        // 强制刷新整个UI
                                        self.messageCounter += 1
                                    }
                                }
                                .transition(.opacity)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 10)
                    .id(messageCounter) // 使用计数器强制刷新
                    .animation(.easeOut(duration: 0.2), value: viewModel.messages.count)
                }
                .background(Color(.systemBackground))
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
            
            Divider()
            
            // 如果有选择的图片，显示预览和提示
            if let userImage = viewModel.userImage {
                HStack {
                    Image(uiImage: userImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    
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
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            
            // 显示错误信息（如果有）
            if let error = viewModel.error {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            
            // 输入区域
            HStack(alignment: .bottom, spacing: 10) {
                // 图片选择按钮
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
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
                ZStack(alignment: .leading) {
                    if viewModel.inputMessage.isEmpty {
                        Text("想要生成什么？")
                            .foregroundColor(.gray.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                    }
                    
                    TextEditor(text: $viewModel.inputMessage)
                        .font(.system(size: 17))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .frame(height: textEditorHeight())
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                        .disabled(viewModel.isLoading)
                        .lineSpacing(2) // 设置行间距
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isInputFocused ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
                
                // 加载指示器或发送按钮
                if viewModel.isLoading {
                    ProgressView()
                        .frame(width: 40, height: 40)
                } else {
                    Button(action: {
                        isInputFocused = false
                        Task {
                            await viewModel.sendMessage()
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(viewModel.inputMessage.isEmpty && viewModel.userImage == nil ? .gray : .blue)
                    }
                    .disabled(viewModel.inputMessage.isEmpty && viewModel.userImage == nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .animation(.easeOut(duration: 0.2), value: viewModel.isLoading)
        }
        .background(Color(.secondarySystemBackground))
    }
    
    // 计算输入框高度
    private func textEditorHeight() -> CGFloat {
        let text = viewModel.inputMessage
        let width = UIScreen.main.bounds.width - 120 // 减去左右边距和其他控件的宽度
        
        let font = UIFont.systemFont(ofSize: 17) // 使用标准字体大小
        let lineHeight: CGFloat = font.lineHeight // 获取字体的行高
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2 // 设置行间距
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        
        let height = ceil(boundingBox.height)
        let minHeight: CGFloat = lineHeight + 24 // 单行文本高度 + 上下内边距
        return max(minHeight, min(height + 24, 120)) // 基础高度为单行高度，最大120，上下各加12点内边距
    }
}

// 消息视图
struct MessageView: View {
    let message: ChatMessage
    @State private var viewId = UUID()
    @State private var enlargedImage: UIImage? = nil
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        messageContent
            .fullScreenCover(item: Binding(
                get: { enlargedImage.map { ImageViewerData(image: $0) } },
                set: { enlargedImage = $0?.image }
            )) { imageData in
                ImageViewerSheet(image: imageData.image) {
                    enlargedImage = nil
                }
            }
    }
    
    // 用户头像颜色
    private var userAvatarColor: Color {
        Color.blue
    }
    
    // AI头像颜色
    private var aiAvatarColor: Color {
        Color.purple
    }
    
    // 用户气泡背景色
    private var userBubbleColor: Color {
        colorScheme == .dark ? Color.blue.opacity(0.8) : Color.blue.opacity(0.2)
    }
    
    // AI气泡背景色
    private var aiBubbleColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.8) : Color.gray.opacity(0.2)
    }
    
    // 正常消息内容视图
    private var messageContent: some View {
        HStack(alignment: .top, spacing: 8) {
            // AI消息左侧显示头像
            if message.role == .assistant {
                Circle()
                    .fill(aiAvatarColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "brain")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            } else {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // 消息头部
                if message.role == .assistant {
                    Text("Gemini")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                
                // 消息内容
                messageBubble
                
                // 生成中指示器
                if message.isGenerating {
                    HStack {
                        Text("正在生成")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TypingIndicator()
                    }
                    .padding(.top, 2)
                    .padding(.leading, 4)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
            
            // 用户消息右侧显示头像
            if message.role == .user {
                Circle()
                    .fill(userAvatarColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            } else {
                Spacer()
            }
        }
        .padding(.vertical, 2)
        .onChange(of: message.content) { _, _ in
            viewId = UUID()
        }
        .id(viewId)
    }
    
    // 消息气泡
    private var messageBubble: some View {
        Group {
            switch message.content {
            case .text(let text):
                Text(text)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(12)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                
            case .markdown(let markdownText):
                Markdown(markdownText)
                    .textSelection(.enabled)
                    .markdownTheme(Theme.custom)
                    .padding(12)
                    .fixedSize(horizontal: false, vertical: true)
                
            case .image(let image):
                Button(action: {
                    enlargedImage = image
                }) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 250, maxHeight: 250)
                        .cornerRadius(12)
                        .overlay(
                            Text("点击查看")
                                .font(.caption)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                                .padding(8),
                            alignment: .bottom
                        )
                }
                .padding(4)
                
            case .mixedContent(let items):
                VStack(alignment: .leading, spacing: 8) {
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
                                    .padding(.vertical, 2)
                            } else {
                                Text(text)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.vertical, 2)
                            }
                            
                        case .markdown(let markdownText, _):
                            Markdown(markdownText)
                                .textSelection(.enabled)
                                .markdownTheme(Theme.custom)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 2)
                            
                        case .image(let image, _):
                            Button(action: {
                                enlargedImage = image
                            }) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 250, maxHeight: 250)
                                    .cornerRadius(8)
                                    .overlay(
                                        Text("点击查看")
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.black.opacity(0.6))
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                            .padding(8),
                                        alignment: .bottom
                                    )
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

// 用于fullScreenCover的数据模型
struct ImageViewerData: Identifiable {
    let id = UUID()
    let image: UIImage
}

// 图片查看器Sheet视图
struct ImageViewerSheet: View {
    let image: UIImage
    let onClose: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
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
                
                // 关闭按钮 - 左上角
                VStack {
                    HStack {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(Circle().fill(Color(.systemGray6)))
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                    }
                    .padding(.top, geometry.safeAreaInsets.top + 10)
                    
                    Spacer()
                }
                
                // 保存和分享按钮 - 右下角
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        // 分享按钮
                        Button {
                            saveImageToPhotos()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(Circle().fill(Color(.systemGray6)))
                        }
                        
                        // 直接保存到相册按钮
                        Button {
                            saveImageDirectlyToPhotos()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .font(.title3)
                                Text("保存")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(.systemGray6)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 10)
                }
            }
        }
        .alert(isPresented: $showSaveAlert) {
            Alert(title: Text("提示"), message: Text(saveAlertMessage), dismissButton: .default(Text("确定")))
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
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

// 气泡形状
struct BubbleShape: Shape {
    let isFromCurrentUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 16
        let triangleSize: CGFloat = 8
        
        var path = Path()
        
        if isFromCurrentUser {
            // 右边的三角形气泡
            path.move(to: CGPoint(x: rect.maxX - triangleSize, y: rect.minY + cornerRadius + triangleSize))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius))
            path.addLine(to: CGPoint(x: rect.maxX - triangleSize, y: rect.minY + cornerRadius))
            
            // 其余的圆角矩形
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                        radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                        radius: cornerRadius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                        radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius + triangleSize))
        } else {
            // 左边的三角形气泡
            path.move(to: CGPoint(x: rect.minX + triangleSize, y: rect.minY + cornerRadius + triangleSize))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addLine(to: CGPoint(x: rect.minX + triangleSize, y: rect.minY + cornerRadius))
            
            // 其余的圆角矩形
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                        radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                        radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                        radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius + triangleSize))
        }
        
        return path
    }
}

// 输入指示器
struct TypingIndicator: View {
    @State private var animationOffset = 0.0
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .offset(y: sin(animationOffset + Double(index) * 0.5) * 2)
                    .opacity(0.5 + sin(animationOffset + Double(index) * 0.5) * 0.5)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
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

#Preview {
    NavigationView {
        ChatView()
    }
}