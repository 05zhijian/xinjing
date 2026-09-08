import 'avatar.dart';

/// 候选物种池：映射层 prompt 的约束，避免模型自创物种名导致无法复现。
/// 默认动物为主，可含少量精灵/器物（定稿后再核，见 DevDoc §5.2）。
const List<String> speciesPool = [
  '白狐', '雪鸮', '暹罗猫', '灰狼', '猎豹',
  '棕熊', '水牛', '旅鹿', '野马', '海鸟',
  '喜鹊', '水獭', '猫头鹰', '垂耳兔', '绵羊', '萤火虫',
  '精灵', '守山石灵',
];

/// 示例种子：无记忆时让新用户先看到「镜灵」是什么。
/// 展示专用，不写进 avatar.json（只有真实「显化」的结果才落盘）。
final List<AvatarSpec> sampleSpecs = <AvatarSpec>[
  AvatarSpec(
    being: AvatarBeing(
      species: '白狐',
      essence: const ['夜行', '独立', '内敛的创作欲'],
      baseCoat: const ['雪白', '尾尖墨蓝'],
      reason: '深夜最清醒，独自打磨作品时眼睛会亮——不是狼的群居，是白狐的独行与机敏。',
    ),
    scene: AvatarScene(
      setting: '堆满纸稿的深夜书房',
      season: '初秋',
      weather: '窗外下着雨',
      moodPalette: '墨蓝与月白',
      props: const ['摊开的笔记本', '半杯凉茶'],
      pose: '趴在纸堆上，抬眼望向雨窗',
    ),
    stateNote: '示例形象：连续几晚赶稿，尾尖的墨蓝比上周更深了一些。',
  ),
  AvatarSpec(
    being: AvatarBeing(
      species: '水獭',
      essence: const ['好奇', '爱动手', '收集小确幸'],
      baseCoat: const ['栗棕', '腹部暖白'],
      reason: '对喜欢的事会一头扎进去研究很久，还把零碎的小快乐都收进怀里。',
    ),
    scene: AvatarScene(
      setting: '夏夜江边的旧船屋',
      season: '盛夏',
      weather: '刚下过一阵雨',
      moodPalette: '晚霞橙与河水青',
      props: const ['几颗亮石子', '一本翻旧的手艺书'],
      pose: '仰躺在船板上，小爪抱着刚捡来的石子',
    ),
    stateNote: '示例形象：最近爱上了逛旧物市集，宝贝都堆在窝边。',
  ),
  AvatarSpec(
    being: AvatarBeing(
      species: '棕熊',
      essence: const ['沉稳', '给人靠山', '慢热长情'],
      baseCoat: const ['深褐', '胸口一抹蜜金'],
      reason: '情绪稳、习惯扛事，对认定的人和事会守很久——像熊在冬天安静守着洞穴。',
    ),
    scene: AvatarScene(
      setting: '晨雾里的雪松林小屋',
      season: '深冬',
      weather: '初雪刚落',
      moodPalette: '雾灰与蜜金',
      props: const ['窗台上温着的茶', '一封没写完的回信'],
      pose: '坐在小屋门槛上，对着雪地发一会儿呆',
    ),
    stateNote: '示例形象：最近在替别人收尾一件大事，自己也想要个长一点的冬眠。',
  ),
];
