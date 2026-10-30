# Overplay（构建产物：DSOverplay.app）

macOS 14+ 菜单栏应用，提供常驻的**简略版悬浮窗**与**完整版主窗口**：悬浮窗用于快速查看今日费用、余额 / 额度、tokens 与告警，主窗口用于基础信息、用量分析、额度与预算、新增厂商、厂商详情、消息与设置。支持本地预算 / 余额低水位告警、告警线、余额快照曲线、CSV 导出、演示模式与本地持久化。**真实连接器支持 DeepSeek、OpenRouter 与用户配置的通用 HTTPS 只读端点**；演示模式额外提供 Kimi、GLM、MiniMax、Qwen、豆包 Seed、腾讯混元、OpenAI GPT、Anthropic Claude、Google Gemini、Meta Llama、xAI Grok、Mistral 的虚拟数据，用于演示多平台 / 多账户 / 跨币种展示。

> 这个 demo 是用 DSH 测试开发的一个 demo，开源仅支持个人实践 / 学习，这个 demo 不可商用。
> This demo is developed and tested with DSH. It is open-source for personal practice and learning only. Commercial use of this demo is prohibited.

## 构建与运行

要求：macOS 14+、Apple Silicon、Swift 5.9+（Xcode 15+ 或 Command Line Tools）。运行测试需要完整 Xcode（XCTest 随 Xcode 提供）。

```bash
./build.sh                 # 生成 DSOverplay.app（ad-hoc 签名）
open DSOverplay.app        # 启动菜单栏应用
```

首次启动会先展示 issue-001 的引导；完成或关闭引导后显示简略版悬浮窗，后续启动直接恢复上次的悬浮窗位置、宽度、密度与收起状态。真实模式可添加 DeepSeek / OpenRouter 账户；演示模式（需先确认免责声明）内置 14 个平台的虚拟账户。`--show` 可直接打开完整版主窗口，默认进入“基础信息”；菜单栏图标左键 / 双击打开或前置悬浮窗，右键显示菜单；关闭主窗口只是隐藏。

开发模式下可直接运行并输出调试信息：

```bash
./DSOverplay.app/Contents/MacOS/DSOverplay --demo --show
```

## 测试

```bash
./test.sh
```

`test.sh` 会在检测到 `/Applications/Xcode.app` 时自动设置 `DEVELOPER_DIR`，然后执行 `swift test`。当前测试覆盖：

- 金额 / 币种格式化、Decimal 精确累加、分币种聚合；
- 时间桶、时区与自然月边界、月末线性外推；
- SQLite 账户 / 快照 / 告警持久化，usage upsert 幂等与历史保留/删除；
- DeepSeek / OpenRouter 连接器的成功、401 / 403、429 + Retry-After、超时、空响应、畸形 JSON、缺失字段、BYOK 字段与部分成功；
- 预算 80% / 100%、余额低水位、连续同步失败、凭据失效、数据过期，以及去重、滞回与 6 小时冷却；
- 单账户 single-flight、凭据缺失、部分成功不触发预算告警；
- 自动刷新计时、启动错峰、5 分钟周期、指数退避、429 Retry-After 与凭据失效暂停重试；
- 部分成功/凭据失效时预算不可用（不显示 0 或完整剩余）、手动刷新取消与在途写入保护；
- 真实 `URLSession` 对 302 重定向的拒绝（本地一次性 HTTP 服务）；
- Keychain 实际读写（测试使用独立 service 并在结束时清理）；
- CSV 字段、转义、来源 / 时间范围 / 演示数据标识与无密钥；
- 数据状态：真实 0、缺失、不可用、部分成功、失败 / 凭据失效、厂商余额异常；
- 平台 / 账户范围聚合、跨币种隔离、额度与预算排除不完整账户、币种选项与默认选择；
- 消息筛选、未确认计数、顶部队列上限、error 不自动消失、80% 倒计时与归档；
- 演示数据 14 平台 / 16 账户 / 每账户 30 个完整 UTC 日且不含今天；
- 悬浮窗位置 / 宽度 / 密度 / 收起状态持久化与多显示器钳制、简略版字段映射、退出清理顺序；
- 状态项演示标识在有未确认告警时仍保持可见，以及告警级别的符号 / 可访问性映射；
- 共享时间范围：今天 / 本周 / 本月 / 今年、7 / 30 / 90 天与自定义区间，自定义分钟精度、起止校验与 365 天保留期；
- 厂商 token / 费用 / 请求数聚合、覆盖率、缺失字段不按 0 计入、图表缺失日期断点与月 / 年聚合、余额快照按币种 + 时间桶取最后值；
- 单账户刷新失败不影响其他账户数据、同一账户 single-flight，以及 429 / Retry-After 后手动刷新冷却；
- 删除一个账户（保留 / 删除历史两种模式）不会影响其他账户的账户、凭据、用量、余额与额度数据。

当前共 **181 项 XCTest**，全部通过。

另提供应用内自动化验证：`--demo --switch-smoke` 覆盖主窗口 / 悬浮窗切换、折叠、收起、消息中心、五个 Tab 切换、厂商详情打开与托盘面板路径，断言 0 次刷新调用与 0 个网络请求；`--demo --collapse-floating --auto-quit-after N` 用于收起后空闲 CPU 采样。`--demo --show --detail-account <account-id>` 可直接打开指定账户详情截图；`--window-width 1080` 可验证最小窗口宽度下的平台栏换行；`--demo --tab addProvider --alert-line-account <account-id> --snapshot <path>` 可直接截取告警线编辑器。

新增覆盖：通用 HTTP 配置 / JSON 映射 / SSRF 校验 / 连接测试失败分类（403 / 429 / 400 / 404 / 405 / 超时 / 网络 / 重定向 / 畸形）、表单必填 / 重复 / URL 校验、通用 HTTP 账户状态 / 余额与额度聚合 / 预算集成、账户 profile 与公共告警线持久化、三态阈值传播、预算 / 配额 / 余额 / Token 四类告警线、去重 / 恢复 / 新自然月重新布防、托盘与 toast 告警线级别。本轮界面验收项——平台筛选栏最小宽度自动换行、必填标识与保存禁用原因、官方品牌图标浅色 / 深色显示——通过截图与可重复手工步骤验证，未纳入 XCTest。Keychain 无明文沿用既有测试；未保存退出确认与跨视图 UI 一致性仍为手工验证项。

## 功能范围

- **DeepSeek**：普通 API Key；`GET /user/balance` 读取总余额、赠送余额、充值余额与币种；每次成功同步保存快照，两次以上展示余额曲线。每个账户按官方返回的币种分别展示余额；多币种账户分行展示，不混合其他币种；余额阈值只作用于当前账户，币种跟随该账户。官方没有历史 token / 费用接口，界面明确显示「厂商未提供」，不会伪造为 0。
- **OpenRouter**：需要 **Management Key**；读取 `GET /api/v1/credits` 与 `GET /api/v1/activity`。按日 / 模型展示 prompt、completion、reasoning、缓存 tokens、请求数与 usage 费用；BYOK 费用单独标注；用量窗口约最近 30 个 UTC 日；普通 API Key 会得到“需要 Management Key”的可操作提示。
- **简略版悬浮窗**：无边框、置顶、非激活式、可拖动的常驻窗口；支持完整 / 压缩两档密度。顶部四个按钮为退出、折叠、收起、打开完整版；全局摘要显示今日费用（分币种）、官方余额 / 额度、Token 总量与覆盖率、请求数、告警状态 / 未确认数与最后同步时间；账户列表固定状态栏、内部滚动。缺失数据使用空状态，不显示 0。收起后仅保留托盘，轮询与告警继续；重启恢复位置、宽度、密度与收起状态，屏幕变化后自动钳制到可见区域。
- **托盘**：菜单栏状态项常驻，左键 / 双击打开或前置悬浮窗（收起时恢复），右键菜单提供打开悬浮窗、打开主窗口、打开快捷面板、刷新全部、设置与退出。图标使用模板 SF Symbol（矢量图，系统按菜单栏 16 / 18 / 22 / 44 px 与 @2x 自动渲染，无位图裁切），按正常 / 告知 / 警戒 / 失败切换形状与颜色，并提供 tooltip。演示模式无论是否有未确认告警，状态项都固定显示“演示”文字标识，右键菜单顶部固定显示“演示数据 · 不发起网络请求”，不会把演示告警误认为真实数据。
- **简略 / 完整双向切换**：悬浮窗“打开完整版”或编辑按钮打开主窗口；主窗口“简略版”按钮或关闭主窗口返回悬浮窗（若未收起）；托盘同时提供两个入口，复用同一数据 / 同步 / 告警引擎，不重建数据或重复请求。
- **基础信息（默认页）**：完整版主窗口为“基础信息 / 用量分析 / 额度与预算 / 新增厂商 / 设置”五个页签。基础信息按平台 / 账户过滤，显示所选时间范围的 token 总量、各厂商汇总、分币种费用、请求数与覆盖率；token 总量不含未提供 token 的厂商，缺失数据不补 0。平台筛选栏在最小窗口宽度下自动换行，所有平台和账户 chips 均可触达并显示换行提示；厂商卡片显示主指标、官方额度 / 本地预算中性进度、告警线生效值 / 来源、健康状态、最后同步、刷新、删除、详情入口；标题栏与消息中心入口保持不变。
- **新增厂商**：预设 DeepSeek / OpenRouter / 通用 HTTP；未接入的真实组织级平台明确标注“暂不支持”，不会创建虚假监控账户。表单支持显示名称、官方名称、图标、API Key、Base URL / 端点 / 认证方式 / JSON 字段映射；必填 / 可选字段均有可见标识，保存按钮禁用时显示原因与“保存前还需完成”清单；连接测试成功后才允许保存；编辑名称 / 图标可直接保存，修改通用 HTTP 端点或认证需要重新测试。通用 HTTP 仅支持单个 HTTPS GET 端点、Bearer / 自定义 Header 与点号路径映射，拒绝 localhost / 私网 / 云元数据地址，重定向由传输层拒绝。厂商图标使用开发期获取、本地打包的官方品牌图形，浅色 / 深色均清晰；无素材或用户自定义图标时回退中性标记，运行时不会联网抓取。来源见 [`docs/brand-icons.md`](docs/brand-icons.md)。
- **告警线**：公共告知 / 警戒百分比 + 单厂商三态（关闭 / 跟随公共 / 自定义）；支持预算 %、配额 %、余额绝对值、Token 绝对值。未启用不显示标记；无分母不显示百分比；数据不可用 / 过期 / 不新鲜不触发；同周期同规则只触发一次，恢复后重新布防，新自然月重新评估。新账户默认关闭，旧预算 / 余额固定阈值保留并在 UI 标注，保存新告警线前提示覆盖关系。
- **时间范围与粒度**：基础信息、用量分析、额度与预算、厂商详情共享时间范围；支持今天 / 本周 / 本月 / 今年、7 / 30 / 90 天与自定义区间，自定义精确到分钟并校验开始晚于结束、超出 365 天保留期。用量记录只有厂商 UTC 日桶，因此 token / 费用 / 请求数只提供自动 / 日 / 月 / 年，分钟 / 小时禁用并说明；DeepSeek 余额快照带真实时间戳，支持分钟 / 小时 / 日 / 月 / 年。自然单位按本机时区，厂商日桶按 UTC，界面持续标注口径。
- **厂商详情**：点击厂商卡片进入；显示区间总量、Prompt / Completion / Reasoning / Cached 分阶段、请求数、BYOK（OpenRouter）、首日 / 末日 / 峰值变化；趋势图可切换 Token / 费用 / 请求数，缺失日期断开折线、不补 0。DeepSeek 只展示余额快照曲线与阈值，不画 token 折线；OpenRouter 标注约 30 天窗口；Gemini 演示平台标注真实 AI Studio 受限，不推断未配置指标；OpenAI / Anthropic 演示账户显示“组织级”标签。
- **用量分析**：保留费用按厂商堆叠、token 趋势、模型拆分、明细与占比；共享基础信息的时间 / 平台 / 账户筛选；CSV 导出当前筛选。趋势图保留所选范围的全部日期，缺失日期留空且不补 0；当天无数据时直接显示空白并提示下一 UTC 日回填。
- **数据状态**：只有厂商明确返回 0 时才显示真实的 0；缺失、不可用、未同步、部分成功、同步失败或凭据失效显示「无数据 / 不可用 / 暂无完整数据 / 同步失败」等空状态与原因，不使用 `0`、`0?` 或 `0%` 占位。部分成功 / 缺失数据不参与预算、额度使用率或阈值告警计算。
- **消息中心**：顶部最多同时显示 3 条消息并叠加显示，不挤压布局；error 类消息（预算已用尽、余额低于阈值、同步失败、凭据失效）需手动关闭，预算 80% 通知倒计时后归档，普通告知倒计时后关闭，不显示进度条。消息中心从顶部消息、基础信息或额度与预算页打开，支持搜索、类型 / 账户 / 状态 / 时间筛选、确认与未确认计数；基础信息 / 额度与预算不再各自维护旧告警列表。演示来源消息持续标注「演示数据」。
- **预算与告警**：本地月度预算（80% / 100%；真实模式当前为 OpenRouter，演示模式还覆盖 Kimi、GLM、Qwen、OpenAI、Anthropic、Mistral）、DeepSeek 余额低水位、连续 3 次同步失败、凭据失效、超过 2 个刷新周期未成功同步；应用内消息中心 + 本地通知；同一预算阈值同月只触发一次，余额回升后重新布防，同步失败冷却 6 小时。
- **刷新**：全部 / 单账户手动刷新；自动刷新默认 15 分钟（5–60 分钟可配置）；指数退避与 Retry-After；429 / 受限请求会按 Retry-After 阻止手动重复刷新并显示剩余秒数；同一账户 single-flight；同步不阻塞 UI。
- **多语言与语言包**：内置简中 / 繁中 / 英文，默认跟随系统，不支持时回退简中；设置页即时切换并持久化。主窗口、悬浮窗、托盘、消息中心、告警、空状态、错误、日期 / 数字 / 币种格式同步更新。支持导入本地 JSON 语言包（UTF-8、≤1MB、formatVersion / locale / displayName / fallbackLocale / appVersionRange / strings），校验失败不改当前语言；缺失 key 按回退链回退，可移除导入语言包，内置语言不可删除。格式与安全校验见 [`docs/localization.md`](docs/localization.md)，示例见 [`docs/examples/language-pack-ja.json`](docs/examples/language-pack-ja.json)。
- **设置页**：语言、刷新与通知、账户管理、演示模式、数据与隐私、关于、退出。通知开关真实持久化并显示系统权限状态；权限被拒绝时关闭本地通知并引导到系统设置。账户列表可编辑 / 删除（演示模式禁用并说明原因）；支持导出 CSV；清除全部本地数据需两次确认，并询问是否同时删除导入的语言包。
- **退出**：悬浮窗关闭、托盘、设置页、菜单栏与系统退出统一清理；停止定时器 / 请求、保存窗口状态、关闭窗口并移除托盘；新增厂商表单未保存时，切换 Tab、切到简略版、关闭主窗口、退出（含 AppleScript / 系统退出）都会确认，取消则保留内容。
- **演示模式**：悬浮窗、托盘和主窗口共享 14 个平台 / 16 个账户、30 个完整 UTC 日的虚拟数据与告警；DeepSeek 含 CNY / USD 两个账户，Kimi 含主账户 / 团队账户；其余平台包括 OpenRouter、GLM、MiniMax、Qwen、豆包 Seed、腾讯混元、OpenAI GPT、Anthropic Claude、Google Gemini、Meta Llama、xAI Grok、Mistral。所有演示内容持续标注「演示数据」，导出文件带 `demo` 标记；**不发起外部网络请求、不读写 Keychain、不打开真实数据库**。演示用量仅覆盖最近 30 个完整 UTC 日（不含今天），因此「今日费用」等当天视图会如实显示空状态。

界面效果（均为演示数据）：

| 简略版悬浮窗（展开） | 简略版悬浮窗（压缩） |
| --- | --- |
| ![悬浮窗展开](docs/screenshots/floating-expanded.png) | ![悬浮窗压缩](docs/screenshots/floating-compact.png) |

| 托盘右键菜单（演示标识） | 基础信息（默认页：范围 / 覆盖率 / 厂商卡片） |
| --- | --- |
| ![托盘菜单](docs/screenshots/tray-menu.png) | ![基础信息](docs/screenshots/overview.png) |

| 新增厂商（必填标识 / 保存原因 / 官方图标） | 告警线编辑器（校验提示 / 演示禁用原因） |
| --- | --- |
| ![新增厂商](docs/screenshots/add-provider.png) | ![告警线编辑器](docs/screenshots/alert-line-sheet.png) |

| 演示托盘标识（浅色系统外观） | 演示托盘标识（深色系统外观） |
| --- | --- |
| ![浅色](docs/screenshots/status-demo-light.png) | ![深色](docs/screenshots/status-demo-dark.png) |

| 平台选中与账户 chips（窄窗口自动换行） | DeepSeek 官方余额（CNY / USD 分币种） |
| --- | --- |
| ![平台与账户 chips](docs/screenshots/platform-accounts.png) | ![官方余额币种下拉](docs/screenshots/balance-currency.png) |

| 空状态：无数据 / 不可用 | 设置 |
| --- | --- |
| ![空状态](docs/screenshots/empty-state.png) | ![设置](docs/screenshots/settings.png) |

| 顶部消息（最多 3 条；error 手动关闭） | 消息中心面板（无独立 Tab，可筛选 / 确认） |
| --- | --- |
| ![顶部消息](docs/screenshots/messages-toasts.png) | ![消息中心](docs/screenshots/messages.png) |

| 用量分析（多平台堆叠） | 额度与预算 |
| --- | --- |
| ![用量分析](docs/screenshots/usage.png) | ![额度与预算](docs/screenshots/quota.png) |

| 厂商详情（OpenRouter 日级趋势） | 厂商详情（DeepSeek 余额快照） |
| --- | --- |
| ![OpenRouter 详情](docs/screenshots/provider-detail.png) | ![DeepSeek 余额详情](docs/screenshots/provider-balance.png) |

| 删除账户二次确认 | 厂商详情 · 同步失败保留上次有效图 |
| --- | --- |
| ![删除确认](docs/screenshots/delete-confirmation.png) | ![同步失败](docs/screenshots/provider-error.png) |

额度与预算页按账户展示 DeepSeek 币种与阈值，两个账户的 CNY / USD 余额不会合并；部分成功或缺失数据不计算使用率 / 剩余 / 预估。厂商详情按数据源能力展示日级趋势或余额快照，缺失日期断开、不补 0；同步失败时保留最近一次有效图并标注错误。

另有引导页与深色模式截图：`docs/screenshots/onboarding.png`、`docs/screenshots/dark-overview.png`。

## 数据与安全

- 所有数据仅保存在本机：`~/Library/Application Support/Overplay/overplay.sqlite`（目录 0700，SQLite WAL）。
- API Key **只保存在 macOS Keychain**（`local.ds.overplay.credentials`，`AfterFirstUnlockThisDeviceOnly`，不随 iCloud 同步）；数据库、UserDefaults、日志、告警与 CSV 中不包含明文 Key。
- 请求仅发往 `api.deepseek.com`、`openrouter.ai` 的固定 HTTPS 接口，以及用户明确配置并通过 SSRF 校验的通用 HTTPS 只读端点；传输层拒绝重定向；无遥测、无第三方统计、无远程配置；不调用推理接口、不代理 LLM 请求。
- 错误信息与厂商返回的错误摘要会脱敏 Authorization / Key；界面不提供 Key 明文回显。
- 退出时停止定时器、取消进行中的请求并退出；关闭主窗口不会退出应用。
- 删除账户会删除 Keychain 凭证，并提供「同时删除历史数据」选项（默认关闭，保留但不参与默认统计）。
- 「清除全部本地数据」需要两次确认，会删除账户、Keychain 凭证、历史用量、快照、告警与设置，并询问是否同时删除导入的语言包；语言偏好恢复为跟随系统。演示模式需先退出，避免触碰真实数据。

## 演示模式

- 入口：首次引导或设置页；进入前展示完整免责声明，取消则不进入。
- 演示数据位于内存命名空间，不读取真实账户或凭证；不启动同步引擎，因此不会产生任何外部请求。
- 演示数据覆盖 14 个平台、16 个账户，每个有用量数据的账户都包含 30 个完整 UTC 日（不含今天）；趋势图保留所选范围最后一天的空位并给出提示，不隐藏、不补 0。
- 演示平台只有虚拟数据与能力声明，真实账户编辑器仍只允许 DeepSeek / OpenRouter；未接入平台由 `UnsupportedConnector` 明确拒绝，不会发起真实请求。
- 导出 CSV 文件名含 `demo`，内容含「是否演示数据」列与「演示数据」标识；演示告警不会发送系统通知。
- 演示模式会持久化开关；下次启动仍为演示模式，所有页面继续显示演示标识。退出后回到真实模式。

## 已知限制

- 真实连接器接入 DeepSeek、OpenRouter 与通用 HTTP MVP。Kimi、GLM、MiniMax、Qwen、豆包 Seed、腾讯混元、OpenAI GPT、Anthropic Claude、Google Gemini、Meta Llama、xAI Grok、Mistral 目前只有演示虚拟数据，没有同步引擎、凭据校验或真实接口；新增厂商页明确标注“暂不支持”，不会创建虚假监控账户。
- DeepSeek 无历史用量 / 费用接口，只能展示余额快照，不提供 token 趋势或百分比额度。
- OpenRouter activity 仅覆盖最近约 30 个 UTC 日；超出窗口不显示、不补 0。费用 / token 趋势图保留所选范围的全部日期，缺失日期留空；当天数据通常要到下一 UTC 日才可见。OpenRouter 金额为 USD，credits 与本地预算分开展示。
- 用量 / 费用 / 请求数只存厂商 UTC 日桶，无法提供真实分钟 / 小时曲线；分钟 / 小时仅适用于 DeepSeek 余额快照。自定义区间精确到分钟，但按日桶记录的统计会包含所选日期范围，不会把日级数据上采样。
- 本地最多加载 365 天用量与余额历史；更早区间会提示超出保留期。演示数据仍只有最近 30 个完整 UTC 日。
- 厂商详情中的组织级标签目前用于 OpenAI / Anthropic 演示账户；真实组织级接入后需要 Account 模型增加组织级字段。Gemini 演示平台不代表真实 AI Studio 能力，真实接入在后续连接器 issue 中限制为仅本地预算。
- DeepSeek 每个账户只设置一个余额低水位阈值，币种必须与该账户余额接口返回的币种一致；若一个账户返回多个币种，可在这些币种中选择一个作为该账户的阈值。不同账户 / 币种不合并统计。
- 月度预算按本机自然月聚合厂商 UTC 日桶，可能不含当天且仅覆盖约 30 天窗口；数据不完整时不触发预算告警。额度页同时展示「所选分析范围」的独立统计，并明确其不参与本地月度预算；发生跨月时不会把所选范围当作预算周期。预估值为线性外推，仅作参考。
- 通用 HTTP MVP 仅支持单一 HTTPS 只读 GET 端点、Bearer / 自定义 Header 与点号路径 JSON 映射；不支持 OAuth、多端点、数组逐项映射或远程图标抓取。SSRF 校验拒绝字面 localhost / 私网 / 元数据地址，并依赖传输层拒绝重定向；DNS 解析到私网的极端场景仍建议在网络层限制。
- 旧 `config.json` 不会自动读取；本版本要求用户手工录入，旧文件迁移仍待提供明确样例后处理，不访问 `overplay/`。
- 新增厂商演示模式可模拟连接测试成功，但不联网、不写 Keychain、不落库；真实 Key、系统通知、AppleScript / 系统退出、429 / 超时 / 401 / 403 与畸形 JSON 仍需验收阶段手工复核。
- 旧预算 / 余额固定阈值与新告警线同时存在时，保存新告警线后旧固定阈值不再单独触发；同一告警线每级只支持一个指标，无法同时表达预算与余额两条绝对规则。
- 首版仅 Apple Silicon 构建；未提供 DMG、签名公证、自动更新与随系统启动。
- 不支持跨币种换算或统一总额；不同币种分开展示。

## 目录结构

```text
Sources/OverplayCore/   # 存储、Keychain、连接器、同步、告警、演示数据、CSV
Sources/OverplayApp/    # AppKit 生命周期、菜单栏、SwiftUI 主看板
Tests/OverplayCoreTests # XCTest 单元与集成测试（fixtures / mock transport）
docs/screenshots/       # 演示数据截图
build.sh                # 构建 .app
test.sh                 # 运行测试
```
