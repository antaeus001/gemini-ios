import SwiftUI

// 工具视图 - 样例库
struct ToolsView: View {
    @State private var selectedCategory: String = "全部"
    let categories = ["全部", "图像", "文本", "设计", "代码", "上传图片"]
    @EnvironmentObject var chatViewModel: ChatViewModel
    @State private var showingChatView = false
    @State private var showingImageUploader = false
    
    // 样例数据
    let examples = [
        ToolExample(title: "生成风景图", description: "创建一个山水风景图", category: "图像", prompt: "创建一个高山湖泊的风景图，夕阳西下，有远处的山脉和近处的松树"),
        ToolExample(title: "编写故事", description: "根据主题创作短篇故事", category: "文本", prompt: "写一个关于太空探险的短篇科幻故事，主角是一位年轻宇航员"),
        ToolExample(title: "App界面设计", description: "设计移动应用界面", category: "设计", prompt: "设计一个健康追踪App的主界面，包含步数统计、睡眠监测和心率数据"),
        ToolExample(title: "代码生成", description: "生成示例代码", category: "代码", prompt: "用Swift写一个简单的待办事项App，包含添加、删除和标记完成功能"),
        ToolExample(title: "图像修复", description: "修复或增强图像", category: "图像", prompt: "增强这张照片的色彩和清晰度，使其更加生动"),
        ToolExample(title: "写作助手", description: "改进文章或论文", category: "文本", prompt: "帮我修改这篇关于人工智能发展的文章，提高其专业性和可读性"),
        ToolExample(title: "徽标设计", description: "创建公司徽标", category: "设计", prompt: "为一家名为'EcoTech'的环保科技公司设计一个现代简约风格的徽标"),
        ToolExample(title: "API文档", description: "生成API使用文档", category: "代码", prompt: "为一个用户认证API编写详细的使用文档，包括所有端点和参数说明")
    ]
    
    // 图片上传样例数据
    let imageUploadExamples = [
        ToolExample(title: "图片分析", description: "上传图片获取AI分析", category: "上传图片", prompt: "请分析这张图片并告诉我你看到了什么内容。"),
        ToolExample(title: "图像编辑", description: "上传图片进行AI编辑处理", category: "上传图片", prompt: "请帮我编辑这张图片，提高清晰度和对比度。"),
        ToolExample(title: "内容识别", description: "识别图片中的文字和物体", category: "上传图片", prompt: "请识别图片中的所有文字和主要物体。"),
        ToolExample(title: "创意描述", description: "获取图片的创意文字描述", category: "上传图片", prompt: "请用富有创意的语言描述这张图片的内容和氛围。")
    ]
    
    var filteredExamples: [ToolExample] {
        if selectedCategory == "全部" {
            return examples
        } else if selectedCategory == "上传图片" {
            return imageUploadExamples
        } else {
            return examples.filter { $0.category == selectedCategory }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签固定布局
            ZStack {
                Rectangle()
                    .fill(Color(.systemBackground))
                    .frame(height: 50)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            TabButton(
                                title: category,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // 分割线
            Divider()
            
            // 样例列表，现在对所有分类都使用同样的列表视图
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(filteredExamples) { example in
                        if example.category == "上传图片" {
                            ImageUploadExampleCard(example: example, showImageUploader: $showingImageUploader)
                                .padding(.horizontal)
                        } else {
                            ToolExampleCard(example: example)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $showingImageUploader) {
            NavigationView {
                ImageUploadView()
                    .navigationBarTitle("图片上传", displayMode: .inline)
                    .navigationBarItems(trailing: Button(action: {
                        showingImageUploader = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    })
            }
        }
    }
}

// 标签按钮组件
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title == "上传图片" ? "上传图片" : title)
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? .blue : .primary)
                .background(isSelected ? Color.gray.opacity(0.1) : Color.clear)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
    }
}

// 示例卡片组件
struct ToolExampleCard: View {
    let example: ToolExample
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(example.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(example.category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(categoryColor(example.category).opacity(0.1))
                        .foregroundColor(categoryColor(example.category))
                        .cornerRadius(8)
                }
                
                Text(example.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            ToolExampleDetailView(example: example, isPresented: $showingDetail)
        }
    }
    
    // 根据分类返回颜色
    func categoryColor(_ category: String) -> Color {
        switch category {
        case "图像":
            return .purple
        case "文本":
            return .blue
        case "设计":
            return .green
        case "代码":
            return .orange
        default:
            return .gray
        }
    }
}

// 示例详情视图
struct ToolExampleDetailView: View {
    let example: ToolExample
    @Binding var isPresented: Bool
    @State private var prompt: String
    @EnvironmentObject var chatViewModel: ChatViewModel
    @State private var shouldNavigateToChat = false
    
    init(example: ToolExample, isPresented: Binding<Bool>) {
        self.example = example
        self._isPresented = isPresented
        self._prompt = State(initialValue: example.prompt)
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题
                Text(example.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // 描述
                Text(example.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                // 分类标签
                HStack {
                    Text(example.category)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    
                    Spacer()
                }
                
                Divider()
                
                // 提示文本区域
                VStack(alignment: .leading) {
                    Text("提示词")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    TextEditor(text: $prompt)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .frame(height: 200)
                }
                
                Spacer()
                
                // 按钮
                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("关闭")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        // 直接创建新会话，不显示确认对话框
                        chatViewModel.inputMessage = prompt
                        chatViewModel.clearMessages()
                        isPresented = false
                        
                        // 通知需要切换到聊天标签
                        NotificationCenter.default.post(name: NSNotification.Name("SwitchToChat"), object: nil)
                    }) {
                        Text("开始新会话")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .navigationBarTitle("示例详情", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: {
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            })
        }
    }
}

// 图片上传示例卡片
struct ImageUploadExampleCard: View {
    let example: ToolExample
    @Binding var showImageUploader: Bool
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(example.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("上传图片")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                
                Text(example.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            ImageExampleDetailView(example: example, isPresented: $showingDetail, showImageUploader: $showImageUploader)
        }
    }
}

// 图片上传示例详情视图
struct ImageExampleDetailView: View {
    let example: ToolExample
    @Binding var isPresented: Bool
    @Binding var showImageUploader: Bool
    @State private var prompt: String
    @EnvironmentObject var chatViewModel: ChatViewModel
    
    init(example: ToolExample, isPresented: Binding<Bool>, showImageUploader: Binding<Bool>) {
        self.example = example
        self._isPresented = isPresented
        self._showImageUploader = showImageUploader
        self._prompt = State(initialValue: example.prompt)
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题
                Text(example.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // 描述
                Text(example.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                // 分类标签
                HStack {
                    Text(example.category)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    
                    Spacer()
                }
                
                Divider()
                
                // 提示文本区域
                VStack(alignment: .leading) {
                    Text("提示词")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    TextEditor(text: $prompt)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .frame(height: 200)
                }
                
                Spacer()
                
                // 按钮
                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("关闭")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        // 直接创建新会话，不显示确认对话框
                        chatViewModel.inputMessage = prompt
                        chatViewModel.clearMessages()
                        isPresented = false
                        
                        // 通知需要切换到聊天标签
                        NotificationCenter.default.post(name: NSNotification.Name("SwitchToChat"), object: nil)
                    }) {
                        Text("开始新会话")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .navigationBarTitle("示例详情", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: {
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            })
        }
    }
}

// 样例数据模型
struct ToolExample: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let category: String
    let prompt: String
}

// 图片上传视图
struct ImageUploadView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @State private var showingImagePicker = false
    @State private var showingLoading = false
    @State private var uploadedImageURL: String? = nil
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                if chatViewModel.userImages.count > 0 {
                    Image(uiImage: chatViewModel.userImages.first!)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    
                    if let url = uploadedImageURL {
                        VStack {
                            Text("图片已上传，链接：")
                                .font(.subheadline)
                            Text(url)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .onTapGesture {
                                    UIPasteboard.general.string = url
                                }
                                
                            Button(action: {
                                // 使用上传的图片URL创建对话
                                startChatWithImageUrl(url)
                            }) {
                                Text("开始对话")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            chatViewModel.userImages = []
                            uploadedImageURL = nil
                            errorMessage = nil
                        }) {
                            Text("清除")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            uploadImage()
                        }) {
                            HStack {
                                if showingLoading {
                                    ProgressView()
                                        .frame(width: 16, height: 16)
                                }
                                Text(uploadedImageURL == nil ? "上传图片" : "重新上传")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(showingLoading)
                    }
                    .padding(.horizontal)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .frame(height: 200)
                            .padding(.horizontal)
                        
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            
                            Text("从相册选择图片")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .padding(.top, 8)
                            
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                Text("选择图片")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .padding(.top, 15)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: Binding(
                get: { chatViewModel.userImages.first },
                set: { newImage in
                    if let newImage = newImage {
                        chatViewModel.userImages = [newImage]
                    } else {
                        chatViewModel.userImages = []
                    }
                }
            ))
        }
    }
    
    // 上传图片方法
    private func uploadImage() {
        guard !chatViewModel.userImages.isEmpty else { return }
        
        // 设置加载状态
        showingLoading = true
        errorMessage = nil
        
        // 执行上传
        Task {
            do {
                if let imageUrl = await chatViewModel.uploadUserImage() {
                    // 更新UI
                    await MainActor.run {
                        uploadedImageURL = imageUrl
                        showingLoading = false
                    }
                } else {
                    // 显示错误
                    await MainActor.run {
                        errorMessage = chatViewModel.error ?? "上传失败"
                        showingLoading = false
                    }
                }
            }
        }
    }
    
    // 启动使用图片URL的对话
    private func startChatWithImageUrl(_ imageUrl: String) {
        // 通知需要切换到聊天标签
        NotificationCenter.default.post(name: NSNotification.Name("SwitchToChat"), object: nil)
        
        // 使用延迟允许视图有时间切换
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                // 清除当前会话
                chatViewModel.clearMessages()
                
                // 创建一个初始提示，让模型知道它将处理图像
                let initialPrompt = "请分析这张图片并告诉我你看到了什么内容。"
                
                // 启动对话
                try? await chatViewModel.sendMessageWithImageUrl(prompt: initialPrompt, imageUrl: imageUrl)
            }
        }
    }
}

// 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    NavigationView {
        ToolsView()
            .navigationBarTitle("样例库", displayMode: .inline)
    }
} 