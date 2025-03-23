import SwiftUI

struct MainView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标题和说明
                VStack {
                    Text("Gemini 2.0 Flash")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("基于 Google Gemini 2.0 Flash 图像生成模型")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Logo 或图片
                Image(systemName: "sparkles.rectangle.stack")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .padding()
                
                // 功能描述
                VStack(alignment: .leading, spacing: 10) {
                    FeatureRow(iconName: "text.bubble.fill", text: "生成创意文本")
                    FeatureRow(iconName: "photo.fill", text: "创建和编辑图像")
                    FeatureRow(iconName: "doc.text.image.fill", text: "生成包含文本和图像的混合内容")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // 导航按钮
                VStack(spacing: 15) {
                    // 进入样例画廊
                    NavigationLink(destination: ExamplesView()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.headline)
                            Text("浏览样例功能")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // 进入聊天按钮
                    NavigationLink(destination: ChatView()) {
                        HStack {
                            Image(systemName: "message.fill")
                                .font(.headline)
                            Text("开始对话")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct FeatureRow: View {
    let iconName: String
    let text: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: iconName)
                .foregroundColor(.blue)
                .font(.title2)
            
            Text(text)
                .font(.body)
        }
        .padding(.vertical, 5)
    }
} 