import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class PartBoxApp extends StatelessWidget {
  const PartBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return MaterialApp(
      title: '元件盒',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: appState.themeMode,
      scrollBehavior: const AppScrollBehavior(),
      home: const HomePage(),
    );
  }
}
