import SwiftUI

struct ExamplesView: View {
    @State private var navigateTo: AnyView?
    @State private var isNavigating = false
    
    // 示例功能项
    private let examples: [ExampleItem] = [
        ExampleItem(title: "图像生成", icon: "photo.fill", color: .blue, description: "利用AI创建全新的图像"),
        ExampleItem(title: "图像处理", icon: "wand.and.stars", color: .purple, description: "增强和修改现有图像"),
        ExampleItem(title: "图文故事", icon: "book.fill", color: .green, description: "创建配有图片的精彩故事"),
        ExampleItem(title: "去水印", icon: "seal.fill", color: .orange, description: "移除图像中的水印和标记"),
        ExampleItem(title: "老照片修复", icon: "photo.stack.fill", color: .brown, description: "修复和增强老旧照片"),
        ExampleItem(title: "电商换模特", icon: "person.crop.rectangle.fill", color: .pink, description: "替换产品图片中的模特"),
        ExampleItem(title: "商品海报", icon: "tag.fill", color: .red, description: "创建专业的商品推广海报"),
        ExampleItem(title: "复杂知识讲解", icon: "brain.head.profile", color: .indigo, description: "通过图文解释复杂概念"),
        ExampleItem(title: "表情包", icon: "face.smiling.fill", color: .yellow, description: "创建有趣的表情包和贴纸"),
        ExampleItem(title: "角色设计", icon: "person.fill.viewfinder", color: .mint, description: "设计独特的角色和形象"),
        ExampleItem(title: "解释自然现象", icon: "leaf.fill", color: .green, description: "通过图像解释自然规律和现象")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景渐变
                LinearGradient(
                    gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 顶部标题
                        Text("Gemini 2.0 示例")
                            .font(.system(size: 32, weight: .bold))
                            .padding(.top, 20)
                        
                        Text("选择一个功能来体验 Gemini 的能力")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 10)
                        
                        // 功能网格
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(examples) { example in
                                ExampleCard(example: example)
                                    .onTapGesture {
                                        let chatViewModel = ChatViewModel()
                                        let prompt = generatePrompt(for: example.title)
                                        
                                        // 设置导航目标为ChatView，并传入相应的提示词
                                        navigateTo = AnyView(
                                            ChatView(viewModel: chatViewModel)
                                                .onAppear {
                                                    Task {
                                                        await chatViewModel.startGenerationChat(prompt: prompt)
                                                    }
                                                }
                                        )
                                        isNavigating = true
                                    }
                            }
                        }
                        .padding()
                    }
                }
                
                if isNavigating, let destination = navigateTo {
                    destination
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationBarItems(
                trailing: NavigationLink(destination: ChatView()) {
                    Text("开始对话")
                        .fontWeight(.medium)
                }
            )
        }
    }
    
    // 根据功能类型生成适当的提示词
    private func generatePrompt(for exampleType: String) -> String {
        switch exampleType {
        case "图像生成":
            return "创建一张未来城市的图像，有飞行汽车和高科技建筑"
        case "图像处理":
            return "帮我把这张图片的颜色调整得更明亮，增加对比度"
        case "图文故事":
            return "创作一个关于宇宙探索的短篇故事，配上相关插图"
        case "去水印":
            return "请移除这张图片中的水印，让图像看起来更干净"
        case "老照片修复":
            return "修复这张老照片，去除划痕和污渍，并增强清晰度"
        case "电商换模特":
            return "将这件衣服换到不同体型的模特上展示"
        case "商品海报":
            return "为一款新型智能手表创建一张吸引人的促销海报"
        case "复杂知识讲解":
            return "用图文解释量子力学的双缝实验及其意义"
        case "表情包":
            return "创建一组表达\"惊讶\"情绪的有趣表情包"
        case "角色设计":
            return "设计一个未来科幻风格的游戏角色，有详细的视觉特征"
        case "解释自然现象":
            return "用图文解释为什么天空是蓝色的以及日落时会变红"
        default:
            return "用Gemini的能力，展示一个创意图文作品"
        }
    }
}

// 示例项目结构
struct ExampleItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let description: String
}

// 示例卡片视图
struct ExampleCard: View {
    let example: ExampleItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 图标
            Image(systemName: example.icon)
                .font(.largeTitle)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(example.color)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(color: example.color.opacity(0.3), radius: 5, x: 0, y: 3)
            
            // 标题和描述
            Text(example.title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(example.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            Spacer()
        }
        .frame(height: 160)
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    ExamplesView()
}