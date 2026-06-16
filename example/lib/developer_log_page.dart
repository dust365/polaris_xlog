import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xlog_plugin/xlog_plugin.dart';

import 'log_viewer_page.dart';

/// Developer-mode screen: lists every daily log file and lets the user
/// tap "Upload" to POST that day's `.xlog` to the backend.
class DeveloperLogPage extends StatefulWidget {
  const DeveloperLogPage({super.key});

  // TODO: point this at your real log-collection endpoint.
  static const String uploadUrl = 'https://logs.youfi.com/api/v1/upload';

  @override
  State<DeveloperLogPage> createState() => _DeveloperLogPageState();
}

class _DeveloperLogPageState extends State<DeveloperLogPage> {
  late Future<List<XLogFile>> _filesFuture;
  String? _uploadingPath;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    // Flush so today's buffered logs are on disk before we list them.
    _filesFuture = XLog.flush().then((_) => XLog.listLogFiles());
    setState(() {});
  }

  Future<void> _upload(XLogFile file) async {
    // The plugin ships no HTTP client; uploading is the app's job. This example
    // uses package:http — flush first so today's buffer is on disk.
    final platform = Theme.of(context).platform.name;
    setState(() => _uploadingPath = file.path);
    try {
      await XLog.flush(sync: true);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(DeveloperLogPage.uploadUrl),
      )
        ..fields['userId'] = 'huichen@youfi.com'
        ..fields['logDate'] = file.date.toIso8601String().split('T').first
        ..fields['platform'] = platform
        // ..headers['Authorization'] = 'Bearer <token>'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      _snack(ok
          ? 'Uploaded ${file.name} (${response.statusCode})'
          : 'Failed: ${response.statusCode} $body');
    } catch (e) {
      XLog.e('Upload', 'failed for ${file.name}', error: e);
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _uploadingPath = null);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Mode · Logs'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<List<XLogFile>>(
        future: _filesFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snap.data ?? [];
          if (files.isEmpty) {
            return const Center(child: Text('No log files yet.'));
          }
          return ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final f = files[i];
              final d = f.date;
              final dateStr =
                  '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              final uploading = _uploadingPath == f.path;
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(dateStr),
                subtitle: Text('${f.name} · ${_fmtSize(f.sizeBytes)}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LogViewerPage(file: f)),
                ),
                trailing: uploading
                    ? const SizedBox(
                        width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'View',
                            icon: const Icon(Icons.visibility_outlined),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => LogViewerPage(file: f)),
                            ),
                          ),
                          FilledButton(
                            onPressed: _uploadingPath == null ? () => _upload(f) : null,
                            child: const Text('Upload'),
                          ),
                        ],
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
