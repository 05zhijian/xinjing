# 心镜 · AI 陪伴日记

一个会**记住你**的 AI 陪伴日记 App（Flutter）：日常对话与觉察日记沉淀成对你的了解，并且把这份了解**显化成一只会演化的「镜灵」**——由你自己的记忆画出来的具象自我。

- 三层记忆架构：聊天/日记从「原始记录」沉淀为「长期认识」
- 镜灵：物种代表你是谁，画面跟随你最近的经历而变化（真实 AI 生图）
- 隐私优先：记忆全在本地 `documents/xianhuadewo/`，只把提炼后的文本发给 AI/生图平台
- 无后端、一人一 key：对方填一个自己的 key 即可用全部功能

## 核心亮点

| | 说明 |
|---|---|
| 🧠 三层记忆 | 工作记忆（会话窗口）/ 情景记忆（本地向量检索）/ 语义记忆（画像）。日记后自动 **consolidate**，把散对话提炼成「目标 / 在意 / 事实」画像与一句洞察，越聊越懂你 |
| 🦊 镜灵 | 具象化身：**身份固定 × 状态演化**。首次显化从候选物种池选定（白狐 / 水獭 / 棕熊…）并锁定；之后只让环境、光线、道具跟随最近记忆漂移。每次存档成「演化史」，一眼看到你变了什么 |
| 🔑 单 key 分发 | 服务商可切换：**智谱**（GLM 对话 + CogView 生图，一个 key 全通）/ **DeepSeek**（纯文本）。不内置任何 key，装机后在右上角 ⚙️ 填自己的 |

**画像会自我修正**：每 7 篇日记自动跑一次「画像审查」，把过时/被推翻的了解降级并留一句变化记录；每篇日记都在刷新条目强度，说错的你随时能在「我的」页点「放下」。

## 镜灵长什么样

> 你最近总在熬夜赶作品集、话变少、聊到想做的事眼睛会亮 →
> **「一只冬夜白狐，趴在堆满纸稿的书桌上，尾尖沾着未干的墨蓝。」**
> 不是狼（太群居）、不是猫（太慵懒），是白狐——这是 AI 从你的画像里「看」出来的。

镜灵 = 不变的你（物种、底色、性格标签） × 会变的你（场景、天气、心境、道具）。

```
三层记忆 ──► 映射层：画像+近期记忆 → AvatarSpec JSON   （DeepSeek/GLM，本地校验）
                    │  只把具象描述发出去（隐私红线）
                    ▼
             出图层：CogView → PNG 落盘 → 演化史 gallery  （智谱，可插拔）
```

身份锁定规则：物种生成一次即锁死，模型想「改口」也不会漂移；只有用户主动「重置身份」才会重选。场景没变化时不会重复出图、不花冤枉钱。

**会听人话**：觉得不像，在镜灵页说一句「别这么阴郁，我最近挺开心的」——反馈存进本地，下一次显化就按你的话调氛围和场景；想换物种，用「重置身份」重新生成（反馈也会参与重新定身份）。

## 技术栈

Flutter / Dart · 本地字符 n-gram 哈希嵌入（自包含、不限流、确定性可测）· JSON 文件持久化 · DeepSeek `deepseek-v4-flash` / 智谱 `glm-4-flash` + `cogview-3-flash`

## 运行

```bash
cd ai_diary_demo

# Windows 桌面
flutter run -d windows

# Android 设备 / 模拟器
flutter run -d <device-id>
```

首次使用：右上角 **⚙️ AI 设置** → 服务商选 **智谱** 或 DeepSeek → 粘贴你自己的 key → 保存。

- **智谱 · 推荐（含生图）**：一个 key 同时解锁对话/日记/镜灵真图（CogView）
- **DeepSeek · 纯文本备用**：无生图，镜灵用占位画布；智谱限流时可切过来应急

默认服务商规则：显式 `--dart-define=AI_PROVIDER=` 优先 → 有智谱 key 用智谱 → 只有 DeepSeek key 时用 DeepSeek → 都没有（分发的 APK）默认智谱并引导去 ⚙️ 配 key；你在设置里显式选过的一律优先。

先聊几句、生成一篇觉察日记，再到「我的 → 镜灵」点 **显化镜灵**，就能看到 AI 为你画的形象。

### 打包 Android APK（不内置 key，可直接分发）

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 别用 `--dart-define` 塞 key——分发对象应该填自己的 key（见「单 key 分发」）。
> 换文件名再发 QQ/微信，避免同名缓存装到旧包。

## 测试

```bash
flutter analyze   # 0 issues
flutter test      # 58 个测试全绿
```

覆盖：向量嵌入确定性 / 三层 recall 合并 / consolidate 去重与洞察回写 / 画像容错解析 / 镜灵身份锁定与场景演化 / 生图落盘与失败兜底 / 壳层 ⚙️ 打开 AI 设置。

集成测试（真实 AI，需 key）：

```bash
flutter test integration_test/app_test.dart -d <device> --dart-define=DEEPSEEK_API_KEY=你的key
```

## 文档

- `AI_Diary_DevDoc.md` — 三层记忆架构设计（工作/情景/语义）
- `XINJING_Avatar_DevDoc.md` — 镜灵设计（映射层 schema、物种池、演化规则、出图层、真实接口记录）
- `JUEJIN_三层记忆架构.md` — 掘金文章《给 AI 陪伴日记 App 设计三层记忆：工作 / 情景 / 语义》

## 隐私

- 记忆文件（画像/情景/日记/镜灵）全部存在本机 `documents/xianhuadewo/`，不上你自己的服务器
- 发给云端（对话/生图）的只有当前会话与提炼后的具象描述；`buildImagePrompt` 明确排除含具体事件的 reason/stateNote
- key 由用户自己填、本地 `shared_preferences` 保存

## License

[MIT](LICENSE)
