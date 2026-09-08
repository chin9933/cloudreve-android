# 参与开发

本项目基于 [YangChengxxyy/cloudreve_flutter](https://github.com/YangChengxxyy/cloudreve_flutter) 继续开发，修改时请保留来源说明。

## 工作流程

1. 先说明问题和复现步骤，大改动先讨论范围。
2. 从维护分支创建自己的功能分支，一次 PR 聚焦一个问题。
3. 遵循 `.editorconfig`、`analysis_options.yaml` 和 [架构约定](docs/ARCHITECTURE.md)。
4. 增加回归测试，执行 README 中的全部检查。
5. 描述未覆盖的设备、平台和限制，不把编译成功当作真机验证。
6. 提交前检查 `git diff --check`、`git diff --stat` 和新增文件列表。

提交说明建议使用 `fix:`、`feat:`、`refactor:`、`test:`、`docs:`、`build:` 或 `chore:` 前缀。不要把行为修改与大规模无关重排混在一起。

## 代码规则

- Dart 文件使用 `lower_case_with_underscores.dart`；类使用 UpperCamelCase；成员使用 lowerCamelCase。
- 由 `dart format` 决定排版，不手工维护特殊缩进。导入使用 package URI 并保持排序。
- 不通过全局关闭 lint 规避问题。必须抑制时，只在最小范围说明原因。
- 异步后调用导航、提示或 setState 前检查对应页面/上下文是否仍有效。
- 不把另一个路由的 BuildContext 长期保存在组件里；优先通过参数、回调和对话框返回值传递数据。
- 订阅、控制器和临时状态必须有明确生命周期。播放器的已记录原生兼容性例外不能直接套用普通 dispose 规则。
- 业务请求经仓储层处理；新缓存必须考虑账号切换、容量、失效和并发请求复用。
- 测试使用模拟请求和虚构数据；默认检查不允许依赖个人账号或生产站点。
- 新资源和依赖同时说明来源、许可及体积影响。

## 生成代码

`api/` 中的 SDK 不是手写业务层。不要为了满足 UI lint 批量改动生成文件。修改服务端协议映射时优先在仓储层补兼容处理和协议测试；确需重新生成时，提交输入、工具版本和生成差异说明。

## 隐私与许可

不要提交账号密码、会话、服务器私钥、带签名的媒体链接、私人截图、APK 或本机 SDK 路径。历史提交也需要检查，`.gitignore` 不会清除已提交内容。

当前统一开源许可证尚待确定。引入代码或资源前先确认来源和许可，勿假定公开仓库的内容均可任意再分发。
