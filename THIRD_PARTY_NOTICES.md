# 来源与第三方组件

## 项目来源

本项目基于 **[YangChengxxyy/cloudreve_flutter](https://github.com/YangChengxxyy/cloudreve_flutter)** 开发。原作者：YangChengxxyy。保留其项目来源，不将原项目内容标为本项目独立原创。

Cloudreve 名称、原有图标及相关资源不因本项目的修改而改变权利归属。重新品牌化或发行前应核对资源的使用范围。此文件不是给上游代码追加许可证。

## Dart / Flutter 依赖

准确版本以根目录 `pubspec.lock` 为准，用途见 `pubspec.yaml`。主要组件包括 Flutter、Dio、Provider、go_router、just_audio、media_kit、flutter_secure_storage、file_picker、archive 和 photo_view。

应用“设置 → 应用信息”中的开源许可入口使用 Flutter 的 LicenseRegistry，展示构建时收集到的 Dart 包许可证。发布时不能删除这些声明。需逐一审查新增依赖的 LICENSE；应用内注册表不能代替原生依赖和资源的完整合规检查。

## 原生视频依赖

当前 Android 视频链路为：

`media_kit → media_kit_video / media_kit_libs_video → media_kit_libs_android_video → libmpv / FFmpeg 等原生库`

锁定版本中的 Android 插件引用 [libmpv-android-video-build](https://github.com/media-kit/libmpv-android-video-build) 的 v1.1.7 `default` 架构产物。该构建仓库与底层组件的许可必须分别核对，不能只看 Flutter 封装包的 MIT 声明就判定整个 APK 的许可。

发布二进制前需留存实际使用的原生库版本、构建配置、版权声明、对应源码位置，以及适用许可要求的源码/重新链接材料。切换库版本或构建 flavor 时重新检查。当前文件不宣称已完成 APK 的全部许可审计。

## API 客户端

`api/`、`api_docs/` 和 `openapi/` 沿用上游项目的 API 定义与生成结构。保留生成标记，生成规则见 [架构说明](docs/ARCHITECTURE.md)。
