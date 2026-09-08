# 心镜 · 具象化身「镜灵」设计文档

> 版本：v1.1（2026-09-09）
> 定位：把现有「三层记忆 → 文本画像（profile.json）」再进一步，**用一张可演化的具象画面，把 AI 对你的了解显化出来**。它是「显化的我」产品名最直接的落地，也是三层记忆架构的可视化封面。
> 性质：设计稿。概念已冻结；§十二为已拍板决定。
> 进度：**M0+M1+M2 已实现**（58 测试全绿 + 真实智谱 key 探针出图成功）。M1 离线跑通「显化→演化→时间轴」、占位画布；M2 落地智谱单 key：`AiService` provider 可切换（DeepSeek/智谱）、`ZhipuImageGen`（GLM-4-Flash 文本 + CogView-3-Flash 生图）、PNG 落盘 `avatar/imgs/`、化身页真图展示。
> UI（同日）：壳层共享 AppBar——全局右上角 ⚙️ 打开 `ai_settings_page.dart`（服务商 + key 一处配置，随服务商持久化），聊天 ✨ 生成日记 / 日记刷新经 GlobalKey；「我的」瘦身为镜灵卡 + 画像。Android 应用名已修为 UTF-8「心镜」，release 不打入 key。

---

## 一、背景与目标

**目标**：用户每次生成，得到一张「镜灵」——由三层记忆推导出的**具象存在（默认是动物，可以是精灵/器物）**。物种固定、细节随状态演化，每次生成都附一句人话解释「为什么它现在长这样」。

**为什么是动物/具象，而不是人脸**
1. 人格推不出长相——逼真人脸=伪造一张脸，既误导又永远对不上。
2. 具象隐喻天然表达性格（物种=身份、毛色/环境=状态），不生造虚假「真容」。
3. 奇幻生物/动物是生图模型质感最强的区，**惊艳**比画人脸更容易达到。
4. 与「心镜」同构：镜中照见的是「灵」，不是「相」。

**决策（已确认）**
- 形态：具象化身（动物等），**不做逼真人脸**。
- 第一版优先级：**先出图惊艳**。出图美，是这一版唯一的外在 KPI。
- 引擎灵魂是「映射层」（免费、确定性、可测）；出图层是可插拔的付费最后一跳。

---

## 二、现状分析（本次接入点）

现有三层记忆已把「理解用户」跑通，本次不重造，只消费其结果：

| 现有组件 | 文件 | 本次怎么用 |
|---|---|---|
| `UserProfile`（L3 语义画像 goals/values/facts） | `lib/profile.dart`，持久化 `profile.json` | **物种身份**的依据 |
| `LayeredMemory.consolidate()`（洞察回写 L2） | `lib/layered_memory.dart` | **状态演化**的依据 |
| `VectorMemory`（type: diary/insight/chat + 时间戳） | `lib/memory.dart` | 取「最近」记忆判断状态漂移 |
| `AiService.complete()`（非流式 + 重试 + max_tokens=2048） | `lib/ai_service.dart` | 复用于映射层的 LLM 调用 |
| 数据目录 `documents/xianhuadewo/` | `lib/main.dart:_initStorage` | 新增文件放这里 |
| Key 存 `shared_preferences` | `lib/settings_page.dart` | 新增独立的生图 key |

**关键缺口**：文本画像看得见字、看不见「我」。缺一层**把画像翻译成画面**的管线 + 一个**让人想生成、想对比**的界面。

---

## 三、产品定义：身份固定 × 状态演化

镜灵 = **不变的你（Being）** × **会变的你（Scene）**，两个概念必须从第一天就分离。

| | Being（身份） | Scene（状态） |
|---|---|---|
| 是什么 | 你是哪种存在、底色 | 此刻的环境、光线、心情、发生的事 |
| 决定谁 | 长期画像（goals/values/facts） | 近期记忆（最近日记/洞察/对话） |
| 变化频率 | 几乎不变，锁定 | 每次生成可漂移 |
| 例子 | 冬夜白狐、尾尖墨蓝 | 雨夜、书房、纸堆、台灯、金丝围巾 |

**一致性是魔法的前提**：同一只狐，状态不同，才谈得上「演化」；物种天天变，就只是「抽卡」。所以 Being 一旦生成就**锁死**（除非用户主动「重置化身」）。

---

## 四、总体架构：两段管线

```
三层记忆（已有）
 profile.json ── L3 语义画像（长期身份） ──┐
 memories.json ─ L2 最近 diary/insight（近期状态） ──┤
 今日对话 / 工作层 ────────────────────────────┘
                    │
                    ▼
【映射层 ①】LLM：画像/记忆 → 具象描述 AvatarSpec（严格 JSON）
    免费 · 确定性校验 · 可单测 ←——产品灵魂，唯一要写好的 prompt
                    │  只把 AvatarSpec 文本传出去（隐私红线，见 §七）
                    ▼
【出图层 ②】ImageGen 抽象 → 厂商生图 → PNG 存档
    付费 · 可插拔 · 厂商待选型（M2 试金石定）
                    │
                    ▼
avatar.json + 图片 + avatar_history ──► 化身页 / 演化时间轴
```

写入/触发流：
1. 用户在化身页点「显化」；
2. 组装上下文：L3 画像全文 + 最近 N 条 L2（diary/insight，按时间取）+ 最近工作层对话摘要；
3. 调映射层 LLM → 校验 → 若 Being 为空则定身份（锁定），否则只演化 Scene + 写「状态变化注释」；
4. 调出图层 → PNG 存 `avatar/imgs/{ts}.png` → 追加 `avatar_history` 一条 → 界面展示 + 一句 why。

---

## 五、映射层（灵魂）：文本记忆 → AvatarSpec

### 5.1 输出 Schema（严格 JSON，字段全部枚举约束）

```json
{
  "being": {
    "species": "白狐",
    "essence": ["夜行", "独立", "内敛的创作欲"],
    "baseCoat": ["雪白", "尾尖墨蓝"],
    "reason": "你夜里最清醒、独自打磨作品时眼睛会亮——不是狼的群居，不是猫的慵懒，是白狐的独行与机敏。"
  },
  "scene": {
    "setting": "深夜书房",
    "season": "初秋",
    "weather": "雨",
    "moodPalette": "墨蓝 / 月白",
    "props": ["摊开的笔记本", "金色丝线围巾"],
    "pose": "趴在纸堆上抬眼望向窗外"
  },
  "stateNote": "离上次显化：你在为 offer 准备 → 围上金线；熬夜上升 → 窗外起雨"
}
```

- `being`：**空则让模型定身份**；已存在则要求**原样逐字返回**（校验层做「身份未漂移」断言）。
- `scene`：每次自由，但要贴最近记忆的具体事/情绪，避免只给空泛的「安静」。
- `stateNote`：一句给用户看的演化说明（≤40 字），是「为什么变了」的人话。
- 严格 JSON + 失败重试：完全复用 `profile.extractFromConversation` 的套路（`profile.dart:91` 的兜底 prompt、`parseJson` 容忍前后缀）；继续踩已知坑：DeepSeek 推理模型要 `max_tokens=2048`，否则 content 被 reasoning 挤断成残缺 JSON。

### 5.2 物种池（示例，完整池 M0 待精细打磨）

| 画像特征线索 | 候选物种（附性格理由） |
|---|---|
| 夜猫 · 独立 · 深度思考 | 白狐、雪鸮、暹罗猫 |
| 稳定 · 支撑别人 · 慢热 | 棕熊、水牛、老槐树（器物例外） |
| 自由 · 浪漫 · 怕被框住 | 旅行的鹿、海鸟、野马 |
| 好奇 · 话痨 · 收集狂 | 喜鹊、水獭、猫头鹰（藏书） |
| 温和 · 敏感 · 照顾型 | 垂耳兔、绵羊、萤火虫 |
| 干脆 · 冲 · 不服输 | 猎豹、狼（领队向） |

要求：映射 prompt 里让模型**从池中选**（而不是自创物种名），并在 essence 里写明区别理由，避免脸谱化（白狐 ≠ 网红感，要靠场景和底色给出独特性）。

### 5.3 身份锁定 & 状态漂移规则

- Being 为空（首次）→ 生成并锁定。
- 之后每次：Being 字段走**校验**，与上次不一致 → 丢弃本次生成、提示「身份冲突」（正常不该发生；发生=prompt 或解析 bug，暴露给日志）。
- 物种「重选」只走用户手动重置（§九），绝不由单次对话触发——否则上一段对话情绪一激动镜灵就换物种，可信度崩。
- Scene 漂移来源 = L2 最近 diary/insight + 最近对话。**变化要有据**：没有新记忆时生成的 scene 应与上次接近，避免纯随机抖动画。

### 5.4 与「惊艳」的关系

图片上限=画质由模型给；**画面是否有意思**由 scene 质量给。映射层打磨的是后者：prompt 里禁止出现「萌」「帅气」这类讨好词，改用具体的氛围词（光线、材质、天气、道具），让同一只狐在不同心境下真的不同。

---

## 六、出图层（可插拔，付费最后跳）

```dart
/// 生图抽象：UI 只依赖这个接口，厂商实现可换、测试用 Fake。
abstract class ImageGen {
  bool get hasKey;
  void setKey(String key);
  Future<Uint8List?> generate({
    required String prompt,          // 由 AvatarSpec 拼成的一句画面描述
    String negative = '',            // 负面词（模糊、畸形、文字等）
    int? seed,                       // 同一 scene 重试想保持一致时传入
  });
}
```

- 厂商候选：**硅基流动（托管 FLUX）** / **智谱 CogView** / **火山即梦 Seedream**。三家具体请求体以 **M2 试金石**实际响应为准（本稿不臆造接口字段）。
- Key：独立于 DeepSeek，存 `shared_preferences['image_api_key']`，UI 在「我的」页分开配。Settings 里同时记 `image_provider`（默认值 M2 定）。
- 超时放宽到 120s（生图比文本慢），沿用 AiService 的 429/5xx 退避重试思路。
- 结果：PNG 字节落盘 `documents/xianhuadewo/avatar/imgs/{ts}.png`，内存不留原图。

### ⚠️ 隐私红线（必须写死在 prompt 拼装层）

**发给生图平台的只能是 AvatarSpec 转成的画面描述，绝不含任何原始记忆、姓名、真实地点、日记原文。** 拼装层统一出口、日志对 prompt 做脱敏。这条写进 review 检查项。

---

## 七、数据文件与存储（向后兼容）

```
documents/xianhuadewo/
├─ profile.json / memories.json        # 已有，不改格式
├─ avatar.json                         # 新增：身份 + 最近一次 scene + 演化计数
└─ avatar/imgs/{ts}.png                # 新增：历史图（ts=epoch ms）
```

`avatar.json` 结构：

```json
{
  "being": { "...": "身份，生成一次即锁定" },
  "latest": { "scene": {...}, "stateNote": "...", "ts": 0, "img": "avatar/imgs/1725xxx.png" },
  "history": [ { "ts": 0, "scene": {...}, "stateNote": "...", "img": "..." } ],
  "genCount": 3,
  "resetCount": 0
}
```

`history` 全量存会随使用增长——demo 量级（每周几次，一年几百条）完全可承受，先不做滚动裁剪；真到千级再加「只看变化大的」压缩逻辑。设计上给 `AvatarSpec` 加 `equals`（scene 无变化则不重复落盘/不出新图），控制无谓的花钱。

---

## 八、UI 草案与入口（已确认）

已拍板：**并入「我的」页顶部 · 手动「显化」为主 · 示例种子可预览**（不新增 Tab、不加自动红点）。

- 「我的」页顶部插一张**「当前镜灵」英雄卡**：图 + 一句 stateNote/reason + 「显化/刷新」按钮；点击进全屏**化身页**。
- **化身页**：当前大图 + 演化时间轴（历史缩略横滑，点开看当次 scene 与 stateNote）+ 动作：显化 / 重置身份（确认弹窗）。
- 首次使用记忆为空：化身页给「先用示例画像预览」入口（M0 种子直接喂映射层），让新用户第一眼就看到完整效果——**这是「惊艳第一版」能成立的关键**。

---

## 九、代码改动清单

| 文件 | 动作 | 说明 |
|---|---|---|
| `lib/avatar.dart` | 新增 | `AvatarSpec`（含 `equals`/`toSpecJson`）+ 解析/枚举校验/身份漂移断言 |
| `lib/avatar_renderer.dart` | 新增 | 组装上下文 → 映射层 prompt → 校验 → 拼图 prompt；把 LLM 调用收敛到构造注入的 `AiService`（单测用 Fake） |
| `lib/image_service.dart` | M2 新增 | `ImageGen` 抽象 + 厂商 HTTP 实现 + PNG 落盘（接口形状 M2 试金石定，不臆造） |
| `lib/avatar_store.dart` | 新增 | `avatar.json` 读/写、历史追加（仿 `profile.dart` attach/load/save） |
| `lib/avatar_page.dart` | 新增 | 「我的」页顶部英雄卡 `AvatarCard` + 全屏化身页 + 时间轴 |
| `lib/main.dart` | 改 | 装配 `AvatarStore`，注入「我的」页（卡在 SettingsPage 顶部） |
| `lib/settings_page.dart` | 改(M1) | 「我的」页顶部插 `AvatarCard` 并跳转化身页；生图 key/provider 配置 → M2 |
| `lib/chat_page.dart` | 不改 | 已拍板：手动显化，不加自动红点 |
| `test/avatar_test.dart` | 新增 | 解析、枚举校验、身份漂移断言、无变化不落盘 |
| `test/avatar_renderer_test.dart` | 新增 | 用 Fake AiService 断言：prompt 拼装、隐私脱敏、首次定身份/后续仅 scene |
| `test/image_service_test.dart` | M2 新增 | Fake 厂商响应 → 字节/落盘/失败兜底 |
| `README.md` | 改 | 一句话新卖点 + 架构尾段（README 现为乱码，顺手重写，见 §十一） |
| `XINJING_Avatar_DevDoc.md` | 新增 | 本文档 |

**兼容性**：不动 `profile.json` / `memories.json` 结构；新增文件缺失时静默兜底（沿用各 store 现有「坏了就当空」习惯）。新依赖：**无**（http 已有；生图走 HTTP 拿字节）。

---

## 十、测试计划

1. `AvatarSpec`：合法/非法 JSON、枚举越界钳制、being 漂移→断言失败、`equals` 判定无变化。
2. `AvatarRenderer`（Fake AiService）：
   - 首次生成 → being 被写入；再次生成 → being 逐字保留；
   - 隐私：原始记忆关键词**不得**出现在发给 ImageGen 的 prompt（用敏感词断言）；
   - 无新记忆时 scene 贴近上次（抖动小）。
3. `ImageGen`：Fake 响应 200/429/超时 → 字节/重试/空兜底；落盘路径正确。
4. `AvatarStore`：读写往返、history 追加、文件损坏兜底。
5. 回归：现有 37 个测试保持全绿；`flutter analyze` 零告警。

### 集成测试（真机/模拟器，可选跑）

接真实 DeepSeek + 真实生图 key 全流程一次：聊两句 → 显化 → 出图落盘 → history +1。沿用 `pumpUntil` 轮询，超时放宽（生图 120s）。

---

## 十一、里程碑

| 里程碑 | 内容 | 出口标准 | 需什么 |
|---|---|---|---|
| **M0** | 造 2~3 条**示例画像种子** + 物种池精修 + AvatarSpec schema 定稿 | 离线可 review，喂种子能出像样的 scene | 无 |
| **M1** ✅ | 映射层 + store + 化身页 UI + 占位画布 + 示例种子预览；`ImageGen` 抽象推迟到 M2 | 无生图 key 也能演示「显化→演化→时间轴」 | 无 |
| **M2** ✅ | 已选**智谱单 key**：`AiService` provider 抽象（DeepSeek 默认可切）、`ZhipuImageGen`、PNG 落盘 + 化身页真图展示 | 真实接口探针出图 168KB；57 测试全绿 | 智谱 key（用户已配） |
| **M3** | 演化时间轴打磨、重置身份、README 重写（现为乱码）、简历措辞 | 完整可讲可上简历 | — |

**顺序理由**：M1 的 Mock 让「惊艳」的交互先成立、且不花钱；M2 只在确认画质方向后动手，避免一开始就锁死厂商。

---

## 十二、已拍板的决定（2026-09-08）

1. **入口**：并入「我的」页顶部英雄卡，不新增 Tab。
2. **触发**：手动「显化」为主；不加自动提示红点。
3. **首次体验**：全新用户可用「示例画像预览」先出图演示。
4. 工作名 **「镜灵」**；物种池默认以动物为主、可含少量精灵/器物（M0 定池时核）。此条仍可改。
5. **对外分发 = 一人一 Key（新硬需求）**：别人拿到 APK，只需填**一个** key 就能用全部功能（聊天/日记/映射/出图）。落地：M2 把文本侧写死的 DeepSeek 升级为可换 provider，并按「单 key 全通」筛厂商——候选：智谱（GLM 对话 + CogView 生图）、硅基流动（DeepSeek + FLUX）。记忆与 key 全程留在用户自己设备，无需后端。参见「要不要后端」讨论记录。

---

## 十三、风险与已知坑（先立 flag）

- **DeepSeek 推理模型截断**：复用 `complete()` 的 `max_tokens=2048` + 90s + 解析失败重试，新映射层同样适用（已验证的套路，别在别处重写一遍）。
- **身份漂移**：being 校验不过宁可失败重来，也别让狐变猫。
- **生图一致性**：同一 scene 重试传 seed；厂商若无 seed 则接受轻微差异，靠 scene 显著变化掩盖。
- **审核/内容策略**：动物温和向，avoid 血腥/恐怖；物种池与 prompt 天然规避敏感。
- **云上生成 ≠ 本地数据**：只有 AvatarSpec 文本上云，原始记忆永不出本地（§六红线，Review 必查）。
- README.md 现为 GBK 乱码（`蹇冮暅`），M3 顺手以 UTF-8 重写。
- **真实接口记录（2026-09-09 已探通）**：智谱 `chat/completions` 走 OpenAI 兼容（model `glm-4-flash`，返回 `choices[0].message.content`）；`images/generations`（model `cogview-3-flash`）约 11s 返回 `data[0].url`（带签名下载地址，再 GET 取 PNG）。免费/低价档生成图可能带 `watermark`（见 url 文件名），介意需看账号档位。
