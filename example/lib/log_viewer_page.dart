import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xlog_plugin/xlog_plugin.dart';

/// Decodes one `.xlog` file on-device and shows it as searchable, color-coded
/// text. Demonstrates `XLog.decodeLogFile` — no backend needed.
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key, required this.file});

  final XLogFile file;

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  late Future<List<String>> _linesFuture;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _linesFuture = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<String>> _load() async {
    final text = await XLog.decodeLogFile(widget.file.path);
    return const LineSplitter().convert(text);
  }

  Color? _colorFor(String line, ColorScheme cs) {
    if (line.startsWith('[E') || line.startsWith('[F')) return cs.error;
    if (line.startsWith('[W')) return Colors.orange.shade800;
    if (line.startsWith('[I')) return cs.primary;
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final lines = await _linesFuture;
              await Clipboard.setData(ClipboardData(text: lines.join('\n')));
              if (!mounted) return;
              messenger.showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')));
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filter lines…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                filled: true,
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<String>>(
        future: _linesFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final err = snap.error;
            final msg = err is XLogDecodeFileTooLargeException
                ? err.toString()
                : 'Decode failed: $err';
            return Center(child: Text(msg));
          }
          final all = snap.data ?? const [];
          final lines = _query.isEmpty
              ? all
              : all.where((l) => l.toLowerCase().contains(_query)).toList();
          if (lines.isEmpty) {
            return const Center(child: Text('No matching lines.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final line = lines[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: SelectableText(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                    color: _colorFor(line, cs),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
