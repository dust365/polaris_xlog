import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:polaris_xlog/polaris_xlog.dart';

import 'developer_log_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One encrypted file per day: <prefix>_YYYYMMDD.xlog, kept for 7 days of cache.
  await XLog.init(
    level: XLogLevel.verbose,
    namePrefix: 'mlog',
    cacheDays: 7,
    consoleLogOpen: kDebugMode,
  );
  XLog.i('App', 'MLog example started');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MLog Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MLog')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => XLog.i('Demo', 'info tapped at ${DateTime.now()}'),
              child: const Text('Write INFO'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => XLog.w('Demo', 'warning tapped'),
              child: const Text('Write WARN'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => XLog.e('Demo', 'error tapped',
                  error: Exception('boom'), stackTrace: StackTrace.current),
              child: const Text('Write ERROR'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.developer_mode),
              label: const Text('Developer Mode'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeveloperLogPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
