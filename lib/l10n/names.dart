import 'lang.dart';

/// 数据名词的显示层英译表。
/// 数据库里存的中文名（动作/肌群/模板/训练日标题）是数据键，绝不能改存储值；
/// 本表只在【渲染】时把中文映射成英文，映射不到的原样回落中文
/// （用户自建动作、AI 生成的新动作等，英文界面下保留原文可接受）。

const _kExerciseEn = <String, String>{
  // 胸
  '杠铃卧推': 'Barbell Bench Press',
  '上斜杠铃卧推': 'Incline Barbell Bench Press',
  '上斜哑铃卧推': 'Incline Dumbbell Bench Press',
  '哑铃卧推': 'Dumbbell Bench Press',
  '坐姿夹胸（蝴蝶机）': 'Seated Chest Fly (Pec Deck)',
  '绳索夹胸': 'Cable Chest Fly',
  '双杠臂屈伸（挺胸）': 'Chest Dip',
  '俯卧撑': 'Push-up',
  '上斜俯卧撑': 'Incline Push-up',
  '下斜俯卧撑（脚垫高）': 'Decline Push-up (Feet Elevated)',
  '上斜杠铃卧推（轻）': 'Incline Barbell Press (Light)',
  '哑铃飞鸟': 'Dumbbell Fly',
  '弹力带夹胸': 'Band Chest Fly',
  // 背
  '引体向上': 'Pull-up',
  '负重引体向上': 'Weighted Pull-up',
  '高位下拉': 'Lat Pulldown',
  '杠铃划船': 'Barbell Row',
  '坐姿划船': 'Seated Cable Row',
  '杠铃硬拉': 'Deadlift',
  '直臂下压': 'Straight-Arm Pulldown',
  'T杠划船': 'T-Bar Row',
  '哑铃单臂划船': 'Single-Arm Dumbbell Row',
  '弹力带下拉': 'Band Pulldown',
  '弹力带坐姿划船': 'Band Seated Row',
  '超人式': 'Superman',
  '反向雪天使': 'Reverse Snow Angel',
  // 肩
  '站姿推举': 'Overhead Press',
  '坐姿哑铃推举': 'Seated Dumbbell Press',
  '史密斯机推肩': 'Smith Machine Shoulder Press',
  '哑铃侧平举': 'Dumbbell Lateral Raise',
  '俯身飞鸟（后束）': 'Bent-Over Reverse Fly (Rear Delt)',
  '面拉': 'Face Pull',
  '哑铃前平举': 'Dumbbell Front Raise',
  '杠铃耸肩': 'Barbell Shrug',
  '弹力带侧平举': 'Band Lateral Raise',
  '派克俯卧撑': 'Pike Push-up',
  '弹力带面拉': 'Band Face Pull',
  // 手臂
  '杠铃弯举': 'Barbell Curl',
  '哑铃锤式弯举': 'Hammer Curl',
  '哑铃弯举': 'Dumbbell Curl',
  '绳索下压': 'Cable Triceps Pushdown',
  '哑铃颈后臂屈伸': 'Overhead Dumbbell Triceps Extension',
  '窄距卧推': 'Close-Grip Bench Press',
  '弹力带弯举': 'Band Curl',
  '凳上臂屈伸': 'Bench Dip',
  '双杠臂屈伸': 'Dip',
  // 腿
  '杠铃深蹲': 'Barbell Squat',
  '腿举（倒蹬机）': 'Leg Press',
  '保加利亚分腿蹲': 'Bulgarian Split Squat',
  '哈克深蹲': 'Hack Squat',
  '罗马尼亚硬拉': 'Romanian Deadlift',
  '哑铃罗马尼亚硬拉': 'Dumbbell Romanian Deadlift',
  '腿屈伸（股四头）': 'Leg Extension (Quads)',
  '腿弯举（腘绳肌）': 'Leg Curl (Hamstrings)',
  '站姿提踵': 'Standing Calf Raise',
  '杠铃臀桥': 'Barbell Glute Bridge',
  '徒手深蹲': 'Bodyweight Squat',
  '哑铃高脚杯深蹲': 'Goblet Squat',
  '箭步蹲': 'Lunge',
  '臀桥': 'Glute Bridge',
  '单腿臀桥': 'Single-Leg Glute Bridge',
  '靠墙静蹲': 'Wall Sit',
  // 核心
  '平板支撑': 'Plank',
  '侧平板支撑': 'Side Plank',
  '卷腹': 'Crunch',
  '悬垂举腿': 'Hanging Leg Raise',
  '俄罗斯转体': 'Russian Twist',
  '健腹轮': 'Ab Wheel Rollout',
  // 功能/全身
  '壶铃摆荡': 'Kettlebell Swing',
  '哑铃农夫行走': "Farmer's Walk",
  '箱跳': 'Box Jump',
  '深蹲跳': 'Jump Squat',
  '波比跳': 'Burpee',
  '登山跑': 'Mountain Climber',
  '熊爬': 'Bear Crawl',
  '死虫式': 'Dead Bug',
  '鸟狗式': 'Bird Dog',
  '哑铃单腿硬拉': 'Single-Leg Dumbbell Deadlift',
  '药球砸地': 'Med Ball Slam',
  '战绳（双甩）': 'Battle Ropes (Alternating Waves)',
  '弹力带伐木': 'Band Woodchopper',
  '雪橇推': 'Sled Push',
  '土耳其起立': 'Turkish Get-up',
};

/// 训练日标题 / 计划模板名 / 模板介绍等随库内置的名词。
const _kPresetNounEn = <String, String>{
  // 薄肌计划
  '薄肌计划（内置）': 'Baoji Plan (built-in)',
  '推力日 A（胸·肩）': 'Push Day A (Chest · Shoulders)',
  '拉力日（背·后束）': 'Pull Day (Back · Rear Delts)',
  '腿部日 + 轻推·手臂': 'Leg Day + Light Push · Arms',
  '训练日': 'Training Day',
  // 内置模板
  '三分化（推·拉·腿）': 'Push/Pull/Legs Split',
  '五分化（胸·背·肩·臂·腿）': 'Bro Split (Chest · Back · Shoulders · Arms · Legs)',
  '功能性训练（全身）': 'Functional Training (Full Body)',
  '居家哑铃全身': 'Home Dumbbell Full Body',
  '推日（胸肩三头）/ 拉日（背二头）/ 腿日，经典健美分化，每肌群每周刺激 1-2 次':
      'Push (chest/shoulders/triceps), pull (back/biceps) and legs — the classic bodybuilding split, each muscle 1-2x per week',
  '适合每周 3-6 练、以增肌为主的训练者；时间紧就按 推→拉→腿 轮转':
      'For 3-6 sessions a week focused on muscle growth; short on time? rotate Push → Pull → Legs',
  '每天专攻一个部位，动作量大、单部位刺激深，经典健美式训练':
      'One body part per day, high volume and deep stimulus — classic old-school training',
  '适合每周稳定 5 练、追求单部位容量的中高级训练者':
      'For intermediate/advanced lifters training 5 days a week chasing per-part volume',
  '壶铃/爆发/核心/单侧动作，练"用得上的力量"，兼顾体态与心肺':
      'Kettlebell, power, core and unilateral work — strength you can use, plus posture and conditioning',
  '适合久坐办公、想改善体能与核心稳定的人；健身房居家动作各半可替换':
      'For desk-bound folks improving conditioning and core stability; gym/home moves are swappable',
  '一副哑铃 + 自重，全身 3 练，出差/居家不断训':
      'One pair of dumbbells plus bodyweight, 3 full-body days — never miss a session at home or on the road',
  '适合只有哑铃（或弹力带）的环境；回健身房后切回主力计划':
      'For dumbbell-only (or band-only) setups; switch back to your main plan when you return to the gym',
};

/// 肌群名（热力图分区，中文是数据键）。
const _kMuscleEn = <String, String>{
  '胸': 'Chest',
  '肩': 'Shoulders',
  '背': 'Back',
  '手臂': 'Arms',
  '腿': 'Legs',
  '核心': 'Core',
  '其他': 'Other',
};

/// 器械场景（存储值 gym/home/both 或中文标签）。
const _kEquipmentEn = <String, String>{
  'gym': 'Gym',
  'home': 'Home',
  'both': 'Gym / Home',
  '健身房': 'Gym',
  '居家': 'Home',
  '皆可': 'Gym / Home',
  '全部': 'All',
};

/// 动作名显示（动作库/训练/历史/统计等处）。
String exname(String zh) => Lang.isEn ? (_kExerciseEn[zh] ?? zh) : zh;

/// 库内置名词（模板名/训练日标题等）显示。
String dname(String zh) => Lang.isEn ? (_kPresetNounEn[zh] ?? zh) : zh;

/// 肌群名显示。
String mname(String zh) => Lang.isEn ? (_kMuscleEn[zh] ?? zh) : zh;

/// 器械场景显示。
String eqname(String zh) => Lang.isEn ? (_kEquipmentEn[zh] ?? zh) : zh;
