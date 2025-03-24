import SwiftUI

// 工具视图 - 样例库
struct ToolsView: View {
    @State private var selectedCategory: String = "全部"
    let categories = ["全部", "图像", "文本", "设计", "代码"]
    @EnvironmentObject var chatViewModel: ChatViewModel
    @State private var showingChatView = false
    
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
    
    var filteredExamples: [ToolExample] {
        if selectedCategory == "全部" {
            return examples
        } else {
            return examples.filter { $0.category == selectedCategory }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 分类选择器
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(categories, id: \.self) { category in
                        CategoryButton(
                            title: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(Color(.systemBackground))
            
            // 分割线
            Divider()
            
            // 样例列表
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(filteredExamples) { example in
                        ToolExampleCard(example: example)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

// 分类按钮组件
struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .foregroundColor(isSelected ? .blue : .primary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
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
                        // 使用这个提示词
                        chatViewModel.inputMessage = prompt
                        isPresented = false
                        
                        // 通知需要切换到聊天标签
                        NotificationCenter.default.post(name: NSNotification.Name("SwitchToChat"), object: nil)
                    }) {
                        Text("使用此提示")
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

#Preview {
    NavigationView {
        ToolsView()
            .navigationBarTitle("样例库", displayMode: .inline)
    }
} 