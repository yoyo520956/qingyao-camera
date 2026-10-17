# 倾瑶相机 QingyaoCamera (iOS)

基于 Swift / SwiftUI 的专业级 iOS 相机应用（v4.9），深度适配 iPhone（iOS 16+，iOS 26/27 渐进增强）。

## 功能特性

- 液态玻璃 UI（iOS 26+ glassEffect 渐进增强）+ 深空渐变主题
- 拍照模式：标准 / HDR / HDR+（八帧融合）/ 超清 Pro（四帧金字塔对齐 + 2x 超清输出）/ DRO / RAW
- AI 超分辨率：waifu2x CoreML 模型（降噪 1x + 超分 2x，Neural Engine 硬件加速，任意分辨率）
- 人像模式：Vision 系统级人物分割 + 背景高斯虚化，三档景深（浅/中/深）
- 296 个电影胶片 LUT（9 分类，.cube 实时预览 / 拍照烧录 / 视频烧录三链路，强度 0-100%）
- 视频：4K 录制、延时摄影、慢动作、GIF 动图导出（mp4 + GIF 双份）、实时增强开关
- 全景拼接（条带 8% 渐变融合）、Live Photo、长按连拍、RAW + JPG 双存
- 专业控制：手动对焦环、EV 曝光补偿滑杆、峰值对焦、人脸检测框、直方图/斑马线、AE-L
- 电影模式（2.35:1 遮幅 + 暗角 + 胶片颗粒）、语音控制、音量键拍照、QuickTake
- 触觉反馈系统（11 处挂点）、Lucide 官方图标、快门三态动效

## 构建

依赖 [xcodegen](https://github.com/evanepp/XcodeGen)：

```bash
cd camera-ios
brew install xcodegen
xcodegen generate
xcodebuild -project QingyaoCamera.xcodeproj -scheme QingyaoCamera \
  -sdk iphoneos -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

CI：`.github/workflows/build-camera-ios.yml`（GitHub Actions，macos-latest，未签名 IPA）。

## 目录结构

```
camera-ios/
├── project.yml              # xcodegen 工程定义
├── Resources/LUTs/          # 296 个 .cube 胶片 LUT（9 分类）
├── Resources/Models/        # waifu2x CoreML 模型（9 个）
└── Sources/                 # Swift 源码（32 个文件）
```

## License

MIT
