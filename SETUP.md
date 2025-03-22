# Gemini iOS 项目设置指南

## 修复编译错误

以下是修复项目编译错误的步骤：

### 1. 添加GoogleGenerativeAI依赖

请在Xcode中执行以下操作：

1. 打开Xcode项目（gemini-ios.xcodeproj）
2. 选择File > Add Packages...
3. 在搜索栏中输入：`https://github.com/google/generative-ai-swift`
4. 点击"Add Package"
5. 选择最新版本（0.4.2或更高）
6. 确保将包添加到"gemini-ios"目标中

### 2. 更新项目设置

1. 选择gemini-ios项目
2. 选择"gemini-ios"目标
3. 设置iOS部署目标为iOS 15.0或更高

### 3. 设置API密钥

要设置Gemini API密钥：

1. 选择Product > Scheme > Edit Scheme...
2. 选择"Run"
3. 选择"Arguments"标签
4. 在"Environment Variables"部分
5. 点击"+"添加新环境变量
6. 名称：`GEMINI_API_KEY`
7. 值：您的Gemini API密钥

### 4. 命令行构建（可选）

如果您想使用命令行构建项目，可以使用以下命令：

```bash
# 清理构建目录
xcodebuild clean -project gemini-ios.xcodeproj -scheme gemini-ios

# 构建项目
xcodebuild build -project gemini-ios.xcodeproj -scheme gemini-ios -destination 'platform=iOS Simulator,name=iPhone 14'
```

### 5. 清理和构建项目

1. 选择Product > Clean Build Folder
2. 选择Product > Build

## 代码修复说明

我们已经对项目进行了以下修改：

1. 在`ChatMessage.swift`中添加了`import UIKit`以支持UIImage
2. 在`ChatView.swift`中更新了onChange API，使用messages.count而不是直接观察messages数组
3. 更新了导航栏API，使用现代toolbar布局
4. 创建了Package.swift用于管理GoogleGenerativeAI依赖
5. 在GenerationConfig中添加了`responseModalities: ["Text", "Image"]`参数，以便支持文本和图片输出

## 重要配置提示

使用`gemini-2.0-flash-exp-image-generation`模型时，必须在生成配置中添加以下参数：

```swift
let config = GenerationConfig(
    // 其他参数...
    responseModalities: ["Text", "Image"]
)
```

这是必需的，否则模型将无法正确生成图像内容。

## 常见问题解决

- **聊天会话尚未初始化**：确保已正确设置GEMINI_API_KEY环境变量
- **无法找到GoogleGenerativeAI模块**：确保Swift Package已正确添加到项目中
- **UIImage相关错误**：确保在使用UIImage的文件中导入UIKit
- **SwiftUI导航错误**：如果使用iOS 15或以上，可以考虑使用新的导航API
- **环境变量错误**：确保正确设置了GEMINI_API_KEY环境变量
- **onChange方法错误**：SwiftUI的onChange API在不同iOS版本中有差异，确保使用正确的语法
- **图像生成问题**：确保在GenerationConfig中设置了`responseModalities: ["Text", "Image"]`

## 其他提示

- 确保使用的是最新版本的Xcode（至少Xcode 14.0或更高）
- 如果遇到其他依赖问题，可能需要关闭并重新打开Xcode
- 经常检查Google Gemini API的文档以获取最新的API变更信息
- 对于复杂的编译错误，可以尝试删除derived data：
  `rm -rf ~/Library/Developer/Xcode/DerivedData` 