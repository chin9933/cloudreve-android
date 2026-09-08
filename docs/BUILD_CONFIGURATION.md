# 构建时设置应用信息

仓库使用通用名称和示例包名，不绑定任何个人站点。构建参数只影响本次 APK，不改写 Dart、AndroidManifest.xml 或 pubspec.yaml。

## 参数

| 命令参数 | JSON / Dart define | 默认值与作用 |
| --- | --- | --- |
| `--app-name` | `APP_NAME` | `Cloudreve`；桌面、系统应用名称、启动页、登录页、侧栏、播放器及应用信息页 |
| `--application-id` | `APP_APPLICATION_ID` | `com.example.cloudreve`；APK 身份，正式发行应使用维护者自己的唯一包名 |
| `--app-description` | `APP_DESCRIPTION` | `安全存储 · 随时访问 · 轻松分享`；启动页、登录页和应用简介 |
| `--site-url` | `CLOUDREVE_SITE_URL` | 空值；用户先添加服务器，也可指定 HTTPS 默认站点 |
| `--build-name` | `APP_VERSION_NAME` | pubspec.yaml 的版本名，例如 `1.2.0` |
| `--build-number` | `APP_VERSION_CODE` | pubspec.yaml 的构建号；1 到 2100000000 的整数，发布升级时递增 |

名称支持中文和空格，最多 64 字符；简介最多 240 字符。包名使用小写点分段形式。站点可带部署子路径，但不能含明文 HTTP、用户名、密码、查询参数或片段。未知参数和未知 JSON 字段直接报错，避免拼写错误被静默忽略。

## Windows 命令

```bat
tool\build_android_release.cmd --app-name "团队云盘" --application-id com.example.teamdrive --site-url https://cloud.example.com --app-description "团队文件管理" --build-name 1.2.0 --build-number 12 --split-per-abi
```

本地测试且未配置正式签名时，显式附加 `--local-test`。不能将测试签名包当作正式发布包。依赖缓存不完整时附加 `--online`；默认使用 Gradle 离线缓存。

```bat
tool\build_android_release.cmd --help
tool\build_android_release.cmd --app-name "团队云盘" --dry-run
```

含空格的命令值要加引号。含 `%`、`!`、`&`、引号等特殊字符的文字建议放入 JSON，避免命令行终端自身的转义规则。传给 Gradle 的文字以 UTF-8 编码，中文名称不会要求修改系统代码页。

## 本地配置文件

复制 `config/app.example.json` 为 `config/app.local.json`，再自行填写公开元数据。没有配置版本字段时仍读取 pubspec.yaml。

```json
{
  "APP_NAME": "团队云盘",
  "APP_APPLICATION_ID": "com.example.teamdrive",
  "APP_DESCRIPTION": "团队文件管理",
  "CLOUDREVE_SITE_URL": "https://cloud.example.com",
  "APP_VERSION_NAME": "1.2.0",
  "APP_VERSION_CODE": "12"
}
```

```bat
tool\build_android_release.cmd --config config/app.local.json --split-per-abi
```

优先级：命令参数 > JSON > 通用默认值 / pubspec.yaml，与参数出现顺序无关。`--site-url=` 可显式取消默认站点。个人配置保存在被 Git 忽略的 `config/*.local.json` 中；不要把它改成会被提交的文件名。

在已配置 Flutter、JDK 和 Android SDK 的其他系统，也可运行 `node tool/build_android.mjs` 并传相同参数，或使用标准 Flutter 命令：

```sh
flutter build apk --release --split-per-abi --dart-define-from-file=config/app.local.json
```

直接使用 Flutter 时同样读取以上 Dart define；Android 与 Flutter UI 共用这些值。若 JSON 提供 `APP_VERSION_NAME` / `APP_VERSION_CODE`，它们优先于 Flutter 的 `--build-name` / `--build-number`；否则使用 Flutter 的常规版本处理。

## 安全与升级

- 所有这些配置均可从 APK 中读取。Base64 传递不提供保密性，禁止填写账号、令牌、密码或签名密钥。
- 正式签名继续使用 `android/key.properties` 或 `CLOUDREVE_KEYSTORE_*` 等受保护环境变量，见 [发布清单](RELEASE_CHECKLIST.md)。如需指定已有本地测试签名，显式设置 `CLOUDREVE_DEBUG_KEYSTORE`；仓库不再探测个人命名的密钥文件。
- APK 包名与 Java 源码命名空间分开配置，原生入口保持稳定。修改包名会成为独立应用；要覆盖升级旧应用，必须沿用原包名与签名证书。原账号和本地缓存不会跨包名自动迁移。参见 [Android 应用 ID 与命名空间说明](https://developer.android.com/build/configure-app-module)。
- 已有安装保留自己选择的服务器与安全会话，不强制切换到新构建默认站点。旧版本若从未保存隐式默认站点、也没有可恢复会话，则需要重新添加地址，不猜测维护者的旧站点。
- 图标仍使用仓库中的通用资源；这些参数不修改图标、许可证或原作者署名。保留“基于原项目开发”及上游仓库引用。

编译期参数采用 Dart 官方支持的 [环境声明机制](https://dart.dev/libraries/core/environment-declarations)。
