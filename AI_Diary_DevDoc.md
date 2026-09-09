# 心镜 · AI 陪伴 App — 记忆分层设计文档

> 版本：v1.0（2026-08-20）
> 定位：把现有「单一向量记忆」升级为「三层记忆架构」，让记忆真正可讲、可测、可上简历。

---

## 一、背景与目标

**目标**：补齐三层记忆架构（工作 / 情景 / 语义）+ 记忆流动（写入流 / 读取流 / 整合升华），配套测试与 README，做成一个能上简历的完整项目。

**决策（已确认）**：纯后端架构，不加可视化 UI；暂不写掘金文章，代码优先。

---

## 二、现状分析

改动前代码里的记忆组件（隐式分层，未显式化）：

| 现状组件 | 文件 | 职责 | 缺什么 |
|---|---|---|---|
| `VectorMemory` | `lib/memory.dart` | 向量化存储全部对话/日记，余弦 × 时间衰减检索 topK | 是「一层扁平库」，没有分层 |
| `UserProfile` | `lib/profile.dart` | goals / values / facts 画像，每轮注入 system，AI 抽取合并 | 已经是「语义记忆层」，但没纳入统一编排 |
| 会话内最近 12 条消息 | `lib/chat_page.dart` | `_messages.sublist` 拼进 prompt | 是「工作记忆层」，但逻辑散在 UI 层 |
| `DiaryStore` | `lib/diary_store.dart` | 日记归档为 markdown | 归档层，本次不动 |

**关键缺口**：
1. 没有显式的「分层抽象」——面试没法一句话讲清架构
2. 没有「记忆流动」——旧记忆不会压缩成洞察、升华进语义层
3. 读取是单层检索（只查向量库），不是「语义恒定 + 工作最近 + 情景语义」的多级合并

---

## 三、目标架构：三层记忆

```
用户输入
   │
   ▼
┌────────────────────────────────────────────────────┐
│            LayeredMemory（编排器，新）              │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ L1 工作记忆  WorkingMemory（新）              │  │  会话窗口 · 易失
│  │    最近 N 条消息（环形缓冲，maxWindow=20）     │  │  不持久化
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │ L2 情景记忆  EpisodicMemory（= 现有 VectorMemory）│ 向量化原始记忆 · 持久化
│  │    类型 chat / diary / insight                │  │  memories.json
│  │    余弦相似度 × 时间衰减 topK                  │  │
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │ L3 语义记忆  SemanticMemory（= 现有 UserProfile）│ 抽取画像 · 持久化
│  │    goals / values / facts                     │  │  profile.json
│  │    恒定注入 system，不遗忘                     │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
       ▲ 写入流                            ▼ 读取流
  对话/日记 → L2 情景层                 L3 恒定注入
  L2 整合 → L3 语义层                  L1 最近 + L2 语义检索合并
```

### 各层职责

| 层 | 名字 | 持久化 | 作用 |
|---|---|---|---|
| L1 | 工作记忆 WorkingMemory | 否（易失） | 当前会话上下文，最近 N 条，直接拼进 prompt |
| L2 | 情景记忆 EpisodicMemory | `memories.json` | 原始记忆（对话/日记/洞察），向量检索，语义相关 + 近期优先 |
| L3 | 语义记忆 SemanticMemory | `profile.json` | 抽取出的稳定画像（目标/在意/事实），恒定注入，永不遗忘 |

### 为什么是这三层

- **工作记忆**：控制上下文长度，避免 prompt 无限膨胀
- **情景记忆**：语义检索「相关历史」，解决「关键词匹配不到但意思相关」的问题
- **语义记忆**：把短期经历沉淀为长期认知，让 AI 越来越懂用户——这是「记忆会成长」的核心卖点

---

## 四、记忆写入流

1. **每轮对话结束**（chat_page `onDone`）：
   - 用户问句 + AI 回复 → `LayeredMemory.remember(text, type: chat)` → 向量化写入 **L2 情景层**
2. **生成日记后**（chat_page `_generateDiary` onDone）：
   - 日记正文 → `remember(content, type: diary)` → 写入 **L2**
   - 触发 `consolidate()` → 见第六节「整合升华」
3. **工作记忆**：会话内自动累积，超 `maxWindow` 淘汰最旧（UI 层 `_messages` 已有限制，`WorkingMemory` 作为统一封装）

---

## 五、记忆读取流

`LayeredMemory.recall(query)` 返回三层合并的上下文：

| 来源 | 内容 | 注入方式 | 条数控制 |
|---|---|---|---|
| L3 语义 | `profile.buildSystemContext()` | system 首段 | 全部（画像本身精简） |
| L2 情景 | `query` 向量化 → 余弦 × 时间衰减 → topK | system `【相关记忆】` | topK=5，minSimilarity=0.2 |
| L1 工作 | 最近 N 条消息 | user/assistant 历史 | 最近 12 条 |

**设计取舍**：三层都注入但不失控——画像精、检索限 topK、工作限最近条数，上下文总量可控。

---

## 六、记忆整合升华 consolidate()

**触发时机**：每次生成日记后（与现有 `profile.extractFromConversation` 时机一致）。

**步骤**：
1. 取本次会话的对话历史（`useAll` 全量）
2. **抽取**：AI 输出 JSON `{goals, values, facts}` → 解析 → 去重合并 → 写入 **L3 语义层**（复用 `UserProfile.extractFromConversation` + `merge`）
3. **洞察回写**：让 AI 把本次对话压缩成 1 条 20 字内洞察 → 写入 **L2 情景层**（`type: insight`），补齐现有代码从没写过的 `insight` 类型

**意义**：这就是「记忆分层」最值钱的部分——记忆从「原始记录」**升华**为「长期洞察」，而不是一直堆原始对话。回答面试题的落点。

---

## 七、代码改动清单

| 文件 | 动作 | 说明 |
|---|---|---|
| `lib/working_memory.dart` | 新增 | `WorkingMemory`：环形缓冲 + 窗口淘汰 + `recent()` |
| `lib/layered_memory.dart` | 新增 | `LayeredMemory`：组合三层 + `remember` / `recall` / `consolidate` / `stats` |
| `lib/chat_page.dart` | 改 | 用 `_layered.recall()` 替代 `_memory.search()`；日记后调 `_layered.consolidate()` |
| `lib/main.dart` | 改 | 装配 `LayeredMemory`，注入 ChatPage |
| `lib/profile.dart` | 微调 | 复用 `extractFromConversation` 于 consolidate，无需大改 |
| `test/working_memory_test.dart` | 新增 | 窗口淘汰、recent 顺序 |
| `test/layered_memory_test.dart` | 新增 | recall 三层合并、consolidate 去重/洞察回写 |
| `README.md` | 改 | 架构图 + 设计取舍 + 数据流，定位简历项目 |
| `AI_Diary_DevDoc.md` | 新增 | 本文档 |

**兼容性**：不改 `memories.json` / `profile.json` 存储格式，现有数据可无缝继续用；现有 5 个测试文件保持全绿。

---

## 八、测试计划

1. `WorkingMemory`：溢出淘汰、`recent()` 顺序、空窗口兜底
2. `LayeredMemory.recall`：三层来源正确合并、条数上限、空记忆兜底
3. `consolidate`：抽取 JSON 解析、去重合并进语义层、洞察写回情景层
4. 回归：现有 `memory_test` / `diary_store_test` / `practice_test` / `profile_test` / `widget_test` 全绿

### 集成测试（真机/模拟器）

`integration_test/app_test.dart` 用 `pumpUntil` 轮询（真实 AI 流式，`pumpAndSettle` 等不到），跑三层记忆全流程：
发消息 → 情景层累计 → 生成日记 → consolidate 抽取画像。

关键依赖：
- **嵌入本地化**：情景层向量由 `localEmbed`（字符 n-gram 哈希）本地生成，不依赖外部嵌入 API——无限流、确定性、可单测。
- **网络鲁棒性**：`AiService` 对 429 / 5xx / 网络超时做指数退避重试（`maxAttempts=3`，尊重 `Retry-After`，封顶 8s）；流式 `chat` 只在发送阶段重试，且流式读取有 45s 无事件超时，避免 SSE 卡死。

踩坑记录：
- Android 集成测试里第二次 `tester.enterText` 可能因输入通道未重连而静默失败 → 改用 `typeChat` 直接设 controller 文本。
- 智谱 embedding 免费额度在模拟器高频调用下随机 429 → 换 DeepSeek（不限流）+ 本地嵌入。
- `testWidgets` 默认 30s 超时不够真实 AI 流式 + consolidate 两次非流式调用 → 全流程测试加 `timeout: Timeout(minutes: 5)`。
- **DeepSeek 推理模型截断坑**：`deepseek-v4-flash` 是推理模型，非流式响应把输出 token 优先给 `reasoning_content`；不设 `max_tokens` 时真实 `content`（如画像 JSON）可能被截断成 `{"goals":["` 这样的残缺 JSON，`parseJson` 静默失败 → 画像 0 条。修复：`complete()` 加 `max_tokens=2048` + 90s 超时，`extractFromConversation` 解析失败时用更严格 prompt 重试一次。

验证命令：`cd ai_diary_demo && flutter analyze && flutter test`
集成测试：`flutter test integration_test/app_test.dart -d emulator-5554 --dart-define=DEEPSEEK_API_KEY=你的key`

---

## 九、画像进化（L3 自我修正，2026-09-09 增补）

**问题**：画像原本「只增不减」（merge 只去重），旧认知与新现实永远叠加，没有时间维度，谈不上「越用越懂」。

**解法**：把画像从「字符串清单」升级成「带元数据的条目 + 三个机制」，JSON 兼容旧数组格式：

```
ProfileItem = 文本 + dim(goals/values/facts)
            + strength(被印证次数) + lastSeen(最近印证) + active(是否仍成立)
```

1. **修订型抽取**：每次 consolidate 不再只 append——同维同文命中 → 刷新 `lastSeen` 并 `strength+1`；否则新增。每篇日记都在「强化或新增」，从不稀释。
2. **画像审查 review**：每新增 7 篇日记触发一次（`kProfileDiaryReviewEvery`，可构造参数调）。让模型对照最近 10 条日记/洞察，输出 `{"expire":["原文"],"note":"一句话变化"}`；把过时条目 `active=false`（**只降级不真删**，留历史与强度），note 写进 `changeLog`（时间轴 = 它怎么修正自己的证据）。
3. **人可纠错**：注入 system 只取**活跃**条目；「我的」页每条可点「放下」（降级）、手动补充 upsert。「放下」是 P1 里用户最直接的收敛手段。

**写入流**：`LayeredMemory.consolidate()` → 抽取吸收 + 洞察回写 + `addDiary()` → 阈值到则 `_review()`。

**不做的**：不自动按时间衰减过期（避免误杀仍成立但久未提及的长期画像）——过期只由 review 依据证据判定。

**测试**：64 全绿，覆盖旧格式兼容 / strength 刷新 / deactivate 降级保留 / review 触发与降级 / 注入只含活跃。模型回复容忍前后缀，解析失败严格指令重试一次。
