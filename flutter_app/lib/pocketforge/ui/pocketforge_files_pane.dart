// l10n:ignore-file — English-only PocketForge product, independent of Fa's app.
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';

import '../pocketforge_model.dart';
import 'pocketforge_theme.dart';

class PocketForgeFilesPane extends StatefulWidget {
  const PocketForgeFilesPane({super.key, required this.session});
  final PocketForgeModel session;

  @override
  State<PocketForgeFilesPane> createState() => PocketForgeFilesPaneState();
}

class PocketForgeFilesPaneState extends State<PocketForgeFilesPane> {
  final _editor = TextEditingController();
  String? _selected;
  String _saved = '';
  String? _error;
  bool _loading = false;
  bool _refreshing = false;
  bool get _dirty => _selected != null && _saved != _editor.text;
  bool get hasUnsavedChanges => _dirty;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_refreshCleanFile);
  }

  @override
  void didUpdateWidget(covariant PocketForgeFilesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_refreshCleanFile);
      widget.session.addListener(_refreshCleanFile);
      _selected = null;
      _saved = '';
      _editor.clear();
    }
  }

  Future<void> _refreshCleanFile() async {
    final path = _selected;
    if (!mounted ||
        path == null ||
        _dirty ||
        _loading ||
        _refreshing ||
        widget.session.isRunning) {
      return;
    }
    if (!widget.session.files.contains(path)) {
      setState(() {
        _selected = null;
        _saved = '';
        _editor.clear();
      });
      return;
    }
    _refreshing = true;
    try {
      final content = await widget.session.readFile(path);
      if (mounted &&
          path == _selected &&
          !_dirty &&
          !widget.session.isRunning &&
          content != _saved) {
        setState(() {
          _editor.text = content;
          _saved = content;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_refreshCleanFile);
    _editor.dispose();
    super.dispose();
  }

  Future<bool> _canLeave() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard file edits?'),
        content: const Text(
          'Save your current file first, or discard these edits to open another file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  /// Used before an agent run or changing panels so edits cannot disappear silently.
  Future<bool> prepareToLeave() async {
    if (!await _canLeave()) return false;
    if (_dirty && mounted) setState(() => _editor.text = _saved);
    return true;
  }

  Future<void> _open(String path) async {
    if (_loading ||
        widget.session.isRunning ||
        path == _selected ||
        !await _canLeave()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await widget.session.readFile(path);
      if (mounted) {
        setState(() {
          _selected = path;
          _editor.text = content;
          _saved = content;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_dirty || widget.session.isRunning || _selected == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = _editor.text;
      await widget.session.writeFile(_selected!, content);
      if (mounted && widget.session.error == null) {
        setState(() => _saved = content);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FahColors.of(context);
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Text(
                  'FILES',
                  style: forgeMono(
                    context,
                    size: 10,
                  ).copyWith(letterSpacing: 1.5),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.session.files.length}',
                  style: forgeMono(context, size: 10),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.session.isRunning || _loading
                      ? null
                      : widget.session.refreshFiles,
                  tooltip: 'Refresh files',
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
                TextButton.icon(
                  onPressed: !_dirty || _loading || widget.session.isRunning
                      ? null
                      : _save,
                  icon: const Icon(Icons.save_outlined, size: 15),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 650;
                final fileList = _fileList(context);
                return wide
                    ? Row(
                        children: [
                          SizedBox(width: 205, child: fileList),
                          VerticalDivider(width: 1, color: colors.border),
                          Expanded(child: _editorPane(context)),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: _selected == null ? 225 : 135,
                            child: fileList,
                          ),
                          Divider(height: 1, color: colors.border),
                          Expanded(child: _editorPane(context)),
                        ],
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileList(BuildContext context) {
    final colors = FahColors.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.session.files.length,
      itemBuilder: (context, index) {
        final path = widget.session.files[index];
        final selected = _selected == path;
        return ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: colors.panelAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(
            path.endsWith('.js')
                ? Icons.javascript_rounded
                : path.endsWith('.html')
                ? Icons.code_rounded
                : Icons.description_outlined,
            size: 18,
            color: selected ? colors.teal : colors.dim,
          ),
          minLeadingWidth: 16,
          title: Text(
            path,
            maxLines: 2,
            style: forgeMono(
              context,
              color: selected ? colors.text : colors.dim,
              size: 11,
            ),
          ),
          enabled: !_loading && !widget.session.isRunning,
          onTap: () => _open(path),
        );
      },
    );
  }

  Widget _editorPane(BuildContext context) {
    final colors = FahColors.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_selected == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.data_object_rounded,
                color: colors.borderBright,
                size: 38,
              ),
              const SizedBox(height: 14),
              Text(
                'A place for your ideas to become code.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.dim),
              ),
              const SizedBox(height: 8),
              Text(
                'Open a file to edit it.',
                style: forgeMono(context, size: 10),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_selected${_dirty ? ' • edited' : ''}',
                  style: forgeMono(context, color: colors.text, size: 11),
                ),
              ),
              if (_dirty)
                TextButton(
                  onPressed: widget.session.isRunning
                      ? null
                      : () => setState(() => _editor.text = _saved),
                  child: const Text('Discard'),
                ),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('forge-file-editor'),
            controller: _editor,
            expands: true,
            minLines: null,
            maxLines: null,
            enabled: !widget.session.isRunning,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: forgeMono(context, color: colors.text, size: 12),
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }
}
