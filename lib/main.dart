import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app.dart';
import 'ui/onboarding_page.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = AppContainer(prefs: prefs);
  await container.init();
  runApp(BaojiApp(
      container: container,
      onboarded: prefs.getBool('onboarded') == true));
}

class BaojiApp extends StatelessWidget {
  const BaojiApp({super.key, required this.container, required this.onboarded});

  final AppContainer container;
  final bool onboarded;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      container: container,
      child: MaterialApp(
        title: '薄肌训练计时器',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: onboarded ? const HomeShell() : const OnboardingPage(),
      ),
    );
  }
}
