# Codex Switch

**一个 Codex 环境，多个登录。放在 macOS 菜单栏里。**

原生 SwiftUI · macOS 13+ · 无第三方包 · MIT

[English](README_EN.md) · [安全边界](SECURITY.md) · [实现说明](docs/ARCHITECTURE.md) · [验收记录](docs/VALIDATION.md)

> **0.1.0 源码预览版。** 50 项核心测试已分别在 Linux / Swift 6.2.1 和 macOS 26.2 / Swift 6.3.3 上通过。Apple Silicon 原生应用已编译、完成本地签名校验并安装启动；界面操作、真实钥匙串、OAuth 和账号切换仍待验收。这里提供完整源代码、Mac 安装脚本和 macOS CI，不把编译成功当成完整实机验收。

![界面交互预览，使用示例数据；不是 macOS 实机截图](docs/preview.png)

上图来自 `preview/index.html`。可以直接用浏览器打开，体验选账号、等待切换、主题与设置；它不读取任何真实凭证。

## 做什么

菜单栏显示当前账号与短周期剩余额度。展开后可以查看短 / 长周期额度、距重置时间、准确的本地重置日期，以及接口实际提供的额外 credits 和可用重置次数。点击账号即可请求切换。设置中提供添加、保存当前登录、重命名、移除副本、中英切换、邮箱遮挡和开机启动。

**不建立多个 HOME。** 所有账号继续使用同一个 `~/.codex`，同一个 `config.toml`、会话历史、MCP 与 skills。切换只写登录文件。账号的保存副本存放在 macOS 钥匙串中，不放进项目目录。

**不做 OAuth 代理。** 添加账号和查询用量通过已安装的官方 `codex app-server` 完成。工具不使用 API Key，不抓浏览器 Cookie，不自己刷新 refresh token，不启动推理任务，不自动轮转账号，也不替你兑换重置次数。

## 必须先知道

共享登录文件不等于已经运行的客户端会立刻切换内存中的身份。这个版本**不会强行热切换**：检测到 Codex App、CLI 或 IDE 中的 Codex 后端仍在运行时，切换请求进入等待状态；你退出这些进程后再完成，五分钟未完成则取消。不强制退出客户端，不声称任务能跨账号无缝续跑。

普通终端窗口可以继续开着，但其中正在运行的 Codex 需要退出。CLI 的 `exit` / Ctrl-D、退出 Codex App，或者关闭 / 停用 IDE 的 Codex 扩展后端可能是必要步骤。仅仅暂停任务、没有新输出，不代表进程已退出。

未启用账号只显示**带时间戳的上次用量**。不会为了刷新每张卡片而后台来回切换账号或独立刷新它们的 token。服务端撤销、过期、其他设备刷新等情况仍可能要求重新登录。

## 安装

需要 macOS 13+、Swift 5.9+ 的 Apple 开发工具，以及已安装的官方 Codex CLI。安装脚本不会自动安装 / 更新 Codex，也不会索取密码、`sudo` 或 GitHub token。

首次没有开发工具时先运行：

```sh
xcode-select --install
```

在源码目录执行：

```sh
bash Scripts/install.sh
```

脚本先运行测试，再编译本机架构、生成图标、进行本地 ad-hoc 签名，安装至 `/Applications/Codex Switch.app` 并打开。安装前需退出旧版 Codex Switch。无需 Xcode 工程文件或 npm 依赖。

只构建，或构建 Apple Silicon + Intel 通用包：

```sh
bash Scripts/build-app.sh
bash Scripts/build-app.sh --universal
```

产物在 `dist/Codex Switch.app`。这是**本地签名而非 Apple 公证**的构建；不要全局关闭 Gatekeeper。自建版本更新后，钥匙串可能重新询问访问许可，请核对应用与路径再批准。CI 产物也不等于已公证发行版。

退出后可从访达的「应用程序」打开 **Codex Switch**。窗口打开时显示 Dock 图标；关闭窗口后继续在顶部菜单栏运行。

## 第一次使用

1. 退出仍在运行的 Codex 客户端，点击菜单栏的双箭头，进入「账号与设置」。
2. 确认共享配置顶层有 `cli_auth_credentials_store = "file"`。缺失时可点击「开始设置（先备份配置）」：原配置先备份，只在最前面添加该设置。如果原来明确配置了 `keyring` / `auto`，工具不会自行迁移；手动调整并重新用官方登录确认账号，避免误用旧文件。
3. 点击「保存当前账号」，把已有登录加入列表。再输入新账号名称，点击「添加账号并登录」，在官方浏览器页面选择目标账号。新账号成为当前账号，旧账号仍保存。浏览器若复用了已有账号，不会创建重复账号或悄悄改名。
4. 点击列表中的账号进行切换。额度自动每五分钟读取一次；刷新按钮有十五秒节流。网络失败保留上次结果并标注状态，不把未知当成零。

邮箱默认遮挡。界面语言默认跟随系统，可切换中文 / English。菜单栏的百分比可以关闭。

## 用量的含义

`100 − usedPercent` 才是剩余额度。窗口长度和重置 Unix 时间取自官方 App Server，不假设所有账号都是 5 小时 / 7 天。到达重置时间后显示「待刷新」，**不会自行把额度变成 100%**。

额度百分比并不是 token 数，也不是美元余额。仅当接口返回额外 `credits.balance` 时才展示 credits，不擅自标 `$`；未提供就是「未提供」。可用重置次数只显示、不使用。额外用量桶可展开查看。

「打开官方用量页面」使用浏览器自己的登录状态，可能与当前 CLI 账号不同，页面打开前后都不会同步浏览器身份。

## 文件与凭证

```text
~/.codex/                                  # 唯一、现有的共享环境
  config.toml                              # 切换时不修改
  auth.json                                # 当前官方登录，0600
  sessions/ …                              # 不复制、不删除

~/Library/Application Support/Codex Switch/ # 私有目录，0700
  accounts.json                            # 账号标签、身份、用量缓存；不含 token
  transaction.json                         # 仅操作恢复标记，不含 token
  store.lock

macOS Keychain
  service: cc.atou.codex-switchbar.credentials
  account: 随机 UUID                         # 账号凭证保存副本；不启用 iCloud 同步
```

元数据包含邮箱和工作区标识，仍属于隐私数据。不要提交到 GitHub。活跃 `auth.json` 仍是文件凭证，**钥匙串只保护额外保存的副本**。

默认使用 `~/.codex`。从 Finder 启动的应用通常不会继承交互 shell 的环境变量；已有自定义 `CODEX_HOME` 时，在退出本工具后明确设置**一个全局路径**：

```sh
defaults write cc.atou.codex-switchbar codexHome -string "/absolute/path/to/your/existing/codex-home"
```

该设置仍对全部账号共用；不要在使用中反复改路径。符号链接 HOME、凭证符号链接 / 硬链接、无法识别的凭证或配置会被拒绝，而不是猜测着改写。

## 兼容范围

本工具管理的是官方 ChatGPT OAuth 的**共享文件登录**，不是浏览器会话、Provider 列表或 API Key。它不会修改 `model_provider`、代理地址、强制工作区或企业策略。已有 CC Switch / 其他工具仍会改写登录时，请先停止其自动切换；已有第三方 Provider / 代理配置时，需自行确认官方 Codex 实际使用哪条认证路径。

CLI 是主要目标。桌面 App 与 IDE 只有在确实使用这套共享文件认证时，才可能在退出重开后采用切换结果；这些客户端的具体版本尚未实机验证。菜单栏不冒充读取每个进程的内存登录。

## 官方 CLI 没被发现

应用会查找 PATH、Homebrew、`~/.local/bin` 和常见官方桌面安装位置。使用 nvm / 自定义安装路径时，在设置里选择官方 `codex` 可执行文件。不要选来历不明的代理程序。自定义 shell wrapper 不在验收范围；扫描器无法可靠识别任意改名后的客户端。

## 异常恢复 / 移除

异常中断后有事务标记时，设置中会显示「核对并恢复」。恢复以**当前文件里的实际登录**为准，不自动把旧 token 覆盖回去。无法确认时停止，保留数据；「仅清理标记」需明确确认，且不修改登录文件。

「移除副本」仅删除工具保存的账号，不会执行 `codex logout`，不会删除当前登录或会话。要彻底移除工具，先在 UI 中移除已保存账号、关闭开机启动、退出，再删除 `.app` 与应用支持目录；官方 `~/.codex` 保留。

## 开发与验证

```sh
swift test
python3 Scripts/check-source.py
bash Scripts/build-app.sh       # 仅 macOS
```

Swift Package 没有外部依赖。`SwitchCore` 可在 Linux 跑测试；SwiftUI、Security.framework、登录项与目录监听只在 macOS 编译。源码中的测试凭证全部是运行时生成的合成数据。

[验收记录](docs/VALIDATION.md) 明确区分已执行和未执行项。发布前应让 macOS CI 通过，并完成至少一次 A → B → A 的真实登录验收。

## 创建新的公开 GitHub 仓库

此源码包**没有替你创建远端仓库**。在你本机已有 GitHub CLI 登录时，从刚解压、尚无 `.git` 的源码目录运行：

```sh
# 尚未安装 / 登录 gh 时才需要：
brew install gh
gh auth login

bash Scripts/publish.sh
```

脚本检查当前 GitHub 身份必须是 `atou42`，扫描源码中常见凭证痕迹，然后创建新的**公开**仓库 `atou42/codex-switchbar` 并推送初始提交。已存在仓库、已有 `.git` 或无法确认身份时停止，不修改旧项目。可通过首个参数指定另一个新仓库名。GitHub 授权只在本机官方 `gh` 中完成；不要把 token 发进聊天或源码。若推送 `.github/workflows` 被 GitHub 拒绝并提示缺少 `workflow` scope，可在本机检查并按需运行 `gh auth refresh -h github.com -s workflow`；这是上传 CI 文件的 GitHub 权限，不是 Codex 的权限。若远端已创建但推送失败，脚本不会覆盖重试；核对 `git remote -v` 后再手动 `git push -u origin main`。

内附 macOS Actions：构建、测试、打包为工作流 artifact。不自动发布 Release、不部署服务。工作流是否实际运行成功，应以你的仓库 Actions 结果为准。

## 参考与许可

UI 参考 CodexBar 的紧凑额度面板、Codex Switcher 的账号列表；代码独立实现，无第三方代码或素材打包。[具体来源](docs/REFERENCES.md)。非 OpenAI 官方产品。MIT 许可。
