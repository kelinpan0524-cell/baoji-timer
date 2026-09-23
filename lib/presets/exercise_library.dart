import '../models/models.dart';


/// 内置动作库：覆盖健身房（杠铃/器械）、居家（哑铃/弹力带/自重）、功能性训练。
/// equipment: gym=健身房 / home=居家 / both=皆可
/// 供：动作库浏览页、编辑器联想、AI 拆解提示词、计划模板。
const kExerciseLibrary = <ExerciseMeta>[
  // ============ 胸（健身房） ============
  ExerciseMeta('杠铃卧推', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'gym'),
  ExerciseMeta('上斜杠铃卧推', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'gym'),
  ExerciseMeta('上斜哑铃卧推', MuscleGroups(main: '胸', secondary: ['肩']), true, 'both'),
  ExerciseMeta('哑铃卧推', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'both'),
  ExerciseMeta('坐姿夹胸（蝴蝶机）', MuscleGroups(main: '胸', secondary: []), false, 'gym'),
  ExerciseMeta('绳索夹胸', MuscleGroups(main: '胸', secondary: []), false, 'gym'),
  ExerciseMeta('双杠臂屈伸（挺胸）', MuscleGroups(main: '胸', secondary: ['手臂']), true, 'both'),
  // ============ 胸（居家） ============
  ExerciseMeta('俯卧撑', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'home'),
  ExerciseMeta('上斜俯卧撑', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'home'),
  ExerciseMeta('下斜俯卧撑（脚垫高）', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'home'),
  ExerciseMeta('上斜杠铃卧推（轻）', MuscleGroups(main: '胸', secondary: ['肩']), true, 'gym'),
  ExerciseMeta('哑铃飞鸟', MuscleGroups(main: '胸', secondary: []), false, 'both'),
  ExerciseMeta('弹力带夹胸', MuscleGroups(main: '胸', secondary: []), false, 'home'),

  // ============ 背（健身房） ============
  ExerciseMeta('引体向上', MuscleGroups(main: '背', secondary: ['手臂']), true, 'both'),
  ExerciseMeta('负重引体向上', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym'),
  ExerciseMeta('高位下拉', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym'),
  ExerciseMeta('杠铃划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym'),
  ExerciseMeta('坐姿划船', MuscleGroups(main: '背', secondary: ['手臂']), false, 'gym'),
  ExerciseMeta('杠铃硬拉', MuscleGroups(main: '背', secondary: ['腿', '核心']), true, 'gym'),
  ExerciseMeta('直臂下压', MuscleGroups(main: '背', secondary: []), false, 'gym'),
  ExerciseMeta('T杠划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym'),
  // ============ 背（居家） ============
  ExerciseMeta('哑铃单臂划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'both'),
  ExerciseMeta('弹力带下拉', MuscleGroups(main: '背', secondary: ['手臂']), true, 'home'),
  ExerciseMeta('弹力带坐姿划船', MuscleGroups(main: '背', secondary: ['手臂']), false, 'home'),
  ExerciseMeta('超人式', MuscleGroups(main: '背', secondary: ['核心']), false, 'home'),
  ExerciseMeta('反向雪天使', MuscleGroups(main: '背', secondary: ['肩']), false, 'home'),

  // ============ 肩（健身房） ============
  ExerciseMeta('站姿推举', MuscleGroups(main: '肩', secondary: ['手臂', '核心']), true, 'gym'),
  ExerciseMeta('坐姿哑铃推举', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'both'),
  ExerciseMeta('史密斯机推肩', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'gym'),
  ExerciseMeta('哑铃侧平举', MuscleGroups(main: '肩', secondary: []), false, 'both'),
  ExerciseMeta('俯身飞鸟（后束）', MuscleGroups(main: '肩', secondary: ['背']), false, 'both'),
  ExerciseMeta('面拉', MuscleGroups(main: '肩', secondary: ['背']), false, 'gym'),
  ExerciseMeta('哑铃前平举', MuscleGroups(main: '肩', secondary: []), false, 'both'),
  ExerciseMeta('杠铃耸肩', MuscleGroups(main: '肩', secondary: []), false, 'gym'),
  // ============ 肩（居家） ============
  ExerciseMeta('弹力带侧平举', MuscleGroups(main: '肩', secondary: []), false, 'home'),
  ExerciseMeta('派克俯卧撑', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'home'),
  ExerciseMeta('弹力带面拉', MuscleGroups(main: '肩', secondary: ['背']), false, 'home'),

  // ============ 手臂 ============
  ExerciseMeta('杠铃弯举', MuscleGroups(main: '手臂', secondary: []), false, 'gym'),
  ExerciseMeta('哑铃锤式弯举', MuscleGroups(main: '手臂', secondary: []), false, 'both'),
  ExerciseMeta('哑铃弯举', MuscleGroups(main: '手臂', secondary: []), false, 'both'),
  ExerciseMeta('绳索下压', MuscleGroups(main: '手臂', secondary: []), false, 'gym'),
  ExerciseMeta('哑铃颈后臂屈伸', MuscleGroups(main: '手臂', secondary: []), false, 'both'),
  ExerciseMeta('窄距卧推', MuscleGroups(main: '手臂', secondary: ['胸']), true, 'gym'),
  ExerciseMeta('弹力带弯举', MuscleGroups(main: '手臂', secondary: []), false, 'home'),
  ExerciseMeta('凳上臂屈伸', MuscleGroups(main: '手臂', secondary: []), false, 'home'),
  ExerciseMeta('双杠臂屈伸', MuscleGroups(main: '手臂', secondary: ['胸']), true, 'both'),

  // ============ 腿（健身房） ============
  ExerciseMeta('杠铃深蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym'),
  ExerciseMeta('腿举（倒蹬机）', MuscleGroups(main: '腿', secondary: []), true, 'gym'),
  ExerciseMeta('保加利亚分腿蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both'),
  ExerciseMeta('哈克深蹲', MuscleGroups(main: '腿', secondary: []), true, 'gym'),
  ExerciseMeta('罗马尼亚硬拉', MuscleGroups(main: '腿', secondary: ['背', '核心']), true, 'gym'),
  ExerciseMeta('哑铃罗马尼亚硬拉', MuscleGroups(main: '腿', secondary: ['背']), true, 'both'),
  ExerciseMeta('腿屈伸（股四头）', MuscleGroups(main: '腿', secondary: []), false, 'gym'),
  ExerciseMeta('腿弯举（腘绳肌）', MuscleGroups(main: '腿', secondary: []), false, 'gym'),
  ExerciseMeta('站姿提踵', MuscleGroups(main: '腿', secondary: []), false, 'both'),
  ExerciseMeta('杠铃臀桥', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym'),
  // ============ 腿（居家） ============
  ExerciseMeta('徒手深蹲', MuscleGroups(main: '腿', secondary: []), true, 'home'),
  ExerciseMeta('哑铃高脚杯深蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both'),
  ExerciseMeta('箭步蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'home'),
  ExerciseMeta('臀桥', MuscleGroups(main: '腿', secondary: ['核心']), false, 'home'),
  ExerciseMeta('单腿臀桥', MuscleGroups(main: '腿', secondary: ['核心']), false, 'home'),
  ExerciseMeta('靠墙静蹲', MuscleGroups(main: '腿', secondary: []), false, 'home'),

  // ============ 核心 ============
  ExerciseMeta('平板支撑', MuscleGroups(main: '核心', secondary: []), false, 'home'),
  ExerciseMeta('侧平板支撑', MuscleGroups(main: '核心', secondary: []), false, 'home'),
  ExerciseMeta('卷腹', MuscleGroups(main: '核心', secondary: []), false, 'home'),
  ExerciseMeta('悬垂举腿', MuscleGroups(main: '核心', secondary: ['手臂']), false, 'gym'),
  ExerciseMeta('俄罗斯转体', MuscleGroups(main: '核心', secondary: []), false, 'home'),
  ExerciseMeta('健腹轮', MuscleGroups(main: '核心', secondary: ['手臂']), false, 'both'),

  // ============ 功能性训练 ============
  ExerciseMeta('壶铃摆荡', MuscleGroups(main: '腿', secondary: ['背', '核心']), true, 'both'),
  ExerciseMeta('哑铃农夫行走', MuscleGroups(main: '核心', secondary: ['手臂', '肩']), true, 'both'),
  ExerciseMeta('箱跳', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym'),
  ExerciseMeta('深蹲跳', MuscleGroups(main: '腿', secondary: ['核心']), true, 'home'),
  ExerciseMeta('波比跳', MuscleGroups(main: '核心', secondary: ['胸', '腿']), true, 'home'),
  ExerciseMeta('登山跑', MuscleGroups(main: '核心', secondary: ['腿']), false, 'home'),
  ExerciseMeta('熊爬', MuscleGroups(main: '核心', secondary: ['肩', '腿']), true, 'home'),
  ExerciseMeta('死虫式', MuscleGroups(main: '核心', secondary: []), false, 'home'),
  ExerciseMeta('鸟狗式', MuscleGroups(main: '核心', secondary: ['背']), false, 'home'),
  ExerciseMeta('哑铃单腿硬拉', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both'),
  ExerciseMeta('药球砸地', MuscleGroups(main: '核心', secondary: ['背', '肩']), true, 'gym'),
  ExerciseMeta('战绳（双甩）', MuscleGroups(main: '核心', secondary: ['肩', '手臂']), true, 'gym'),
  ExerciseMeta('弹力带伐木', MuscleGroups(main: '核心', secondary: ['肩']), true, 'home'),
  ExerciseMeta('雪橇推', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym'),
  ExerciseMeta('土耳其起立', MuscleGroups(main: '核心', secondary: ['肩', '手臂']), true, 'both'),
];

/// 兼容旧引用：薄肌计划内置词表 = 大库子集。
const kBaojiExerciseMeta = kExerciseLibrary;

// ================= 计划模板 =================

class PresetExercise {
  final String name;
  final int sets;
  final int repsMin;
  final int repsMax;
  final int restSec;
  final String kind;
  const PresetExercise(this.name, this.sets, this.repsMin, this.repsMax,
      this.restSec, this.kind);

  PlanExercise toPlanExercise(int dayId, int orderIdx) => PlanExercise(
        dayId: dayId,
        name: name,
        orderIdx: orderIdx,
        sets: sets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSec: restSec,
        kind: kind,
        rule: ProgressionRule(
          repsMin: repsMin,
          repsMax: repsMax,
          incrementKg: kind == 'compound' ? 2.5 : 1.25,
          workingSets: sets,
          desc: kind == 'compound'
              ? '全部正式组达 $repsMax 次且末组余力≥1 → 加 2.5kg；有组低于 $repsMin 次 → 减 5%'
              : '全部正式组达 $repsMax 次且末组余力≥1 → 加 1.25kg',
        ),
      );
}

class PlanTemplate {
  final String name;
  final String source; // preset
  final String intro; // 模板选择页的一句介绍
  final String note; // 适合谁
  final Map<int, List<PresetExercise>> byWeekday; // weekday -> 动作
  const PlanTemplate({
    required this.name,
    required this.source,
    required this.intro,
    required this.note,
    required this.byWeekday,
  });

  String get dayTitle => name;
}

/// 模板 1：三分化 PPL（推/拉/腿，每周 6 练或 3 练轮转）——健美经典。
const kPplTemplate = PlanTemplate(
  name: '三分化（推·拉·腿）',
  source: 'preset',
  intro: '推日（胸肩三头）/ 拉日（背二头）/ 腿日，经典健美分化，每肌群每周刺激 1-2 次',
  note: '适合每周 3-6 练、以增肌为主的训练者；时间紧就按 推→拉→腿 轮转',
  byWeekday: {
    // 周一 推
    1: [
      PresetExercise('杠铃卧推', 4, 5, 8, 180, 'compound'),
      PresetExercise('坐姿哑铃推举', 3, 8, 12, 120, 'compound'),
      PresetExercise('上斜哑铃卧推', 3, 8, 12, 120, 'compound'),
      PresetExercise('哑铃侧平举', 4, 12, 15, 75, 'assistance'),
      PresetExercise('绳索下压', 3, 10, 12, 75, 'assistance'),
    ],
    // 周二 拉
    2: [
      PresetExercise('杠铃硬拉', 3, 5, 8, 180, 'compound'),
      PresetExercise('引体向上', 4, 6, 10, 150, 'compound'),
      PresetExercise('坐姿划船', 3, 8, 12, 120, 'assistance'),
      PresetExercise('俯身飞鸟（后束）', 4, 12, 15, 75, 'assistance'),
      PresetExercise('杠铃弯举', 3, 10, 12, 75, 'assistance'),
    ],
    // 周三 腿
    3: [
      PresetExercise('杠铃深蹲', 4, 5, 8, 180, 'compound'),
      PresetExercise('罗马尼亚硬拉', 3, 8, 10, 150, 'compound'),
      PresetExercise('腿举（倒蹬机）', 3, 10, 12, 120, 'compound'),
      PresetExercise('腿弯举（腘绳肌）', 3, 10, 12, 75, 'assistance'),
      PresetExercise('站姿提踵', 4, 12, 15, 60, 'assistance'),
    ],
    // 周四 推（第二循环，轻重高次）
    4: [
      PresetExercise('上斜杠铃卧推', 3, 8, 12, 120, 'compound'),
      PresetExercise('哑铃卧推', 3, 8, 12, 120, 'compound'),
      PresetExercise('哑铃侧平举', 4, 12, 20, 60, 'assistance'),
      PresetExercise('哑铃颈后臂屈伸', 3, 10, 12, 75, 'assistance'),
    ],
    // 周五 拉
    5: [
      PresetExercise('高位下拉', 4, 8, 12, 120, 'compound'),
      PresetExercise('T杠划船', 3, 8, 12, 120, 'compound'),
      PresetExercise('面拉', 3, 12, 15, 60, 'assistance'),
      PresetExercise('哑铃锤式弯举', 3, 10, 12, 60, 'assistance'),
    ],
    // 周六 腿（第二循环）
    6: [
      PresetExercise('保加利亚分腿蹲', 3, 8, 12, 120, 'compound'),
      PresetExercise('哑铃罗马尼亚硬拉', 3, 8, 12, 120, 'compound'),
      PresetExercise('腿屈伸（股四头）', 3, 12, 15, 60, 'assistance'),
      PresetExercise('杠铃臀桥', 3, 10, 12, 90, 'compound'),
    ],
  },
);

/// 模板 2：五分化（胸/背/肩/手臂/腿）——经典健美式，每部位一天精雕。
const kBroSplitTemplate = PlanTemplate(
  name: '五分化（胸·背·肩·臂·腿）',
  source: 'preset',
  intro: '每天专攻一个部位，动作量大、单部位刺激深，经典健美式训练',
  note: '适合每周稳定 5 练、追求单部位容量的中高级训练者',
  byWeekday: {
    // 周一 胸
    1: [
      PresetExercise('杠铃卧推', 4, 6, 8, 180, 'compound'),
      PresetExercise('上斜哑铃卧推', 3, 8, 12, 120, 'compound'),
      PresetExercise('坐姿夹胸（蝴蝶机）', 3, 12, 15, 75, 'assistance'),
      PresetExercise('绳索夹胸', 3, 12, 15, 60, 'assistance'),
      PresetExercise('双杠臂屈伸（挺胸）', 3, 8, 12, 90, 'compound'),
    ],
    // 周二 背
    2: [
      PresetExercise('引体向上', 4, 6, 10, 150, 'compound'),
      PresetExercise('杠铃划船', 4, 8, 10, 150, 'compound'),
      PresetExercise('高位下拉', 3, 10, 12, 90, 'assistance'),
      PresetExercise('坐姿划船', 3, 10, 12, 90, 'assistance'),
      PresetExercise('直臂下压', 3, 12, 15, 60, 'assistance'),
    ],
    // 周三 肩
    3: [
      PresetExercise('站姿推举', 4, 6, 8, 180, 'compound'),
      PresetExercise('哑铃侧平举', 4, 12, 15, 60, 'assistance'),
      PresetExercise('哑铃前平举', 3, 12, 15, 60, 'assistance'),
      PresetExercise('俯身飞鸟（后束）', 4, 12, 15, 60, 'assistance'),
      PresetExercise('杠铃耸肩', 3, 10, 12, 75, 'assistance'),
    ],
    // 周四 手臂
    4: [
      PresetExercise('窄距卧推', 3, 8, 10, 120, 'compound'),
      PresetExercise('绳索下压', 4, 10, 12, 60, 'assistance'),
      PresetExercise('哑铃颈后臂屈伸', 3, 10, 12, 75, 'assistance'),
      PresetExercise('杠铃弯举', 4, 8, 12, 75, 'assistance'),
      PresetExercise('哑铃锤式弯举', 3, 10, 12, 60, 'assistance'),
    ],
    // 周五 腿
    5: [
      PresetExercise('杠铃深蹲', 4, 5, 8, 180, 'compound'),
      PresetExercise('腿举（倒蹬机）', 4, 10, 12, 120, 'compound'),
      PresetExercise('罗马尼亚硬拉', 3, 8, 10, 150, 'compound'),
      PresetExercise('腿屈伸（股四头）', 3, 12, 15, 60, 'assistance'),
      PresetExercise('腿弯举（腘绳肌）', 3, 12, 15, 60, 'assistance'),
      PresetExercise('站姿提踵', 4, 12, 15, 60, 'assistance'),
    ],
  },
);

/// 模板 3：功能性训练（全身 3 练，多关节 + 核心 + 体能）。
const kFunctionalTemplate = PlanTemplate(
  name: '功能性训练（全身）',
  source: 'preset',
  intro: '壶铃/爆发/核心/单侧动作，练"用得上的力量"，兼顾体态与心肺',
  note: '适合久坐办公、想改善体能与核心稳定的人；健身房居家动作各半可替换',
  byWeekday: {
    // 周一 全身 A（下肢主导）
    1: [
      PresetExercise('壶铃摆荡', 4, 12, 15, 60, 'compound'),
      PresetExercise('哑铃高脚杯深蹲', 3, 8, 12, 120, 'compound'),
      PresetExercise('哑铃单腿硬拉', 3, 8, 10, 90, 'compound'),
      PresetExercise('健腹轮', 3, 8, 12, 60, 'assistance'),
      PresetExercise('死虫式', 3, 10, 12, 45, 'assistance'),
    ],
    // 周三 全身 B（上肢主导）
    3: [
      PresetExercise('哑铃卧推', 4, 8, 12, 120, 'compound'),
      PresetExercise('哑铃单臂划船', 4, 8, 12, 90, 'compound'),
      PresetExercise('坐姿哑铃推举', 3, 8, 12, 90, 'compound'),
      PresetExercise('弹力带面拉', 3, 12, 15, 45, 'assistance'),
      PresetExercise('平板支撑', 3, 40, 60, 45, 'assistance'),
    ],
    // 周五 全身 C（爆发 + 体能）
    5: [
      PresetExercise('深蹲跳', 4, 8, 10, 90, 'compound'),
      PresetExercise('波比跳', 3, 10, 12, 60, 'compound'),
      PresetExercise('哑铃农夫行走', 3, 30, 40, 75, 'compound'),
      PresetExercise('弹力带伐木', 3, 10, 12, 45, 'compound'),
      PresetExercise('鸟狗式', 3, 10, 12, 45, 'assistance'),
    ],
  },
);

/// 模板 4：居家哑铃全身（健身房去不了时的备胎）。
const kHomeTemplate = PlanTemplate(
  name: '居家哑铃全身',
  source: 'preset',
  intro: '一副哑铃 + 自重，全身 3 练，出差/居家不断训',
  note: '适合只有哑铃（或弹力带）的环境；回健身房后切回主力计划',
  byWeekday: {
    1: [
      PresetExercise('哑铃卧推', 4, 8, 12, 90, 'compound'),
      PresetExercise('哑铃单臂划船', 4, 8, 12, 75, 'compound'),
      PresetExercise('哑铃高脚杯深蹲', 3, 10, 12, 90, 'compound'),
      PresetExercise('哑铃侧平举', 3, 12, 15, 45, 'assistance'),
      PresetExercise('卷腹', 3, 15, 20, 45, 'assistance'),
    ],
    3: [
      PresetExercise('俯卧撑', 4, 12, 20, 60, 'compound'),
      PresetExercise('弹力带坐姿划船', 4, 12, 15, 60, 'assistance'),
      PresetExercise('箭步蹲', 3, 10, 12, 75, 'compound'),
      PresetExercise('派克俯卧撑', 3, 8, 12, 75, 'compound'),
      PresetExercise('哑铃弯举', 3, 10, 12, 45, 'assistance'),
    ],
    5: [
      PresetExercise('上斜俯卧撑', 4, 12, 15, 60, 'compound'),
      PresetExercise('哑铃罗马尼亚硬拉', 3, 10, 12, 90, 'compound'),
      PresetExercise('臀桥', 3, 12, 15, 60, 'assistance'),
      PresetExercise('凳上臂屈伸', 3, 10, 12, 45, 'assistance'),
      PresetExercise('平板支撑', 3, 40, 60, 45, 'assistance'),
    ],
  },
);

/// 全部可选模板（模板选择页展示）。
const kPlanTemplates = [kPplTemplate, kBroSplitTemplate, kFunctionalTemplate, kHomeTemplate];
