# Gemini iOS 客户端

基于Google Gemini 2.0 Flash(Image Generation) Experimental模型的iOS应用。

## 功能特点

- 生成创意文本内容
- 创建和编辑图像
- 生成包含文本和图像的混合内容（如博客文章）
- 对话式图像编辑体验

## 配置要求

- iOS 15.0+
- Xcode 14.0+
- Swift 5.5+
- Google Generative AI SDK

## 设置步骤

1. 克隆此仓库
2. 在Xcode中打开项目
3. 获取Google Gemini API密钥
4. 将API密钥作为环境变量添加到Xcode scheme中:
   - 编辑Scheme > Run > Arguments > Environment Variables
   - 添加键值对: GEMINI_API_KEY = 你的API密钥

## 使用指南

应用提供三种预设示例：

1. **图像编辑** - 为图像添加或修改特定内容
2. **故事生成** - 生成包含文本和配图的完整故事
3. **设计生成** - 创建特定设计内容，如生日贺卡

你也可以输入自定义提示来满足特定需求。

## 模型信息

此应用使用Google Gemini 2.0 Flash Experimental模型，该模型支持：

- 输出文本和内嵌图片
- 对话方式编辑图片
- 生成包含交织文本的输出内容

## 常见问题解决

1. **聊天会话尚未初始化**
   - 确保已正确设置GEMINI_API_KEY环境变量
   - 检查网络连接是否正常
   - 尝试点击错误消息，使用"重试"选项重新初始化聊天

2. **没有API密钥**
   - 访问 https://makersuite.google.com/app/apikey 获取Gemini API密钥
   - 确保密钥具有访问gemini-2.0-flash-exp-image-generation模型的权限

3. **网络连接问题**
   - 确保设备已连接到互联网
   - 检查是否存在防火墙或网络限制

4. **图像生成问题**
   - 确保提示清晰明确
   - 尝试使用应用内的示例提示进行测试

## 注意事项

- API密钥不应直接硬编码在源代码中
- 此应用处于实验性阶段，模型功能可能会随时变化
- 生成的内容质量取决于提示的质量和模型的能力

## Gemini iOS 应用

这是一个使用Google Gemini 2.0 Flash模型的iOS应用，可以生成文本内容和图像。

### 功能

- 生成文本：回答问题、创建内容
- 生成图像：根据文本提示创建图像
- 混合内容：同时生成文本和图像内容

### 设置

1. 首先，您需要获取一个Google Gemini API密钥。访问 [Google AI Studio](https://makersuite.google.com/) 创建一个账户并获取API密钥。

2. 在Xcode中设置环境变量：
   - 打开项目
   - 选择项目的Scheme (通常在顶部工具栏中)
   - 点击"Edit Scheme..."
   - 在左侧选择"Run"
   - 选择"Arguments"选项卡
   - 在"Environment Variables"部分点击"+"按钮
   - 添加一个新的环境变量：
     - 名称：GEMINI_API_KEY
     - 值：[您的Gemini API密钥]
   - 点击"Close"保存设置

3. 如果遇到编译问题，尝试清理Xcode的派生数据：
   ```
   rm -rf ~/Library/Developer/Xcode/DerivedData/gemini-ios-*
   ```
   然后重新编译项目。

### 使用说明

1. 打开应用
2. 在主界面点击"开始对话"
3. 在聊天界面输入提示，例如：
   - "为我解释量子物理学"（生成文本）
   - "画一只可爱的小狗在草地上玩耍"（生成图像）
   - "告诉我碳水化合物的作用，并附上一张示意图"（生成混合内容）

### 示例提示

应用内置了几个示例提示，展示了Gemini模型的能力：
- 图像生成
- 故事生成
- 设计生成

### 技术说明

本应用直接使用REST API调用Google Gemini模型，不依赖于任何第三方SDK。

特点：
- 直接API调用，完全控制请求参数
- 支持responseModalities参数，允许同时生成文本和图像
- 详细的调试日志，便于问题排查 