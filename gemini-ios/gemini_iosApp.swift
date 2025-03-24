//
//  gemini_iosApp.swift
//  gemini-ios
//
//  Created by antaeus on 2025/3/21.
//

import SwiftUI
import UIKit

@main
struct GeminiIOSApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var selectedTab = 0
    
    init() {
        // 配置TabBar外观
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // NavigationBar外观
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                // 会话标签
                NavigationView {
                    ChatView(viewModel: chatViewModel)
                        .navigationBarTitle("Gemini AI", displayMode: .inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("会话")
                }
                .tag(0)
                
                // 工具标签
                NavigationView {
                    ToolsView()
                        .navigationBarTitle("样例库", displayMode: .inline)
                        .environmentObject(chatViewModel)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "rectangle.grid.2x2.fill")
                    Text("样例")
                }
                .tag(1)
                
                // 广场标签
                NavigationView {
                    SquareView()
                        .navigationBarTitle("内容广场", displayMode: .inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "newspaper.fill")
                    Text("广场")
                }
                .tag(2)
                
                // 我的标签
                NavigationView {
                    ProfileView()
                        .navigationBarTitle("我的", displayMode: .inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("我的")
                }
                .tag(3)
            }
            .accentColor(.blue)
            .onAppear {
                setupNotifications()
            }
        }
    }
    
    // 设置通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SwitchToChat"), object: nil, queue: .main) { _ in
            selectedTab = 0 // 切换到聊天标签
        }
    }
}
