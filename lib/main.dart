import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.init();

  final appState = AppState();
  await appState.load();

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const PartBoxApp(),
    ),
  );
}
