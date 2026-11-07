// l10n:ignore-file — English-only PocketForge product, independent of Fa's app.
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';

import '../pocketforge_model.dart';
import 'pocketforge_agent_pane.dart';
import 'pocketforge_files_pane.dart';
import 'pocketforge_settings.dart';
import 'pocketforge_theme.dart';

class PocketForgeWorkbench extends StatefulWidget {
  const PocketForgeWorkbench({
    super.key,
    required this.session,
    required this.previewBuilder,
  });
  final PocketForgeModel session;
  final WidgetBuilder previewBuilder;

  @override
  State<PocketForgeWorkbench> createState() => _PocketForgeWorkbenchState();
}

class _PocketForgeWorkbenchState extends State<PocketForgeWorkbench> {
  int _section = 0;
  int _sideSection = 2;
  final _filesKey = GlobalKey<PocketForgeFilesPaneState>();
  late final Widget _preview = Builder(builder: widget.previewBuilder);
  ForgeActivity? _lastActivity;
  VoidCallback? _previousPreviewHandler;
  late final VoidCallback _focusCallback = _requestPreviewFocus;

  @override
  void initState() {
    super.initState();
    _lastActivity = widget.session.activity.lastOrNull;
    widget.session.addListener(_followGameTools);
    _attachFocus(widget.session);
  }

  @override
  void didUpdateWidget(covariant PocketForgeWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_followGameTools);
      _detachFocus(oldWidget.session);
      _lastActivity = widget.session.activity.lastOrNull;
      widget.session.addListener(_followGameTools);
      _attachFocus(widget.session);
    }
  }

  void _followGameTools() {
    final activity = widget.session.activity;
    final newActivity = !identical(activity.lastOrNull, _lastActivity);
    _lastActivity = activity.lastOrNull;
    if (mounted &&
        newActivity &&
        widget.session.isRunning &&
        activity.last.label.toLowerCase().contains('game_')) {
      _requestPreviewFocus();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_followGameTools);
    _detachFocus(widget.session);
    super.dispose();
  }

  void _attachFocus(PocketForgeModel session) {
    _previousPreviewHandler = session.onPreviewRequested;
    session.onPreviewRequested = _focusCallback;
  }

  void _detachFocus(PocketForgeModel session) {
    if (session.onPreviewRequested == _focusCallback) {
      session.onPreviewRequested = _previousPreviewHandler;
    }
  }

  void _requestPreviewFocus() {
    if (!mounted || (_filesKey.currentState?.hasUnsavedChanges ?? false)) {
      return;
    }
    setState(() {
      _section = 2;
      _sideSection = 2;
    });
  }

  Future<bool> _prepareToLeaveFiles() async =>
      await _filesKey.currentState?.prepareToLeave() ?? true;

  Future<void> _select(int section) async {
    if (_section == section) return;
    if (!await _prepareToLeaveFiles() || !mounted) return;
    setState(() {
      _section = section;
      if (section != 0) _sideSection = section;
    });
  }

  Future<void> _run() async {
    if (widget.session.isRunning || !await _prepareToLeaveFiles() || !mounted) {
      return;
    }
    setState(() {
      _section = 2;
      _sideSection = 2;
    });
    await widget.session.runPreview();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new conversation?'),
        content: const Text(
          'The current conversation will be cleared. Your project files stay in the workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('New conversation'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.session.resetConversation();
  }

  Future<void> _checkpoints() async {
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Project checkpoints',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Restore a saved version of your files. Your current files are checkpointed first.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (widget.session.checkpoints.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No checkpoints yet. Save one from the project menu.',
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final id in widget.session.checkpoints)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded, size: 18),
                      title: Text(id, style: forgeMono(context, size: 11)),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                      ),
                      onTap: () => Navigator.pop(context, id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted && await _prepareToLeaveFiles()) {
      await widget.session.restoreCheckpoint(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FahColors.of(context);
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => Scaffold(
        backgroundColor: colors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              if (widget.session.error != null)
                Container(
                  width: double.infinity,
                  color: colors.errorContainer,
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: colors.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.session.error!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: widget.session.clearError,
                        tooltip: 'Dismiss error',
                        icon: const Icon(Icons.close_rounded, size: 16),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1050;
                    final agent = PocketForgeAgentPane(
                      session: widget.session,
                      beforeSend: _prepareToLeaveFiles,
                      onRunProject: _run,
                      onOpenFiles: () => _select(1),
                    );
                    final files = PocketForgeFilesPane(
                      key: _filesKey,
                      session: widget.session,
                    );
                    final preview = _previewPane(context);
                    if (wide) {
                      return Row(
                        children: [
                          SizedBox(width: 430, child: agent),
                          VerticalDivider(width: 1, color: colors.border),
                          Expanded(
                            child: Column(
                              children: [
                                _sideTabs(context),
                                Expanded(
                                  child: IndexedStack(
                                    index: _sideSection == 1 ? 0 : 1,
                                    children: [files, preview],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(
                          child: IndexedStack(
                            index: _section,
                            children: [agent, files, preview],
                          ),
                        ),
                        _navigation(context),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = FahColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      decoration: BoxDecoration(
        color: colors.bgAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Icon(Icons.code_rounded, size: 22, color: colors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'pocketforge',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      letterSpacing: -0.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.session.projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: forgeMono(context, size: 9),
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth >= 570)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.memory_rounded, size: 13, color: colors.dim),
                    const SizedBox(width: 6),
                    Text(
                      widget.session.runtimeLabel,
                      style: forgeMono(context, size: 10),
                    ),
                  ],
                ),
              ),
            if (widget.session.isRunning)
              TextButton.icon(
                key: const ValueKey('forge-global-stop'),
                onPressed: widget.session.stop,
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: const Text('Stop'),
              )
            else
              IconButton(
                onPressed: _run,
                tooltip: 'Run project',
                icon: Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: colors.teal,
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'Project actions',
              enabled: !widget.session.isRunning,
              onSelected: (value) async {
                if (value == 'new') await _reset();
                if (value == 'checkpoint') {
                  await widget.session.createCheckpoint();
                }
                if (value == 'restore') await _checkpoints();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'checkpoint',
                  child: Text('Save checkpoint'),
                ),
                const PopupMenuItem(
                  value: 'restore',
                  child: Text('Restore checkpoint'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'new',
                  child: Text('New conversation'),
                ),
              ],
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
            ),
            IconButton(
              onPressed: widget.session.isRunning
                  ? null
                  : () => showPocketForgeSettings(context, widget.session),
              tooltip: 'Model settings',
              icon: const Icon(Icons.tune_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideTabs(BuildContext context) {
    final colors = FahColors.of(context);
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          _navButton(
            context,
            2,
            Icons.play_circle_outline_rounded,
            'Preview',
            _sideSection == 2,
          ),
          _navButton(
            context,
            1,
            Icons.folder_outlined,
            'Files',
            _sideSection == 1,
          ),
          const Spacer(),
          Text(widget.session.runtimeLabel, style: forgeMono(context, size: 9)),
          const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _navigation(BuildContext context) {
    final colors = FahColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.bgAlt,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: Row(
        children: [
          Expanded(
            child: _navButton(
              context,
              0,
              Icons.chat_bubble_outline_rounded,
              'Agent',
              _section == 0,
            ),
          ),
          Expanded(
            child: _navButton(
              context,
              1,
              Icons.folder_outlined,
              'Files',
              _section == 1,
            ),
          ),
          Expanded(
            child: _navButton(
              context,
              2,
              Icons.play_circle_outline_rounded,
              'Preview',
              _section == 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(
    BuildContext context,
    int section,
    IconData icon,
    String label,
    bool selected,
  ) {
    final colors = FahColors.of(context);
    return TextButton(
      onPressed: () => _select(section),
      style: TextButton.styleFrom(
        foregroundColor: selected ? colors.teal : colors.dim,
        backgroundColor: selected ? colors.panel : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? colors.teal : colors.dim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPane(BuildContext context) {
    final colors = FahColors.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colors.bgAlt,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.web_asset_outlined, size: 14, color: colors.dim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.session.projectName,
                  style: forgeMono(context, size: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: widget.session.isRunning ? null : _run,
                tooltip: 'Reload preview',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, size: 17),
              ),
            ],
          ),
        ),
        Expanded(child: _preview),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colors.bgAlt,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Text(
            widget.session.isRunning
                ? widget.session.status
                : widget.session.runtimeLabel,
            style: forgeMono(context, size: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
