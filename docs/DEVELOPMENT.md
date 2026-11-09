# 开发指南

[返回 README](../README.md)

项目使用 SwiftUI、AppKit 和系统 Text Input Source API，采用 Swift 6 语言模式。应用、Swift Package 和集成验证工具的最低部署目标统一为 macOS 14.0。应用支持 arm64 和 x86_64，并按架构分别发布。

## 构建

需要 Apple Silicon Mac 和完整的 Xcode。目前验证的构建环境为 macOS 27.2、Xcode 27.2（Swift 6.4.2）。在仓库根目录执行：

```bash
bash Scripts/build.sh
open build/IMELock.app
```

脚本优先使用 `/Applications/Xcode.app`，也可通过 `DEVELOPER_DIR` 指定其他 Xcode 安装路径：

```bash
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer bash Scripts/build.sh
```

脚本按当前处理器架构构建 Release 配置，输出 `build/IMELock.app` 并验证代码签名与单一架构。应用采用本机 ad-hoc 签名，开启 App Sandbox，无需配置开发者团队。也可以打开 `IMELock.xcodeproj`，选择共享的 IMELock scheme 运行。

指定架构构建时，产物与缓存分别存放：

```bash
bash Scripts/build.sh arm64   # build/arm64/IMELock.app
bash Scripts/build.sh x86_64  # build/x86_64/IMELock.app
```

生成两个独立 DMG 安装包及 SHA-256 校验文件：

```bash
bash Scripts/package-release.sh
```

产物位于 `build/releases/v版本号/`，包含 `IMELock-版本号-arm64.dmg`、`IMELock-版本号-x86_64.dmg` 和 `SHA256SUMS.txt`。每个 DMG 内含对应架构的应用与“应用程序”快捷入口。发布包未经过 Apple 公证，发布说明需注明签名情况及实际验证范围。

应用标识为 `app.imelock.IMELock`，使用独立沙盒和偏好设置，不迁移旧版本数据。首次启动默认未锁定，累计次数为 0，登录启动关闭。调试时避免同时运行 Xcode 构建产物和其他安装位置的应用副本。

## 测试

状态机与持久化测试不切换系统输入源：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

仅使用模拟输入源验证控制器的调度、可调等待时间和取消行为：

```bash
bash Scripts/verify-integration.sh --simulated-only
```

验证指定架构的控制器（在 Apple Silicon 上运行 x86_64 产物需要 Rosetta）：

```bash
IMELOCK_TEST_ARCH=arm64 bash Scripts/verify-integration.sh --simulated-only
IMELOCK_TEST_ARCH=x86_64 bash Scripts/verify-integration.sh --simulated-only
```

沙盒集成验证使用与正式应用相同的输入源服务、控制器和状态机，以独立偏好域保存测试数据：

```bash
bash Scripts/verify-integration.sh
```

集成验证会短暂切换已启用的输入源，检查应用切换触发恢复、安全输入暂停和继续，以及成功恢复计数；退出时还原原来的输入源。基础模式在隔离通知中心中模拟应用激活，需要当前会话未开启安全输入，且至少有两个可用输入源。

要覆盖系统拼音以及三个真实前台应用：

```bash
bash Scripts/verify-integration.sh --include-system-pinyin --activate-apps
```

`--include-system-pinyin` 临时启用系统简体、繁体拼音所需的输入源，结束后还原启用状态。`--activate-apps` 会依次打开或激活 Safari、文本编辑和终端，结束后返回原来的前台应用。测试不会输入文字。

历史结果和仍需手动验证的系统交互见[验证记录](VALIDATION.md)。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| [LockEngine.swift](../IMELock/Core/LockEngine.swift) | 锁定状态机、成功恢复计数、有限重试与频繁切换保护 |
| [ConfigurationStore.swift](../IMELock/Core/ConfigurationStore.swift) | 目标、锁定意愿、故障暂停、等待时间和累计次数的持久化 |
| [InputSourceService.swift](../IMELock/InputSourceService.swift) | 主线程上的 TIS 查询、选择和安全输入检测 |
| [LockController.swift](../IMELock/LockController.swift) | 应用激活触发、单次结果确认、休眠及会话事件 |
| [MenuContentView.swift](../IMELock/MenuContentView.swift)、[SettingsView.swift](../IMELock/SettingsView.swift) | 菜单栏操作与设置 |
| [DelaySettingView.swift](../IMELock/DelaySettingView.swift) | 等待时间滑块、精确输入和校验 |
| [SettingsWindowPresenter.swift](../IMELock/SettingsWindowPresenter.swift) | 设置窗口置前、显示和最小化恢复 |
| [AppDelegate.swift](../IMELock/AppDelegate.swift) | 隐藏菜单栏图标后的启动和重新打开入口 |
| [MenuBarIcon.swift](../IMELock/MenuBarIcon.swift) | 三种状态的模板图标和分辨率缓存 |
| [IconArtwork.swift](../IMELock/IconArtwork.swift) | 菜单栏与应用图标共用的键盘和角标图形 |
| [LoginItemManager.swift](../IMELock/LoginItemManager.swift) | 系统登录项管理 |

## 恢复逻辑

自动恢复由 `NSWorkspace.didActivateApplicationNotification` 触发。收到通知后按设置等待（默认 200 毫秒），让新应用的输入上下文稳定，再检查一次；连续快速切换时取消旧任务，只检查最后激活的应用。

| 触发场景 | 行为 |
| --- | --- |
| 前台应用切换 | 合并事件后检查一次，必要时切回目标 |
| 停留在同一应用、同一应用内换输入源、窗口或桌面 | 不自动检查 |
| 启动、锁定、手动重试 | 立即检查一次 |
| 打开菜单 | 只刷新当前输入源的显示 |
| 屏幕关闭、休眠、会话停用 | 取消待执行任务，暂停恢复 |
| 唤醒或安全输入结束 | 等待下次应用切换或手动重试 |

代码不注册输入源变化通知，不建立重复定时器，也不定时刷新输入源列表。可用列表只在实际的恢复检查中读取。等待时间范围为 50–1000 毫秒；修改设置时，已排队的应用切换检查会从修改时刻按新值重新等待。

每次检查至多执行一次切换。接口返回后立即确认目标；如果结果还未就绪，最多再等待 200 毫秒做一次结果确认。确认过程不继续尝试切换，也不产生后续检查。

连续 3 次检查恢复失败，或者 2 秒内已尝试恢复 5 次后仍被切走，会进入故障暂停。解锁、退出、休眠和会话停用会取消待执行任务。故障暂停会被持久化，重启后仍需手动重试。

## 累计次数与持久化

只有先观察到当前输入源偏离目标、执行切回，并确认实际输入源已恢复，累计次数才增加 1。接口返回成功本身不会计数；失败尝试、重复观察、首次锁定当前输入源，以及未锁定或暂停期间的变化不计数。启动或手动重试时完成的实际恢复也会计入。

统计包含系统自动切换和用户手动切换后被成功恢复的情况，不区分两者。累计值在重启、解锁和更换目标后保留。

偏好设置仅保存输入源标识和名称、锁定状态、故障类型、检查等待时间、菜单栏显示选项和累计次数。菜单栏显示选项通过 `AppStorage` 保存，默认开启；隐藏只移除菜单栏入口，锁定控制器继续运行。显式打开或重新打开应用时可以进入设置，后台启动保持静默。应用不读取按键内容，不注册全局键盘监听，不请求辅助功能或输入监控权限。登录项由 macOS 的 `SMAppService` 管理。

## 图标资源

菜单栏与应用图标共用 `IconArtwork` 的键盘加右下角角标造型。菜单栏图像标记为系统模板以适配深浅色和选中状态，未锁定、已锁定、暂停三种状态按普通和 Retina 分辨率缓存。应用图标使用已锁定状态的同一图形，配以深色底和薄荷绿前景，按 16–1024 像素分别渲染。

重新生成应用图标：

```bash
bash Scripts/generate-icon.sh
```

README 的界面配图使用实际 `MenuContentView` 和 `SettingsView`，以独立的 ABC 示例输入源、200 毫秒检测延迟和 0 次累计值截图。菜单和设置更新后，应同步更新 `docs/images/interface.png`。
