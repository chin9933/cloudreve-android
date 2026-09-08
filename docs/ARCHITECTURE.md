# 架构与维护约定

## 数据与展示边界

`Widget → AppState / Controller → CloudreveRepository → HttpUtil / generated API → HTTPS Cloudreve`

- `lib/main.dart`：启动前恢复外观偏好，创建 Provider 和 GoRouter。
- `lib/app/main_home.dart`：主导航壳、共享操作和顶栏音频入口。
- `lib/view/files_page.dart`：文件列表与预览入口。
- `lib/utils/cloudreve_repository.dart`：协议兼容、业务操作、会话请求与缓存失效。
- `lib/utils/http_util.dart`：HTTP 客户端、服务端切换和鉴权状态。
- `lib/utils/secure_session_store.dart`：安全持久化会话。
- `lib/utils/request_cache.dart`：有界缓存、并发请求合并和主动失效。
- `lib/theme/app_theme.dart`：共享色彩、主题、控件形状和路由外观。
- `lib/config/app_config.dart`：可覆盖的公开站点默认值，不存放凭据。

新增业务不要继续堆进主导航或文件页面。优先提取拥有明确输入/输出的组件和控制器，但应在有回归测试的前提下逐步迁移，避免一次改变导航、请求和媒体生命周期。

## 生命周期

异步返回后，检查实际使用的 BuildContext 是否仍 mounted。对话框返回数据，不保存其他路由上下文；结果显示与复制分为 `share_dialog.dart`、`share_result_dialog.dart`，由页面负责导航。

缓存键包含会话代次及资源身份；登录、退出、切换账号和文件变更必须走现有失效入口。普通页面重建不能造成无意义的重复网络请求。

## 播放器

音频状态由 `audio_player_controller.dart` 管理。视频页面使用 media_kit 原生播放器及 `video_player_controls.dart` 自定义控制层。音量/亮度通过 Android 平台桥接，亮度设置仅作用于当前窗口并在结束时恢复。

当前播放器保留针对原生 release 生命周期崩溃的兼容处理，依赖版本已锁定。升级时必须验证：首次打开、连续切换视频、重复进入/退出、后台恢复、全屏旋转、倍速、锁定与手势，以及 debug 和 release 两种构建。不得仅因常见的“控制器应 dispose”规则移除明确标注的例外。

## API 生成边界

`api/` 为生成的独立 Dart package，使用其自身分析配置。常规质量检查聚焦应用和回归测试，不对生成输出强加手写页面风格。

`tool/build_openapi.py` 从 `api_docs/*.md` 中合并 YAML，输出 `openapi/cloudreve.json`；它需要 Python 3 和 PyYAML，仅在更新协议定义时手动运行。脚本会规范化部分 nullable / required 字段，因此重新生成不是完全无语义影响的操作。

SDK 当前记录的生成器信息位于 `api/.openapi-generator/`。仓库没有可靠记录完整的历史生成命令；不要声称可以从零无差别重建 SDK。实际重新生成时应固定 OpenAPI Generator 版本与参数，单独评审 API 差异并执行协议回归测试。

## 测试范围

现有测试包含缓存、协议、主题、导航、搜索/转存、启动主题、账户界面和媒体控件。部分历史 UI 回归使用源码结构断言，并不等价于真实设备上的视觉测试；新增测试优先断言行为。模拟请求不能证明生产站点、证书和存储对象正常。
