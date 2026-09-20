# Codex Switch

**一个 Codex 环境，多个登录。放在 macOS 菜单栏里。**

原生 SwiftUI · macOS 13+ · 无第三方包 · MIT

[English](README_EN.md) · [安全边界](SECURITY.md) · [实现说明](docs/ARCHITECTURE.md) · [验收记录](docs/VALIDATION.md)

> **0.2.1 实验版。** 支持 Antigravity CLI 个人 Google 账号管理及官方额度读取。104 项自动化测试通过，macOS 原生构建、安装、界面识别现有账号、真实钥匙串保存、终端启动及运行中阻止切换已验证。Antigravity 第二账号登录和 A → B → A 真实切换仍需独立验收。具体边界见验收记录。

![界面交互预览，使用示例数据；不是 macOS 实机截图](docs/preview.png)

上图来自 `preview/index.html`。可以直接用浏览器打开，体验选账号、等待切换、主题与设置；它不读取任何真实凭证。

## 做什么

菜单栏仅显示图标与剩余额度百分比，账号名称和详情在展开面板中显示。展开后可以查看短 / 长周期额度、距重置时间、准确的本地重置日期，以及接口实际提供的额外 credits 和可用重置次数。点击账号即可请求切换。设置中提供添加、保存当前登录、重命名、移除副本、中英切换、邮箱遮挡和开机启动。

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

## 终端操作

安装脚本会把 `codex-switch` 放进 `~/.local/bin`。若找不到命令，将该目录加入 PATH，或运行 `~/.local/bin/codex-switch`。

```sh
codex-switch start                   # 打开窗口
codex-switch stop                    # 退出本工具，不关闭你的 Codex
codex-switch list                    # 查看账号；* 表示当前账号
codex-switch setup                   # 首次设置：备份配置并启用文件登录
codex-switch save "个人"             # 保存当前登录
codex-switch add "工作"              # 网页登录
codex-switch add "工作" --device     # 设备码登录，用 status 查看设备码和验证地址
codex-switch switch "工作"           # 切换账号
codex-switch status                  # 查看进度、错误和当前账号
codex-switch cancel                  # 取消登录或等待中的切换
codex-switch usage                   # 请求刷新用量，保留原刷新频率限制
codex-switch rename "工作" "工作号"
codex-switch remove "工作号"         # 仅移除保存副本，不注销登录
codex-switch list --json             # 供脚本读取
codex-switch --help
```

终端控制同一个菜单栏应用，未运行时自动在后台启动；`start` 才主动打开窗口。`status` 和 `stop` 在已退出时不会重新启动。账号操作共用界面中的配置、钥匙串和等待状态。

`login_pending` 表示等待官方页面登录；`switch_queued` 表示等待 Codex 客户端退出，最多五分钟；`working` 表示操作进行中。这些不是完成通知，请用 `status` 检查后续结果与当前账号。立即失败返回非零退出码；`--json` 返回 `ok: false`。添加前需退出 Codex 客户端。同名账号必须用 `list` 中的完整 ID。命令不会输出登录凭证。

本机控制通道只接受当前 macOS 用户，位于私有应用数据目录。异常终止后如果残留 `control.sock`，应用会报错而不是自动清理或覆盖；先确认没有其他实例，并保留现场排查。

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

## 选择登录方式

在账号名称上方选择「网页登录」或「设备码登录」，再点击「添加账号并登录」。设备码模式显示一次性验证码、复制按钮和官方验证页面入口；可在另一台设备的浏览器完成验证。取消或完成后会清除显示的设备码。不会在设备码失败时自动改用网页登录。

终端使用 `codex-switch add "名称" --device`，随后运行 `codex-switch status` 查看设备码与验证地址；默认或 `--browser` 使用网页登录。设备码只在登录进行时保存在内存并向本机当前用户显示，不写入账号列表。

官方接口参考：[设备码登录](https://developers.openai.com/zh-Hans/docs/app-server#3b-使用-chatgpt-登录设备代码流程)。

## Antigravity CLI（0.2.0 新增，实验支持）

在窗口或菜单面板上方选择 **Antigravity CLI**。Codex 与 Antigravity 的账号列表、保存副本和操作记录分别存放。菜单栏仍保持紧凑；选择 Antigravity 时显示图标和上下两行百分比：上方 **5H**、下方 **Weekly**。两个面板使用相同的账号卡片、额度进度条和账号列表，Codex 为绿色，Antigravity 为紫色。展开 Antigravity 面板可选择「Gemini」或「其他模型」；后者是 Claude、GPT-OSS 的共享额度，与 Codex 账号额度无关。每五分钟自动刷新，也可手动刷新；未知或过期时显示 `—`，不猜测余额。额度读取需要官方 `agy 1.1.11+`。

目前仅支持官方 CLI 的个人 Google 登录（`consumer`）。企业、GCP、WIF、Gemini API Key 等模式会明确拒绝，不尝试转换。此版本按已检查的本机 CLI 登录格式实现，不是 Google 提供的账号切换接口；升级 agy 后应复验。

1. 已登录 agy：选择“保存当前账号”。默认完整显示邮箱。
2. 添加另一账号：先退出 agy 及 Antigravity 客户端，输入名称，点击“添加账号并登录”。工具先把当前登录保存到钥匙串，再让官方 agy 打开登录。
3. 在终端和浏览器完成登录，退出该 agy 会话，回到工具点击“已登录，保存账号”。登录中断时不会自动把旧登录写回；关闭 agy 后可取消添加，再手动切回已保存账号。
4. 切换：退出相关客户端，点击目标账号，再打开官方 CLI。仍有客户端运行时会拒绝切换并提示，不会终止你的任务。

终端使用：

```sh
codex-switch --provider antigravity start
codex-switch --provider antigravity save "个人"
codex-switch --provider antigravity add "工作"
# 完成官方登录并退出 agy 后：
codex-switch --provider antigravity finish
codex-switch --provider antigravity list
codex-switch --provider antigravity switch "个人"
codex-switch --provider antigravity launch
codex-switch --provider antigravity status
codex-switch --provider antigravity cancel
codex-switch --provider antigravity recover
```

`start` 打开本工具窗口，`launch` 打开官方 agy。`stop` 退出整个 Codex Switch，不结束 agy。`rename`、`remove` 同样支持 `--provider antigravity`。`codex-switch --provider antigravity usage` 读取当前账号的官方额度，随后用 `status --json` 查看完成后的结果。Antigravity 暂不支持 `--device`；不会暗中改用其他登录方式。首次打开终端时，macOS 可能询问是否允许本工具控制 Terminal。

切换只更新官方登录存储和它的文件副本，不复制 HOME，不修改会话、模型、MCP 或技能。保存副本使用独立钥匙串服务 `cc.atou.codex-switchbar.antigravity`；账号信息和恢复标记位于 `~/Library/Application Support/Codex Switch/antigravity/`。官方存储被其他 Antigravity 客户端共享时，重启后这些客户端也可能采用新登录，因此写入前检查相关进程；桌面端账号切换不在本次支持承诺内。

研究依据与实际验收边界见 [Antigravity 接入记录](docs/ANTIGRAVITY-RESEARCH.md) 和 [验收记录](docs/VALIDATION.md)。

## 钥匙串授权（0.2.1）

Antigravity 的共享登录记录改用与官方 agy 相同的 Apple 钥匙串访问程序。正常添加新账号时，不再因为读取方变成 Codex Switch 而每次要求重新授权。没有扩大钥匙串权限，也没有改成明文保存。

macOS 仍决定最终授权：钥匙串锁定、此前选择“仅允许一次”、旧保存副本首次访问或本地签名构建升级，都可能再次询问。不能承诺所有系统状态下永久只弹一次。
