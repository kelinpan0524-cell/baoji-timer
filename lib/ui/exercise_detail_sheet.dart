import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import '../models/models.dart';
import '../presets/exercise_library.dart';
import '../presets/exercise_media.dart';
import '../presets/exercise_video.dart';
import 'theme.dart';

/// 动作解析弹层（2026-09-27 Arono 需求：图文并茂、训练中也能看）。
///
/// 内容 = 起止姿势示意图（free-exercise-db，Unlicense 公有领域）
/// + 动作要点（本项目中文原创）。训练中经由用户主动点按入口打开，
/// 与「直接输入重量」同口径——收起式信息、随时划掉、不打断计时，
/// 不违反训练中禁弹窗红线。
Future<void> showExerciseDetailSheet(
  BuildContext context, {
  required String name,
  ExerciseMeta? meta,
}) {
  final m = meta ?? libraryMetaByName(name);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          Text(exname(name),
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (m != null) ...[
            const SizedBox(height: 4),
            Text(
              tx(
                '主练 ${mname(m.muscles.main)}'
                '${m.muscles.secondary.isEmpty ? '' : ' · 兼练 ${m.muscles.secondary.map(mname).join('/')}'}'
                ' · ${m.isCompound ? '复合动作' : '单关节动作'}'
                '${m.gear.isEmpty ? '' : ' · ${gearname(m.gear)}'}',
                en: 'Main ${mname(m.muscles.main)}'
                    '${m.muscles.secondary.isEmpty ? '' : ' · Secondary ${m.muscles.secondary.map(mname).join('/')}'}'
                    ' · ${m.isCompound ? 'Compound' : 'Isolation'}'
                    '${m.gear.isEmpty ? '' : ' · ${gearname(m.gear)}'}',
              ),
              style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
          ],
          ...exerciseMediaSection(name, m),
          ...exerciseVideoSection(name),
        ],
      ),
    ),
  );
}

/// 示范视频段（2026-09-27，wger.de 社区 CC BY-SA 4.0）：
/// 无声短视频，点按播放/暂停，循环；无视频的动作不渲染本段。
List<Widget> exerciseVideoSection(String name) {
  final v = exerciseVideoOf(name);
  if (v == null) return const [];
  return [
    const SizedBox(height: 14),
    Text(tx('动作演示', en: 'Demo Video'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _DemoVideoPlayer(asset: v.file),
      ),
    ),
    const SizedBox(height: 4),
    Text(
      tx('视频来自 wger.de 社区（CC BY-SA 4.0，作者 ${v.author}）· 已转码为无声 480p',
          en: 'Video from the wger.de community (CC BY-SA 4.0, by ${v.author}) · re-encoded silent 480p'),
      style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
    ),
  ];
}

/// 内嵌视频播放器：asset 播放、静音循环、点按切换播放/暂停。
/// 播放器初始化失败（解码兼容等）时降级为一行提示，不阻塞弹层。
class _DemoVideoPlayer extends StatefulWidget {
  const _DemoVideoPlayer({required this.asset});

  final String asset;

  @override
  State<_DemoVideoPlayer> createState() => _DemoVideoPlayerState();
}

class _DemoVideoPlayerState extends State<_DemoVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.asset(widget.asset);
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      setState(() {});
      c.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null || !c.value.isInitialized) {
      return Container(
        color: AppTheme.cardHi,
        alignment: Alignment.center,
        child: _failed
            ? Text(tx('该设备无法播放此视频', en: 'This device cannot play this video'),
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12))
            : const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => c.value.isPlaying ? c.pause() : c.play());
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: VideoPlayer(c)),
          // 播放中不显示按钮；暂停时给个轻提示（无声视频，点画面即恢复）
          if (!c.value.isPlaying)
            const Icon(Icons.play_circle_outline,
                size: 44, color: Colors.white70),
        ],
      ),
    );
  }
}

/// 示意图 + 要点段（动作库详情弹层与训练中解析弹层共用）。
/// 图：0 = 起始姿势，1 = 结束姿势，横版照统一裁 4:3 圆角展示。
List<Widget> exerciseMediaSection(String name, ExerciseMeta? m) {
  final images = exerciseImageAssets(name);
  final cue = m?.cue ?? '';
  return [
    if (images.isNotEmpty) ...[
      const SizedBox(height: 14),
      Row(
        children: [
          for (var i = 0; i < images.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.asset(
                          images[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppTheme.cardHi,
                            alignment: Alignment.center,
                            child: Icon(Icons.image_not_supported_outlined,
                                size: 28, color: AppTheme.textDim),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i == 0
                          ? tx('起始姿势', en: 'Start')
                          : tx('结束姿势', en: 'End'),
                      style:
                          const TextStyle(color: AppTheme.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
    if (cue.isNotEmpty) ...[
      const SizedBox(height: 14),
      Text(tx('动作要点', en: 'Form Cues'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(cuen(name, cue),
          style: const TextStyle(fontSize: 14, height: 1.5)),
    ],
    if (images.isEmpty && cue.isEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          tx('这个动作（多为 AI 计划新增）还没有图文解析，可在动作库里换用内置动作获得解析。',
              en: 'No illustrated guide yet for this exercise (likely added by an AI plan) — swap to a built-in one in the library.'),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
        ),
      ),
  ];
}
