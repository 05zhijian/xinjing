/// 危机兜底（纯 Dart、可单测）：**安全关键路径不交给概率模型**。
///
/// 为什么要有这个文件：评测基线显示，即使手册里写了「必须给求助指引」，
/// 模型在危机情境下仍然只顾追问细节、一句资源都没给（2/2 失败），
/// 而 LLM 评审还给了它满分——所以安全必须在代码层保证，而不是靠 prompt 自觉。
///
/// 策略取舍：**宁可误报，不可漏报**。误报的代价是多给一次关怀与资源
///（无害）；漏报的代价可能是人命。所以识别做得宽，回复做得稳。
library;

/// 危机信号识别结果。
class CrisisSignal {
  final String code; // 'self_harm' | 'violence' | 'harm_others'
  final String label;
  final String matched;
  const CrisisSignal(this.code, this.label, this.matched);
}

final _selfHarm = RegExp(
    r'想死(?!磕)|不想活|活不下去|活着没意思|活着没意义|不如死|一了百了|自杀|轻生|'
    r'结束自己|结束生命|消失掉|如果.*消失|割腕|跳楼|安眠药.*(吃|吞)|'
    r'不在了.*(轻松|好过|更好|好受|解脱)|走了.*(轻松|解脱)');
final _violence = RegExp(
    r'打我|动手打|又动手|家暴|被(他|她|人)打|挨打|威胁我|强迫我|性侵|侵犯我|掐我|踢我');
final _harmOthers = RegExp(r'想杀|弄死|捅死|报复他.*(杀|打)|让他也尝尝');

/// 识别危机信号（可多条）。空列表 = 未命中。
List<CrisisSignal> detectCrisis(String text) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  final out = <CrisisSignal>[];
  void hit(String code, String label, RegExp re) {
    final m = re.firstMatch(t);
    if (m != null) out.add(CrisisSignal(code, label, m.group(0)!));
  }

  hit('self_harm', '自伤/自杀风险', _selfHarm);
  hit('violence', '正在遭受暴力', _violence);
  hit('harm_others', '伤害他人风险', _harmOthers);
  return out;
}

bool needsCrisisGuard(String text) => detectCrisis(text).isNotEmpty;

/// 判定「回复里是否已有求助指引」的线索（保守：宁可判定为缺失，多补一次）。
final RegExp safetyResourceCue =
    RegExp(r'热线|12356|110|120|专业|医生|心理咨询|求助|信任的人|身边的人|家人|朋友|报警');

/// 「明确、无条件」的推荐措辞——危机情境下要的是这个。
final RegExp emphaticCue = RegExp(r'请一定|请务必|务必|请立即|请马上|一定要|立刻|马上');

/// 条件式/犹豫式措辞：危机情境下不该出现（把求助变成「可选」会削弱它的分量）。
final RegExp conditionalOffer =
    RegExp(r'可以考虑|如果你需要|如果需要|如果方便|如果有需要|也许可以|或许可以|如果你想的话');

/// 求助指引是否「足够」：给了资源 + 措辞明确无条件 + 没有条件式框架。
bool hasSufficientSafetyGuidance(String reply) =>
    safetyResourceCue.hasMatch(reply) &&
    emphaticCue.hasMatch(reply) &&
    !conditionalOffer.hasMatch(reply);

/// 危机情境下注入 system 的强制条款（与手册的安全边界一致，但更强硬）。
const String crisisDirective = '\n\n【本轮是危机情境，最高优先】'
    '用户可能正处于自伤、自杀、被暴力或伤害他人的风险中。'
    '不要追问细节、不要分析、不要谈方法、不要用提问代替建议。'
    '必须先表达在意，然后**无条件、明确**地建议求助：用「请一定」「请务必」这样的措辞，'
    '并给出现成资源——心理援助热线 12356（24 小时），紧急情况请立刻打 110／120。'
    '禁止条件式、犹豫式的说法（"如果方便""可以考虑""也许"这类），'
    '也不要把建议放在"如果你需要"的前提下。';

/// 确定性的安全回复：模型失手时的兜底文案（也是缺口时的补充段）。
/// 措辞刻意「无条件 + 明确」，符合 [hasSufficientSafetyGuidance]。
const String crisisSafetyReply = '听到这些，我很在意你现在的安全。你扛着的东西太重，'
    '不该由你一个人扛。请一定告诉现实中能帮到你的人，也请一定拨打心理援助热线 12356'
    '（24 小时）；如果当下有危险，请立刻打 110 或 120。我在这里陪你，但你需要比我更专业的支持。';

/// 保证危机回复一定带「明确无条件」的求助指引：
/// - [required] 为 false 时原样返回；
/// - 已足够（有资源 + 明确 + 无条件的犹豫）则原样返回；
/// - 缺失或只是「有条件地提了一句」则把确定性文案附在末尾
///   （保留模型那句关怀，补上它没做到的那部分）。
String ensureSafetyGuidance(String reply, {required bool required}) {
  final r = reply.trim();
  if (!required) return r;
  if (hasSufficientSafetyGuidance(r)) return r;
  if (r.isEmpty) return crisisSafetyReply;
  return '$r\n\n$crisisSafetyReply';
}
