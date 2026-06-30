import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';
import 'state/session.dart';
import 'theme/app_theme.dart';

void main() => runApp(const DartstreamApp());

class DartstreamApp extends StatefulWidget {
  const DartstreamApp({super.key});

  @override
  State<DartstreamApp> createState() => _DartstreamAppState();
}

class _DartstreamAppState extends State<DartstreamApp> {
  final Session _session = Session();

  @override
  void initState() {
    super.initState();
    _session.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartStream E2E',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: _session.status == SessionStatus.signedIn
          ? ShellScreen(session: _session)
          : LoginScreen(session: _session),
    );
  }
}
