# 发布清单

## 来源与许可

- [ ] 保留 README 和第三方声明中的原仓库链接及“基于原项目开发”的署名。
- [ ] 确定适用于整个派生项目的 LICENSE，核对上游、图标、字体和新引入资源的使用范围。
- [ ] 核对 Dart 依赖和实际打入 APK 的原生依赖；保留适用声明和需要提供的源码材料。
- [ ] 未完成这些步骤前，不添加宣称 MIT / GPL 等许可的徽章或发行声明。

## 代码与隐私

- [ ] 从 `pubspec.lock` 恢复依赖，格式、静态分析、测试和 Android 构建通过。
- [ ] 仓库只含源码和必要资源，运行 `node tool/check_repository.mjs`。
- [ ] 审查 `git diff` 和完整 Git 历史；不能只依赖 .gitignore 或轻量检查。
- [ ] 不含用户数据、账号、私钥、签名 URL、日志和私人截图。
- [ ] 默认名称和包名保持通用、不预设个人站点；个人构建元数据仅放在忽略的 `config/*.local.json` 中。
- [ ] 执行 `node --test tool/build_android_test.mjs`，核对实际 APK 名称、包名、版本与构建配置一致。
- [ ] CI 在目标 GitHub 仓库实际运行通过；本地通过不代表托管 CI 已验证。
- [ ] 按变更补充 CHANGELOG、版本号及升级说明。

## 正式签名

将 `android/key.properties.example` 复制为 `android/key.properties`，填写真实配置；该文件和 keystore 均被忽略。也可由受保护的发布环境提供：

- `CLOUDREVE_KEYSTORE_PATH`
- `CLOUDREVE_KEYSTORE_PASSWORD`
- `CLOUDREVE_KEY_ALIAS`
- `CLOUDREVE_KEY_PASSWORD`

keystore 路径推荐使用绝对路径；相对路径按 `android/` 目录解析。不要把密码填入公开命令、脚本或 CI YAML。密钥由维护者自行生成、保管并备份；仓库不提供正式私钥。

```sh
flutter build apk --release --split-per-abi --dart-define-from-file=config/app.local.json
```

`--local-test` 或 `-PallowDebugReleaseSigning=true` 只用于本地 release 模式验证。默认禁止将未配置正式签名的 release 当作发行版。已安装的测试签名包通常不能被另一个正式签名包覆盖，迁移前需说明账号和本地数据处理方式。

## 设备验收与发行材料

- [ ] 真机验收登录/退出、注册验证、上传下载、重命名、分享转存与预览。
- [ ] 浅色/深色、启动页、返回退出、页面切换和全屏视频无回归。
- [ ] 检查 release 包安装、冷启动、重复开关播放器和后台恢复。
- [ ] 使用 apksigner 验证证书与包签名，核对版本、权限和 ABI。
- [ ] 对每个发行 APK 计算 SHA-256，并附更新说明和许可材料。
- [ ] 发包经人工确认；本仓库 CI 不自动创建 Release、不上传任何 APK。
