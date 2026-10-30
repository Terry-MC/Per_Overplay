# 多语言与语言包

## 内置语言

- 简体中文 `zh-Hans`（默认回退）
- 繁体中文 `zh-Hant`
- English `en`

默认跟随系统语言；系统语言不在上述范围时回退简体中文。设置页可即时切换，选择保存在本机，重启后保持。切换语言会更新主窗口、悬浮窗、托盘菜单 / tooltip、消息中心、告警、空状态、错误提示、日期 / 数字 / 币种格式；已经投递的系统通知不会追溯更新，应用内告警会重新渲染。

## 语言包格式

语言包是 UTF-8 JSON，最大 1MB。示例见 [`examples/language-pack-ja.json`](examples/language-pack-ja.json)。

```json
{
  "formatVersion": 1,
  "locale": "ja",
  "displayName": "日本語",
  "fallbackLocale": "zh-Hans",
  "appVersionRange": ">=1.0 <2.0",
  "strings": {
    "common.cancel": "キャンセル",
    "settings.language.title": "言語",
    "settings.a69e4d32ff": "更新と通知"
  }
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `formatVersion` | 是 | 当前只支持 `1` |
| `locale` | 是 | BCP-47；不能是内置语言 `zh-Hans` / `zh-Hant` / `en` |
| `displayName` | 是 | 语言选择器显示名，不翻译 |
| `fallbackLocale` | 是 | 缺失 key 的回退语言，不能形成循环 |
| `appVersionRange` | 是 | 例如 `>=1.0 <2.0`；支持 `>=`、`>`、`<=`、`<`、`=` |
| `strings` | 是 | 扁平 `key -> 字符串`；不支持嵌套对象、数组或非字符串值 |

### Key 与占位符

- 内置语言 key 清单见 `Sources/OverplayCore/Resources/Localization/zh-Hans.json`；值是该 key 的简中文案。
- 语言包可以使用 key，也可以直接使用简中文案作为 key（例如 `"取消": "キャンセル"`）。
- 含变量的文案使用 `{0}`、`{1}` 占位符；语言包必须保留与内置文案相同数量的占位符，否则拒绝导入。
- 多余的 key 会被忽略；缺失 key 按回退链查找：当前语言包 → `fallbackLocale` → 简体中文 → English → 简中文案。不会把原始 key 显示给用户。
- 用户自定义账户名、语言包 `displayName` 不翻译；官方厂商名与内置文案随语言更新。

### 校验与安全

导入失败不会改变当前语言或已有语言包。以下情况会被拒绝并给出原因：

- 超过 1MB、非 UTF-8、JSON 格式错误、根节点不是对象；
- 缺少必填字段、字段类型错误、`formatVersion` 不支持；
- locale 非法或为内置语言、`fallbackLocale` 形成循环；
- `appVersionRange` 无法解析或与当前应用版本不兼容；
- `strings` 含嵌套值、空值、超长值、重复 key；
- key 含路径穿越字符（`..`、`/`、`\`）；
- 文案含脚本 / 可执行内容（`<script>`、`javascript:`、`onerror=` 等）或 NUL；
- 占位符数量与内置文案不一致。

语言包保存在 `~/Library/Application Support/Overplay/LanguagePacks/`，不会自动下载。设置页可移除当前导入的语言包；内置语言不可删除。清除全部本地数据时可选择是否同时删除语言包。
