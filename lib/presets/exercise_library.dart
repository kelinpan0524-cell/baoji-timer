import '../models/models.dart';


/// 内置动作库：覆盖健身房（杠铃/器械）、居家（哑铃/弹力带/自重）、功能性训练。
/// equipment: gym=健身房 / home=居家 / both=皆可
/// cue: 动作要点讲解（中文，空=无）；gear: 细分器械
///      （杠铃/哑铃/龙门架绳索/固定器械/弹力带/自重/壶铃/其他器械，空=未标注）
/// 供：动作库浏览页、编辑器联想、AI 拆解提示词、计划模板。
const kExerciseLibrary = <ExerciseMeta>[
  // ============ 胸（健身房） ============
  ExerciseMeta('杠铃卧推', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'gym', '杠铃'),
  ExerciseMeta('上斜杠铃卧推', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'gym', '杠铃'),
  ExerciseMeta('上斜哑铃卧推', MuscleGroups(main: '胸', secondary: ['肩']), true, 'both', '哑铃'),
  ExerciseMeta('哑铃卧推', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'both', '哑铃'),
  ExerciseMeta('坐姿夹胸（蝴蝶机）', MuscleGroups(main: '胸', secondary: []), false, 'gym', '固定器械'),
  ExerciseMeta('绳索夹胸', MuscleGroups(main: '胸', secondary: []), false, 'gym', '龙门架绳索'),
  ExerciseMeta('双杠臂屈伸（挺胸）', MuscleGroups(main: '胸', secondary: ['手臂']), true, 'both', '自重'),
  // ============ 胸（居家） ============
  ExerciseMeta('俯卧撑', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'home', '自重'),
  ExerciseMeta('上斜俯卧撑', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'home', '自重'),
  ExerciseMeta('下斜俯卧撑（脚垫高）', MuscleGroups(main: '胸', secondary: ['肩', '手臂']), true, 'home', '自重'),
  ExerciseMeta('上斜杠铃卧推（轻）', MuscleGroups(main: '胸', secondary: ['肩']), true, 'gym', '杠铃'),
  ExerciseMeta('哑铃飞鸟', MuscleGroups(main: '胸', secondary: []), false, 'both', '哑铃'),
  ExerciseMeta('弹力带夹胸', MuscleGroups(main: '胸', secondary: []), false, 'home', '弹力带'),

  // ============ 背（健身房） ============
  ExerciseMeta('引体向上', MuscleGroups(main: '背', secondary: ['手臂']), true, 'both', '自重'),
  ExerciseMeta('负重引体向上', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym', '自重'),
  ExerciseMeta('高位下拉', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym', '龙门架绳索'),
  ExerciseMeta('杠铃划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym', '杠铃'),
  ExerciseMeta('坐姿划船', MuscleGroups(main: '背', secondary: ['手臂']), false, 'gym', '龙门架绳索'),
  ExerciseMeta('杠铃硬拉', MuscleGroups(main: '背', secondary: ['腿', '核心']), true, 'gym', '杠铃'),
  ExerciseMeta('直臂下压', MuscleGroups(main: '背', secondary: []), false, 'gym', '龙门架绳索'),
  ExerciseMeta('T杠划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'gym', '杠铃'),
  // ============ 背（居家） ============
  ExerciseMeta('哑铃单臂划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'both', '哑铃'),
  ExerciseMeta('弹力带下拉', MuscleGroups(main: '背', secondary: ['手臂']), true, 'home', '弹力带'),
  ExerciseMeta('弹力带坐姿划船', MuscleGroups(main: '背', secondary: ['手臂']), false, 'home', '弹力带'),
  ExerciseMeta('超人式', MuscleGroups(main: '背', secondary: ['核心']), false, 'home', '自重'),
  ExerciseMeta('反向雪天使', MuscleGroups(main: '背', secondary: ['肩']), false, 'home', '自重'),

  // ============ 肩（健身房） ============
  ExerciseMeta('站姿推举', MuscleGroups(main: '肩', secondary: ['手臂', '核心']), true, 'gym', '杠铃'),
  ExerciseMeta('坐姿哑铃推举', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'both', '哑铃'),
  ExerciseMeta('史密斯机推肩', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'gym', '固定器械'),
  ExerciseMeta('哑铃侧平举', MuscleGroups(main: '肩', secondary: []), false, 'both', '哑铃'),
  ExerciseMeta('俯身飞鸟（后束）', MuscleGroups(main: '肩', secondary: ['背']), false, 'both', '哑铃'),
  ExerciseMeta('面拉', MuscleGroups(main: '肩', secondary: ['背']), false, 'gym', '龙门架绳索'),
  ExerciseMeta('哑铃前平举', MuscleGroups(main: '肩', secondary: []), false, 'both', '哑铃'),
  ExerciseMeta('杠铃耸肩', MuscleGroups(main: '肩', secondary: []), false, 'gym', '杠铃'),
  // ============ 肩（居家） ============
  ExerciseMeta('弹力带侧平举', MuscleGroups(main: '肩', secondary: []), false, 'home', '弹力带'),
  ExerciseMeta('派克俯卧撑', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'home', '自重'),
  ExerciseMeta('弹力带面拉', MuscleGroups(main: '肩', secondary: ['背']), false, 'home', '弹力带'),

  // ============ 手臂 ============
  ExerciseMeta('杠铃弯举', MuscleGroups(main: '手臂', secondary: []), false, 'gym', '杠铃'),
  ExerciseMeta('哑铃锤式弯举', MuscleGroups(main: '手臂', secondary: []), false, 'both', '哑铃'),
  ExerciseMeta('哑铃弯举', MuscleGroups(main: '手臂', secondary: []), false, 'both', '哑铃'),
  ExerciseMeta('绳索下压', MuscleGroups(main: '手臂', secondary: []), false, 'gym', '龙门架绳索'),
  ExerciseMeta('哑铃颈后臂屈伸', MuscleGroups(main: '手臂', secondary: []), false, 'both', '哑铃'),
  ExerciseMeta('窄距卧推', MuscleGroups(main: '手臂', secondary: ['胸']), true, 'gym', '杠铃'),
  ExerciseMeta('弹力带弯举', MuscleGroups(main: '手臂', secondary: []), false, 'home', '弹力带'),
  ExerciseMeta('凳上臂屈伸', MuscleGroups(main: '手臂', secondary: []), false, 'home', '自重'),
  ExerciseMeta('双杠臂屈伸', MuscleGroups(main: '手臂', secondary: ['胸']), true, 'both', '自重'),

  // ============ 腿（健身房） ============
  ExerciseMeta('杠铃深蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym', '杠铃'),
  ExerciseMeta('腿举（倒蹬机）', MuscleGroups(main: '腿', secondary: []), true, 'gym', '固定器械'),
  ExerciseMeta('保加利亚分腿蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both', '哑铃'),
  ExerciseMeta('哈克深蹲', MuscleGroups(main: '腿', secondary: []), true, 'gym', '固定器械'),
  ExerciseMeta('罗马尼亚硬拉', MuscleGroups(main: '腿', secondary: ['背', '核心']), true, 'gym', '杠铃'),
  ExerciseMeta('哑铃罗马尼亚硬拉', MuscleGroups(main: '腿', secondary: ['背']), true, 'both', '哑铃'),
  ExerciseMeta('腿屈伸（股四头）', MuscleGroups(main: '腿', secondary: []), false, 'gym', '固定器械'),
  ExerciseMeta('腿弯举（腘绳肌）', MuscleGroups(main: '腿', secondary: []), false, 'gym', '固定器械'),
  ExerciseMeta('站姿提踵', MuscleGroups(main: '腿', secondary: []), false, 'both', '自重'),
  ExerciseMeta('杠铃臀桥', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym', '杠铃'),
  // ============ 腿（居家） ============
  ExerciseMeta('徒手深蹲', MuscleGroups(main: '腿', secondary: []), true, 'home', '自重'),
  ExerciseMeta('哑铃高脚杯深蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both', '哑铃'),
  ExerciseMeta('箭步蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'home', '自重'),
  ExerciseMeta('臀桥', MuscleGroups(main: '腿', secondary: ['核心']), false, 'home', '自重'),
  ExerciseMeta('单腿臀桥', MuscleGroups(main: '腿', secondary: ['核心']), false, 'home', '自重'),
  ExerciseMeta('靠墙静蹲', MuscleGroups(main: '腿', secondary: []), false, 'home', '自重'),

  // ============ 核心 ============
  ExerciseMeta('平板支撑', MuscleGroups(main: '核心', secondary: []), false, 'home', '自重'),
  ExerciseMeta('侧平板支撑', MuscleGroups(main: '核心', secondary: []), false, 'home', '自重'),
  ExerciseMeta('卷腹', MuscleGroups(main: '核心', secondary: []), false, 'home', '自重'),
  ExerciseMeta('悬垂举腿', MuscleGroups(main: '核心', secondary: ['手臂']), false, 'gym', '自重'),
  ExerciseMeta('俄罗斯转体', MuscleGroups(main: '核心', secondary: []), false, 'home', '自重'),
  ExerciseMeta('健腹轮', MuscleGroups(main: '核心', secondary: ['手臂']), false, 'both', '其他器械'),

  // ============ 功能性训练 ============
  ExerciseMeta('壶铃摆荡', MuscleGroups(main: '腿', secondary: ['背', '核心']), true, 'both', '壶铃'),
  ExerciseMeta('哑铃农夫行走', MuscleGroups(main: '核心', secondary: ['手臂', '肩']), true, 'both', '哑铃'),
  ExerciseMeta('箱跳', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym', '自重'),
  ExerciseMeta('深蹲跳', MuscleGroups(main: '腿', secondary: ['核心']), true, 'home', '自重'),
  ExerciseMeta('波比跳', MuscleGroups(main: '核心', secondary: ['胸', '腿']), true, 'home', '自重'),
  ExerciseMeta('登山跑', MuscleGroups(main: '核心', secondary: ['腿']), false, 'home', '自重'),
  ExerciseMeta('熊爬', MuscleGroups(main: '核心', secondary: ['肩', '腿']), true, 'home', '自重'),
  ExerciseMeta('死虫式', MuscleGroups(main: '核心', secondary: []), false, 'home', '自重'),
  ExerciseMeta('鸟狗式', MuscleGroups(main: '核心', secondary: ['背']), false, 'home', '自重'),
  ExerciseMeta('哑铃单腿硬拉', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both', '哑铃'),
  ExerciseMeta('药球砸地', MuscleGroups(main: '核心', secondary: ['背', '肩']), true, 'gym', '其他器械'),
  ExerciseMeta('战绳（双甩）', MuscleGroups(main: '核心', secondary: ['肩', '手臂']), true, 'gym', '其他器械'),
  ExerciseMeta('弹力带伐木', MuscleGroups(main: '核心', secondary: ['肩']), true, 'home', '弹力带'),
  ExerciseMeta('雪橇推', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym', '其他器械'),
  ExerciseMeta('土耳其起立', MuscleGroups(main: '核心', secondary: ['肩', '手臂']), true, 'both', '壶铃'),

  // ============ 补库新增（2026-09，wger/free-exercise-db/训练体系常识） ============
  // —— 胸 ——
  ExerciseMeta('哑铃仰卧上拉', MuscleGroups(main: '胸', secondary: ['背']), false, 'both',
      '上背横躺平凳、双脚踩实，双手托一只哑铃一端举在胸口上方；肘部微屈并全程保持角度不变，靠胸和背阔把哑铃沿弧线向头后下放至感到拉伸，再沿原弧线收回。常见错误：肘角越拉越大变成三头臂屈伸，以及下放过深拉伤肩关节。',
      '哑铃'),
  // —— 背 ——
  ExerciseMeta('山羊挺身', MuscleGroups(main: '背', secondary: ['腿']), false, 'gym',
      '髋部贴住罗马椅垫、脚踝勾住挡板，双手抱胸；屈髋控制躯干下放至约与地面平行，靠下背和臀部把上身挺起到与腿成一条直线即止。不要刻意向后反弓腰椎，也不要靠甩动借力，全程慢而有控制。可抱杠铃片渐进加重。',
      '固定器械'),
  ExerciseMeta('反向划船', MuscleGroups(main: '背', secondary: ['手臂']), true, 'both',
      '找低单杠、架上的横杠或稳固桌子，身体从头到脚绷成一条直线、脚跟撑地，握距略宽于肩；肩胛先收紧下沉，再屈肘把胸口拉向横杆、顶点停一秒。常见错误：塌腰撅臀、用脖子够杠或只用手臂拽而不收肩胛。把杠调高即可降低难度。',
      '自重'),
  // —— 肩 ——
  ExerciseMeta('阿诺德推举', MuscleGroups(main: '肩', secondary: ['手臂']), true, 'both',
      '坐姿背靠垫，双手各持一哑铃举在胸前、掌心朝向自己；向上推起的同时旋转手腕到掌心朝前，下落时反向旋回起点。全程肘部微收在身体前侧、小臂垂直地面，腰背贴垫不反弓。常见错误：重量贪大导致旋转做不完整、变成借力甩肩。',
      '哑铃'),
  ExerciseMeta('弹力带肩外旋', MuscleGroups(main: '肩', secondary: []), false, 'home',
      '大臂夹紧身体侧面、肘弯 90 度，握弹力带一端，前臂向外旋开像开门；带子向内拉时保持肘部始终不离身侧。肩袖小肌群保养动作，重量要轻、次数可到 15-20 次。常见错误：肘部外飘、躯干跟着旋转代偿。',
      '弹力带'),
  ExerciseMeta('蝴蝶机反向飞鸟（后束）', MuscleGroups(main: '肩', secondary: ['背']), false, 'gym',
      '坐姿胸口贴紧靠垫、肩膀下沉，双手握把手，用肘部带动手臂向侧后方展开；顶峰收缩一秒再缓慢还原，全程重量可控不甩动。常见错误：耸肩让斜方肌代偿、幅度过大靠惯性甩。',
      '固定器械'),
  // —— 手臂 ——
  ExerciseMeta('牧师凳弯举', MuscleGroups(main: '手臂', secondary: []), false, 'gym',
      '上臂与腋下贴紧斜垫、肘部固定在垫上，只有小臂做弯举；顶峰稍停，再缓慢放到底感受拉伸，肘部微屈不停留泄力。凳子角度让二头在底部拉伸最充分。常见错误：耸肩、肘部抬离垫面借力甩起。',
      '固定器械'),
  // —— 腿 ——
  ExerciseMeta('登阶', MuscleGroups(main: '腿', secondary: ['核心']), true, 'both',
      '找膝高左右的凳子或台阶，全脚掌踩实后靠前腿的臀和大腿把身体蹬上去，后腿轻点即收、不借力；下落时由前腿控制慢放。常见错误：上身前倾过多，或后腿猛蹬抢走前腿的刺激。可双手持哑铃加重。',
      '自重'),
  ExerciseMeta('坐姿提踵', MuscleGroups(main: '腿', secondary: []), false, 'gym',
      '屈膝约 90 度坐在提踵器上，前脚掌踩踏板、膝盖压住固定垫；脚跟下放到底让小腿充分拉伸，再踮起到最高点顶峰停 1-2 秒。屈膝姿势练的是深层比目鱼肌。常见错误：幅度太小只在中段蹭、靠惯性上下颠。',
      '固定器械'),
  ExerciseMeta('北欧腿弯举', MuscleGroups(main: '腿', secondary: []), false, 'home',
      '跪姿、脚踝被人或沙发压住固定，髋到肩保持一条直线慢慢前倒；只用腘绳肌把自己拉回来，初期可以双手轻推地面减负。下放得越慢价值越大。常见错误：塌腰撅臀着倒下去、上来就追全程——先做半程或加弹力带辅助。',
      '自重'),
  ExerciseMeta('颈前深蹲', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym',
      '杠铃压在锁骨与三角肌前束上，手肘抬高朝前接近与地面平行，核心收紧、躯干保持垂直下蹲到大腿平行或更低。常见错误：手肘下垂导致杠铃前滚、躯干前倾；手腕或肩灵活度不足时先用高脚杯深蹲过渡。',
      '杠铃'),
  ExerciseMeta('杠铃臀推', MuscleGroups(main: '腿', secondary: ['核心']), true, 'gym',
      '肩胛下缘靠住训练凳，杠铃加垫压在髋部，双脚踩实地面；脚跟发力把髋顶到肩、髋、膝成一条直线，顶峰收紧臀肌 1-2 秒再控制下放。常见错误：顶端过度塌腰（腰椎超伸）、靠惯性弹起。',
      '杠铃'),
  // —— 核心 ——
  ExerciseMeta('绳索卷腹', MuscleGroups(main: '核心', secondary: []), false, 'gym',
      '面对高位滑轮跪地，绳索把手握在头两侧、髋部保持固定；用腹肌把肋骨向骨盆方向卷下来、肘部朝膝盖方向走，背部拱起才算卷到位。常见错误：整个上身像鞠躬一样平着俯下去——那是髋在动，不是腹肌在卷。',
      '龙门架绳索'),
  ExerciseMeta('帕洛夫推举', MuscleGroups(main: '核心', secondary: ['肩']), false, 'gym',
      '侧身站在龙门架滑轮（居家可用弹力带锚点替代）旁，双手把拉到胸前的把手稳住，先感受侧腹的抗旋转张力；呼气把双臂向前推直、停 2-3 秒再缓慢收回，两侧都做。常见错误：被重量带着转腰、推出时憋气塌腰。',
      '龙门架绳索'),
  ExerciseMeta('反向卷腹', MuscleGroups(main: '核心', secondary: []), false, 'home',
      '仰卧屈膝、下背贴地，靠下腹把骨盆向肋骨方向卷起、膝盖向胸口收，而不是用腿甩；下放要缓慢，腰部始终不离开地面。常见错误：靠大腿摆动借力，动作变成抬腿而非骨盆卷起。',
      '自重'),
  ExerciseMeta('哑铃侧屈', MuscleGroups(main: '核心', secondary: []), false, 'both',
      '单手握哑铃站直，另一手扶头，向握铃一侧屈体，再靠对侧腹斜肌把身体拉直，全程骨盆稳定；身体只做侧向折叠，不前倾不后仰。常见错误：低头含胸用惯性晃动、重量太大变成耸肩。',
      '哑铃'),
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
