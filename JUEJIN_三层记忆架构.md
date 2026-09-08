# 给 AI 陪伴日记 App 设计三层记忆：工作 / 情景 / 语义

> 一个 Flutter + DeepSeek 的 AI 陪伴日记 App，我把它的记忆做成了三层：**工作记忆（会话窗口）→ 情景记忆（向量化原始记录）→ 语义记忆（抽取画像）**。这篇文章讲为什么分、怎么分、怎么流动，以及一个 DeepSeek 推理模型把回复截断成残缺 JSON 的坑。

---

## 一、为什么 AI 需要"记忆分层"

AI 陪伴类应用绕不开一个问题：**它得记得你**。

最朴素的实现是"全部历史拼进 prompt"。但对话一多，prompt 无限膨胀，成本爆炸、上下文超限、模型被无关历史干扰。于是更近一步的做法是"向量检索 top N 喂模型"——把相关历史挑出来，上下文可控了，但**记忆仍然是一层扁平的库**：只有"原始记录"，没有"认知"。

真正的陪伴应该是"**越来越懂你**"：它记得你上次说过什么（情景），更知道你是个什么样的人（语义）。这就是把记忆分层的动机。

## 二、三层记忆架构

```
用户输入
   │
   ▼
┌───────────────────────────────────────────┐
│            LayeredMemory（编排器）          │
│                                           │
│  L1 工作记忆 WorkingMemory                 │  会话内最近消息 · 易失
│     环形缓冲 maxWindow=20，溢出淘汰最旧      │  不持久化
│                                           │
│  L2 情景记忆 VectorMemory                  │  向量化原始记录 · 持久化
│     类型 chat / diary / insight            │  memories.json
│     余弦相似度 × 时间衰减 topK=5            │
│                                           │
│  L3 语义记忆 UserProfile                   │  抽取画像 · 持久化
│     goals / values / facts                 │  profile.json
│     恒定注入 system，不遗忘                 │
└───────────────────────────────────────────┘
       写入流                   读取流
 对话/日记 → L2 情景层        L3 恒定注入 system
 L2 整合   → L3 语义层        L1 最近 + L2 语义检索合并
```

| 层 | 名字 | 持久化 | 作用 |
|---|---|---|---|
| L1 | 工作记忆 WorkingMemory | 否（易失） | 当前会话上下文，最近 N 条，直接拼进 prompt |
| L2 | 情景记忆 VectorMemory | `memories.json` | 原始记忆（对话/日记/洞察），向量检索 |
| L3 | 语义记忆 UserProfile | `profile.json` | 抽取出的稳定画像，恒定注入，永不遗忘 |

为什么是这三层：

- **工作记忆**：控制上下文长度，避免 prompt 无限膨胀；
- **情景记忆**：语义检索"相关历史"，解决"关键词匹配不到但意思相关"的问题；
- **语义记忆**：把短期经历沉淀为长期认知——**这是"记忆会成长"的核心卖点**，也是和"一层扁平向量库"拉开差距的地方。

## 三、写入流：记忆怎么进来

三层各有写入时机：

```dart
// L1：会话中每轮实时记录，溢出淘汰最旧
void noteTurn(String role, String content) => working.addTurn(role, content);

// L2：对话 / 日记结束后持久化一条原始记录
Future<bool> remember(String text, {String type = 'chat'}) =>
    episodic.add(text, type: type);
```

L1 的环形缓冲是典型的"窗口控制"：

```dart
void addTurn(String role, String content) {
  final t = content.trim();
  if (t.isEmpty) return;
  _items.add(WorkingTurn(role, t));
  if (_items.length > maxWindow) {
    _items.removeRange(0, _items.length - maxWindow); // 淘汰最旧
  }
}
```

## 四、读取流：三层合并喂给模型

`recall(query)` 把三层合并成一个上下文，**各层都注入但都受限**——画像精、检索限 topK、工作限最近条数，总量可控：

```dart
Future<MemoryRecall> recall(String query, {int workingLimit = 12}) async {
  final episodicHits =
      episodic.hasItems ? await episodic.search(query) : const <String>[];
  return MemoryRecall(
    semanticContext: semanticContext,   // L3：画像文本 → system 首段
    episodicHits: episodicHits,         // L2：相关记忆原文 → system【相关记忆】
    working: working.recent(n: workingLimit), // L1：最近轮次 → 对话历史
  );
}
```

## 五、consolidate：记忆整合升华（最值钱的部分）

分层如果只做"写入 + 读取"，那只是把扁平库拆成三份。真正的价值在**流动**——记忆从"原始记录"升华成"长期认知"：

```dart
Future<ConsolidationResult> consolidate(AiService ai, List messages) async {
  // ① 抽取画像 → 合并进 L3 语义层（复用 UserProfile.extractFromConversation）
  final profileUpdated = await semantic.extractFromConversation(ai, messages);
  // ② 把对话压缩成一句 20 字内洞察 → 写回 L2 情景层
  final insight = await _extractInsight(ai, messages);
  if (insight != null) {
    await episodic.add(insight, type: 'insight');
  }
  return ConsolidationResult(profileUpdated: profileUpdated, insight: insight);
}
```

- **画像抽取**：AI 读对话输出 `{goals, values, facts}`，去重合并进语义层。画像恒定注入 system，AI 越来越懂用户；
- **洞察回写**：把"这次聊了什么"压成一句启发，作为 `insight` 类型写进情景层——它是可被后续检索到的"浓缩记忆"，而不是又一堆原始对话。

> 这就是记忆分层最值钱的部分：**记忆从"原始记录"升华到"长期洞察"，而不是一直堆原始对话。**

## 六、关键实现：本地 n-gram 嵌入，不调 embedding API

情景层检索需要向量，但这里刻意没用外部 embedding API，而是本地字符 n-gram 哈希嵌入：

```dart
List<double> localEmbed(String text, {int dim = 256, int maxNgram = 3}) {
  final vec = List<double>.filled(dim, 0);
  final t = text.toLowerCase();
  for (var n = 1; n <= maxNgram; n++) {
    for (var i = 0; i + n <= t.length; i++) {
      final h = _stableHash(t.substring(i, i + n));
      vec[h % dim] += 1.0;
    }
  }
  return vec;
}
```

**为什么敢用哈希而不怕质量差**：demo 量级下它换来的是三件事——**自包含**（无网络依赖）、**不限流**（免费 embedding API 高频 429 的坑直接消失）、**确定性可测**（同一文本永远同一向量，单元测试可断言）。检索端用余弦相似度 × 时间衰减（半衰期 7 天），越久远的记忆权重越低：

```dart
static double timeDecay(int timeMs, {double halfLifeDays = 7}) {
  final days = (DateTime.now().millisecondsSinceEpoch - timeMs) / 86400000.0;
  if (days <= 0) return 1.0;
  return math.pow(0.5, days / halfLifeDays).toDouble();
}
```

## 七、踩坑：DeepSeek 推理模型把 content 截断成残缺 JSON

这是排查最久的一个坑，值得单独讲。

**现象**：consolidate 的画像抽取"静默失败"——不报错，但画像永远是 0 条。`extractFromConversation` 里 `parseJson(raw)` 解析失败被吞掉，主流程照常走。

**排查**：抓原始回复，发现 content 是这种残缺 JSON：

```
{"goals":["
```

再深入：`deepseek-v4-flash` 是**推理模型**，非流式响应里输出 token 会优先被 `reasoning_content` 消耗。诊断脚本实测，某次 300 token 的预算里 **294 个被 reasoning 吃掉**，留给真实 `content` 的只剩几个 token——于是画像 JSON 被拦腰截断，解析必然失败。

**修复**（`complete()` 里加两样东西）：

```dart
body: {
  'model': _model,
  'messages': messages,
  'temperature': 0.3,
  // deepseek-v4-flash 是推理模型：输出 token 会被 reasoning_content
  // 大量消耗，不给足 max_tokens 会让真实 content 截断成残缺 JSON。
  'max_tokens': 2048,
},
timeout: const Duration(seconds: 90),
```

另外给解析失败加了**一次严格重试**兜底（模型偶尔会把 JSON 包进代码块/解释里）：

```dart
if (extracted == null) {
  final retry = await ai.complete([
    ...prompt,
    {'role': 'user', 'content': '直接输出 JSON 对象本身，不要任何解释、代码块或多余文字。'},
  ]);
  extracted = parseJson(retry);
}
```

**经验**：调推理模型时，"设 max_tokens"不是可选项而是必选项——它不设就和没设温度、没设超时一样，会以"静默坏数据"的形式反咬你。这类失败没有异常、没有日志里的红色，只有一个解析函数的 `return null`。

## 八、怎么保证这套架构"能讲、能测"

架构再漂亮，面试和工程上都得能证明。这套代码配了两层测试：

- **37 个单元测试**：`WorkingMemory` 溢出淘汰与顺序、`VectorMemory` 检索排序与时间衰减、`cosineSimilarity`/`localEmbed` 纯函数边界、`UserProfile` 解析去重、`LayeredMemory` 三层合并与 consolidate 回写——全部纯逻辑可断言；
- **集成测试跑真 AI**：`integration_test` 里用轮询（真实流式下 `pumpAndSettle` 等不到）走完整流程——发消息 → 情景层累计 → 生成日记 → consolidate 抽取画像。注意 `testWidgets` 默认 30s 超时不够真实 AI 流式 + 两次非流式调用，需显式放大：

```dart
testWidgets('三层记忆全流程', (tester) async { /* ... */ },
    timeout: const Timeout(Duration(minutes: 5)));
```

## 九、总结与取舍

- **分层解决的是"记忆会成长"**：工作层控长度、情景层找相关、语义层沉淀认知，三者合并可控不失控；
- **本地嵌入是刻意的取舍**：牺牲一点向量质量，换来自包含、不限流、可测试——demo 量级下这笔交易很划算；
- **推理模型的坑要"防截断 + 容错"双管齐下**：给足 max_tokens + 解析失败重试，别让静默失败吞噬数据。

项目是开源的：`github.com/05zhijian/xinjing`（Flutter + Dart，MIT License），完整架构与测试代码都在仓库里，欢迎交流。

---

*如果你也在做 AI 应用里的"记忆"或上下文管理，欢迎在评论区聊聊你的方案。*
