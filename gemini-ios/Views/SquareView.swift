import SwiftUI

// 广场视图 - 简化结构
struct SquareView: View {
    var body: some View {
        VStack {
            Text("广场页面")
                .font(.title)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        SquareView()
            .navigationBarTitle("内容广场", displayMode: .inline)
    }
} 