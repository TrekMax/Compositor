# Compositor

[English](README.md) | 简体中文

Adobe Photoshop 的价格较高，而 GIMP 等工具的操作方式又不够熟悉，容易打断创作思路。这正是作者开发 Compositor 的初衷。

Compositor 的目标是成为一款功能完整、完全免费且开源的图像编辑器。它围绕 Photoshop 中常见的图像合成与后期处理工作流设计，提供精细调整最终图像所需的工具。

得益于开源，你可以下载 Xcode 工程，按自己的工作流添加、移除或修改功能。

## 安装

以下下载链接和 Homebrew 命令安装的是上游发行版。如需使用本分支的简体中文界面及其他改动，请[从本仓库源码构建](#构建)。

### 下载

访问 [robbietilton.com/compositor](https://robbietilton.com/compositor)，或从 [GitHub Releases](https://github.com/robbietilton/Compositor/releases/latest) 下载最新发行版。

### Homebrew

```sh
brew install --cask robbietilton-compositor
```

## 功能

### 图层

- 支持图层与图层组、不透明度，以及按 Photoshop 顺序排列的完整混合模式；图层组的不透明度作用于组内全部内容。
- 图层蒙版：可在画布任意位置绘制、填充、反相、模糊和羽化，包括图层自身像素范围之外；支持链接或取消链接，以便单独变换蒙版。
- 支持剪贴蒙版和图层组蒙版。
- 调整图层：色相/饱和度、色阶、曲线、曝光、渐变映射、颗粒、黑白、色彩平衡和反相。滤镜图层：高斯模糊、动感模糊、渐进模糊、锐化、降噪、杂色、暗角、泛光/辉光、RGB 分离、镜头效果和色调对比度。
- 图层效果：描边、投影、颜色叠加、内阴影、外发光和内发光；由 GPU 渲染，随时可以编辑。
- 向下合并、合并图层和合并图层组（⌘E）。
- 复制、行内重命名、拖放排序与嵌套；按住 Option 拖动可复制，图层面板提供右键菜单。
- 在未建立选区时，使用 ⌘C/⌘V 复制、粘贴整个图层或图层组；支持同一项目内、跨项目操作，也可在项目之间拖动图层。

### 变换

- 无损移动、缩放、旋转和翻转；无论缩得多小，图像都保留完整分辨率。
- 自由扭曲：按住 ⌘ 拖动控制点，按住 Shift 可锁定轴向。
- 同时变换多个图层或整个图层组。
- 吸附到画布和图层的边缘、中心及参考线。
- 距离显示（视图 → 显示 → 距离）：移动图层时显示其与画布边缘、附近图层之间的像素距离；按住 ⌘ 可查看与指针下图层的距离。
- 精确输入位置、尺寸、缩放比例和角度，并使用方向键逐步调整。
- 水平或垂直翻转图层及画布。
- 从移动工具栏或图层菜单，将图层相互对齐、分布，或以选区、画布为参照进行对齐与分布。

### 选区

- 矩形和椭圆选框、自由套索、多边形套索，以及魔法工具：魔棒按颜色选择，对象模式勾选点击的对象，可按 Tab 切换。
- 选择主体，以及扩展、收缩和羽化任意选区。
- 增加或减去选区、移动选区边界，以及移动或复制选区内的像素。
- 将图层像素或蒙版载入为选区。
- 内容识别填充，也可用于向图像边缘之外扩展内容。

### 绘画与修饰

- 画笔支持大小、硬度、不透明度和平滑度；可在绘画与擦除模式之间切换（B 和 E），按住 Shift 绘制直线。
- 使用数位板时，笔压可控制画笔大小与不透明度。
- 污点修复画笔，支持内容识别。
- 仿制图章，支持对齐或非对齐模式，可采样单个图层或所有图层。
- 模糊工具，可用于像素或蒙版。
- 渐变工具和形状工具：矩形、圆角矩形、椭圆和直线保持可编辑，无需栅格化。
- 文字工具（T）：在可拖动、可调整大小的段落框内直接编辑多行文字；在工具栏调整字体、字号、颜色、对齐方式和间距；支持文字变换及用作剪贴蒙版。
- 吸管与完整的颜色选择器。

### 调整与滤镜

- Camera Raw 滤镜：在画布旁的面板中调整光线、颜色、曲线、混色器、颜色分级、细节、光学和几何；各分区均可从标题处恢复默认值。
- 色阶（含自动调整）、曲线、色相/饱和度、曝光、渐变映射、颗粒、黑白、色彩平衡和反相。
- 高斯模糊与动感模糊，效果可扩展至图层边缘之外。
- 锐化、降噪、添加杂色、暗角、泛光/辉光、抖色、扫描线、RGB 分离、镜头效果、色调对比度、体积光、轮廓光、镜头校正和移除背景。镜头效果包含变形镜头耀斑、星芒、薄雾、棱镜，以及圆形、六边形、椭圆和猫眼形散景；体积光根据主体周围的距离增加雾气浓度，由手动放置的光源照亮，并让照片原有亮部向雾气中发光，也可添加光束；轮廓光可在主体后方放置最多三盏彩色光源，以环绕主体边缘的辉光融入照明。
- 实时预览；存在选区时，效果限定在选区内。
- 上次滤镜（⌃⌘F）：使用相同设置再次运行最近使用的滤镜。

### 画布与文件

- 通过标签页同时处理多个项目。
- 搜索命令（⌘F）：按名称查找任意菜单命令或工具，按 Return 执行，类似 Raycast 或 Obsidian 的命令搜索。
- 切换全屏（F）：隐藏全部面板，在黑色背景上全屏显示画布；再次按 F 或 Esc 恢复。
- 标尺（⌘R）、从标尺拖出的参考线、间距与细分可调的布局网格，以及对参考线、网格、图层和文档边界的吸附。
- 裁剪支持吸附、3:4 与 9:16 等比例，按住 Option 可对称裁剪；已有选区时，从选区范围开始裁剪。
- 调整画布大小、图像大小，以及修剪画布。
- 窗口高度不足以容纳单列工具时，工具栏自动改为两列。
- 缩放达到 300% 时，画布角落可显示导航器缩略图，用方框标示当前视野；点击或拖动即可移动视野（视图 → 导航器）。
- 缩小时采用清晰的高质量降采样，放大时显示像素网格。
- 导入 JPEG、PNG、HEIC、TIFF、WebP、SVG、PDF、动画 GIF、相机 RAW，以及 Photoshop PSD 和 PSB。PDF 每页作为独立图层，以 300 DPI 或适配画布的尺寸导入；动画 GIF 作为一个图层，在画布下方的帧条中播放、绘画、复制、删除帧及调整时长；相机 RAW 在导入前先进行显影。Photoshop 文件支持 8 位 RGB，不支持 CMYK；每个画板打开为独立标签页，图层组、蒙版、混合模式、填充矩形/椭圆及简单的横排文字保持可编辑，其他矢量内容和竖排文字转换为像素；应用转换前会显示转换报告。
- 大型文档：内存预算随 Mac 配置调整；Photoshop 文件过大时，会将其图层裁切到画布范围以便打开。
- 导出 PNG（⇧⌘E）、JPEG（⇧⌥⌘S），或使用“导出为”（⇧⌥⌘W）导出 PNG、JPEG、按打印尺寸生成的单页 PDF，以及在包含 GIF 图层时导出动画 GIF；可调整输出尺寸，并实时预览 JPEG 质量和文件大小。“导出为”中的通道打包可将图层打包进 PNG 的红、绿、蓝与 Alpha 通道，用于游戏纹理；RGB 分离中的“拆分为图层”则可反向拆出这四个通道。在图层面板中右键导出，可将各图层分别保存为按自身像素范围裁切的 PNG；也支持合并拷贝。
- 项目保存期间可以继续编辑。
- 提供 Photoshop 风格的键盘快捷键，可在“编辑 → 键盘快捷键”中重新分配。
- 拖动数值标签即可连续调整数值，操作方式类似 Photoshop。
- 支持自动更新；上游发行版经过签名与公证。

### 与 AI 智能体协作

- AI 智能体和脚本可以直接创建、修改项目：`.comp` 是包含 PNG 图层和清单文件的文件夹，写入文件时，已打开的项目会实时更新。详见[编写 Compositor 项目](docs/writing-comp-files.md)（英文）。

## 系统要求

- 搭载 Apple 芯片的 Mac，运行 macOS 26.0 或更高版本。
- 从源码构建需要 Xcode 26 或更高版本。

## 界面语言

本分支支持 **English（英文）**、**简体中文**和**跟随系统**。首次启动时可以选择语言，也可以在 **Compositor → 设置… → 通用**（⌘,）中更改。语言切换立即生效，并自动保存。

翻译维护方式见[界面语言说明](docs/localization.md)（英文）。上游 README 中“不接受本地化拉取请求”的政策适用于上游项目；本分支独立维护其翻译。

## 其他平台

Compositor 本身仅支持 macOS。以下非官方移植版由其他开发者维护，未经原作者审查，也不由原作者提供支持；相关问题请反馈到对应项目：

- [CompositorWindows](https://github.com/Cengokill/CompositorWindows)，作者 [@Cengokill](https://github.com/Cengokill)：Windows。
- [Composa](https://github.com/dvdstelt/Composa)，作者 [@dvdstelt](https://github.com/dvdstelt)：Windows 和 Linux。
- [CompositorLX](https://github.com/ClaudiuJitea/compositorLX)，作者 [@ClaudiuJitea](https://github.com/ClaudiuJitea)：Linux。

更多移植信息见 [#23（Windows）](https://github.com/robbietilton/Compositor/issues/23) 和 [#19（Linux）](https://github.com/robbietilton/Compositor/issues/19)。

## 构建

打开 `Compositor.xcodeproj`，运行 **Compositor** scheme。

编辑器、UI、渲染及文件 IO 的目录划分见[源码结构说明](docs/source-structure.md)（英文）。

## 发布

`scripts/release.sh` 会构建 Release 版本，使用 Developer ID 签名，提交 Apple 公证并附加公证票据，最后打包为 `dist/Compositor-<version>.dmg`。

需要准备以下内容，均应保存在仓库之外：

- 登录钥匙串中的 **Developer ID Application** 证书。
- 使用 `xcrun notarytool store-credentials "compositor-notary" …` 保存的公证凭据。
- [`create-dmg`](https://github.com/create-dmg/create-dmg) 工具，可通过 `brew install create-dmg` 安装。

如需自行分发，请在 `scripts/release.sh` 和 `scripts/ExportOptions.plist` 中配置自己的签名团队，并使用自己的证书与公证凭据。

## 许可证

采用 MIT 许可证，详见 [LICENSE](LICENSE)。

体积光使用的深度模型 DepthMini 蒸馏自 [Depth Anything V2 Small](https://github.com/DepthAnything/Depth-Anything-V2)（Apache-2.0），并以 torchvision 的 ImageNet 预训练 MobileNetV3 权重（BSD-3-Clause）为基础。模型不随应用打包，在首次打开体积光功能时下载。
