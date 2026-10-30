# 厂商图标来源

应用内厂商图标为开发期获取、本地打包的官方品牌图形，运行时不会联网抓取。渲染时统一放在浅色圆角底上，保证浅色 / 深色外观下都清晰；用户选择自定义 SF Symbol 时优先使用自定义图标，缺失素材时回退中性字母标记。

| 平台 | 文件 | 来源 | 说明 |
| --- | --- | --- | --- |
| DeepSeek | `brand-deepseek.png` | https://cdn.simpleicons.org/deepseek | Simple Icons（CC0）；品牌归 DeepSeek 所有 |
| OpenRouter | `brand-openrouter.png` | https://cdn.simpleicons.org/openrouter | Simple Icons（CC0） |
| Kimi | `brand-kimi.png` | https://cdn.simpleicons.org/kimi | Simple Icons（CC0） |
| GLM / 智谱 | `brand-glm.png` | https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-svg/icons/zhipu.svg | LobeHub Icons（MIT）；品牌归智谱 AI 所有 |
| MiniMax | `brand-minimax.png` | https://cdn.simpleicons.org/minimax | Simple Icons（CC0） |
| Qwen / 通义千问 | `brand-qwen.png` | https://cdn.simpleicons.org/qwen | Simple Icons（CC0） |
| 豆包 Seed | `brand-seed.png` | https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-svg/icons/doubao.svg | LobeHub Icons（MIT）；品牌归字节跳动所有 |
| 腾讯混元 | `brand-hunyuan.png` | https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-svg/icons/hunyuan.svg | LobeHub Icons（MIT）；品牌归腾讯所有 |
| OpenAI GPT | `brand-openai.png` | https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-svg/icons/openai.svg | LobeHub Icons（MIT）；品牌归 OpenAI 所有 |
| Anthropic Claude | `brand-anthropic.png` | https://cdn.simpleicons.org/anthropic | Simple Icons（CC0） |
| Google Gemini | `brand-gemini.png` | https://cdn.simpleicons.org/googlegemini | Simple Icons（CC0） |
| Meta Llama | `brand-meta.png` | https://cdn.simpleicons.org/meta | Simple Icons（CC0） |
| xAI Grok | `brand-xai.png` | https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-svg/icons/xai.svg | LobeHub Icons（MIT）；品牌归 xAI 所有 |
| Mistral | `brand-mistral.png` | https://cdn.simpleicons.org/mistralai | Simple Icons（CC0） |

- 通用 HTTP 没有对应品牌，使用中性字母标记。
- 图标仅用于识别对应厂商；商标与品牌素材权利归各厂商所有。
- SVG 源在开发期转换为 256×256 PNG（`qlmanage`），文件位于 `Sources/OverplayApp/Resources/BrandIcons/`，由 SwiftPM 资源包随应用分发。
- 新增平台时需补充来源、渲染 PNG 并更新 `BrandIconCatalog` 映射；不得在运行时远程抓取。
