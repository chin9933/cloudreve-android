# Cloudreve for Android（非官方）

基于 [YangChengxxyy/cloudreve_flutter](https://github.com/YangChengxxyy/cloudreve_flutter) 继续开发的 Cloudreve Android 客户端。感谢原作者提供项目基础。

应用使用 Flutter 原生界面，文件与账户操作通过 Cloudreve API 完成，不是将网页套进 WebView。音频使用 just_audio，视频使用 media_kit；需要浏览器处理的站点功能仍可能打开浏览器。

## 当前能力与边界

- 文件浏览、上传、下载、重命名、目录管理和搜索。
- 分享链接管理、复制链接导入、选择转存目录。
- 图片、音频、视频及部分文本/压缩包预览；不支持的格式交由外部应用处理。
- 视频倍速、全屏锁定、纵向亮度/音量手势；音频顶栏控制。
- 登录、注册验证、个人资料、WebDAV 账户管理。
- 浅色/深色主题、启动主题同步、页面切换动画及账号隔离缓存。

当前开发和回归验证以 **Android + Cloudreve v4 API** 为主。服务端版本、存储策略、注册验证方式和权限会影响功能可用性。WebDAV 页面管理访问账户，并不实现系统级 WebDAV 挂载。仓库保留的 iOS、桌面和 Web 平台目录不代表这些平台已完成适配。离线任务相关遗留页面尚未完整实现。

## 开发环境

- Flutter **3.47.2** / Dart **3.13.2**，版本固定在 `.fvmrc`。
- JDK **17**、Android SDK、Android SDK Command-line Tools。
- Node.js **20+**：构建包装命令、仓库检查和可选诊断脚本需要，不属于应用运行依赖。
- Python / OpenAPI Generator：仅重新生成 API 时需要，普通开发不需要。

安装 Flutter 后，在本项目目录运行：

```sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter run
```

请提交根目录 `pubspec.lock`。不要为了消除构建错误随意升级原生播放器依赖。

## 服务器配置

源码不包含维护者的个人部署信息。默认名称为 `Cloudreve`，示例包名为 `com.example.cloudreve`，不预设服务器；首次使用需在登录页添加 HTTPS 服务器。也可以在构建时指定默认站点：

```sh
flutter run --dart-define=CLOUDREVE_SITE_URL=https://cloud.example.com
```

也可复制 `config/app.example.json` 为 `config/app.local.json` 后使用：

```sh
flutter run --dart-define-from-file=config/app.local.json
```

配置文件还可设置名称、包名和简介，详见 [构建配置](docs/BUILD_CONFIGURATION.md)。这里仅放公开应用元数据，不要放密码、令牌或密钥。编译参数会进入 APK，并不保密。`config/*.local.json` 默认不提交，示例文件仅含通用值。已有服务器选择和会话不会被构建参数强制重置。

## 提交前检查

```sh
node tool/check_repository.mjs
node --test tool/build_android_test.mjs
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos
flutter test --no-pub
```

修改格式时运行 `dart format lib test`。Windows 可运行 `tool\pub_get.cmd` 和 `tool\check_project.cmd`，脚本支持 `FLUTTER_ROOT`、PATH 上的 Flutter，以及原有工作区的隔离工具链。

GitHub CI 执行仓库检查、格式检查、静态分析、测试与 Android debug 构建。CI 不会访问生产账户、发布 APK 或使用正式签名密钥。

## Android 构建

Windows 可直接通过命令定制应用信息，无需修改源码（以下域名和包名都是示例）：

```bat
tool\build_android_release.cmd --app-name "团队云盘" --application-id com.example.teamdrive --site-url https://cloud.example.com --app-description "团队文件管理" --build-name 1.2.0 --build-number 12 --split-per-abi
```

或复制 `config/app.example.json` 为 `config/app.local.json`，填写公开部署信息后运行：

```bat
tool\build_android_release.cmd --config config/app.local.json --split-per-abi
```

`--help` 查看全部参数，`--dry-run` 仅检查配置。名字含空格时加引号；含复杂特殊字符时使用 JSON。[完整参数与升级注意事项](docs/BUILD_CONFIGURATION.md)。

正式发布先按 [发布清单](docs/RELEASE_CHECKLIST.md) 配置签名：

```sh
flutter build apk --release --split-per-abi --dart-define-from-file=config/app.local.json
```

产物位于 `build/app/outputs/flutter-apk/`。分 ABI 发布可避免让手机安装不需要的原生架构。

没有正式签名时，release 构建会失败。Windows 上仅做本地验证，可显式允许测试签名：

```bat
tool\build_android_release.cmd --split-per-abi --local-test
```

这个脚本默认使用离线依赖缓存；首次构建可添加 `--online`。**测试签名 APK 不是正式发行包**，不得与正式签名混用。更换包名会成为独立应用，覆盖升级必须保留原包名和签名；通用源码不替维护者预设生产身份。

## 项目结构

| 目录 | 职责 |
| --- | --- |
| `lib/app/` | 启动、登录注册和主导航 |
| `lib/view/` | 文件、首页、分享、个人资料和设置页面 |
| `lib/component/` | 对话框、文件展示和播放器控件 |
| `lib/state/` | 会话、音频、音效与动画状态 |
| `lib/utils/` | API 仓储、缓存、安全存储和平台桥接 |
| `lib/config/`、`lib/theme/` | 构建配置与主题设计 |
| `api/` | 上游生成的 Dart API 客户端 |
| `api_docs/`、`openapi/` | API 说明与生成输入 |
| `test/` | 单元、组件和协议回归测试 |
| `tool/` | 可复用构建及检查工具 |
| `outputs/` | 仅本地的日志、截图、APK 和诊断备份；禁止提交 |

更多说明：[规范化检查记录](docs/CODE_QUALITY.md)、[架构与约定](docs/ARCHITECTURE.md)、[参与开发](CONTRIBUTING.md)、[安全报告](SECURITY.md)、[第三方声明](THIRD_PARTY_NOTICES.md)。

## 许可状态

保留原项目来源及署名。当前尚未为整个派生项目确定统一的开源许可证，因此不声明 MIT、Apache 或 GPL 授权；公开发行前仍需确认适用许可及第三方组件要求。第三方代码、字体、图标和原生库分别遵循其自身许可。
