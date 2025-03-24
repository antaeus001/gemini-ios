import SwiftUI

// 个人资料视图 - 简化结构
struct ProfileView: View {
    var body: some View {
        VStack {
            Text("个人资料页面")
                .font(.title)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        ProfileView()
            .navigationBarTitle("我的", displayMode: .inline)
    }
} 