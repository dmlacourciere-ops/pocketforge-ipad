// l10n:ignore-file — English-only PocketForge product, independent of Fa's app.
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';

import '../pocketforge_model.dart';
import 'pocketforge_settings.dart';
import 'pocketforge_theme.dart';

class PocketForgeAgentPane extends StatefulWidget {
  const PocketForgeAgentPane({
    super.key,
    required this.session,
    this.beforeSend,
    this.onRunProject,
    this.onOpenFiles,
  });
  final PocketForgeModel session;
  final Future<bool> Function()? beforeSend;
  final VoidCallback? onRunProject;
  final VoidCallback? onOpenFiles;

  @override
  State<PocketForgeAgentPane> createState() => _PocketForgeAgentPaneState();
}

class _PocketForgeAgentPaneState extends State<PocketForgeAgentPane> {
  final _prompt = TextEditingController();
  final _scroll = ScrollController();
  late SandboxImageResolver _images = SandboxImageResolver(widget.session.env);
  bool _activityExpanded = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant PocketForgeAgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_changed);
      widget.session.addListener(_changed);
      _images = SandboxImageResolver(widget.session.env);
    }
  }

  void _changed() {
    if (!mounted || !_scroll.hasClients) return;
    final nearEnd = _scroll.position.maxScrollExtent - _scroll.offset < 120;
    if (nearEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || widget.session.isRunning) return;
    if (!widget.session.hasApiKey) {
      await showPocketForgeSettings(context, widget.session);
      return;
    }
    if (widget.beforeSend != null && !await widget.beforeSend!()) return;
    _prompt.clear();
    await widget.session.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FahColors.of(context);
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.session.isRunning ? colors.teal : colors.dim,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  'AGENT',
                  style: forgeMono(
                    context,
                    size: 10,
                  ).copyWith(letterSpacing: 1.5),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    widget.session.modelId,
                    overflow: TextOverflow.ellipsis,
                    style: forgeMono(context, size: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.session.messages.isEmpty
                ? _welcome(context)
                : ListView.builder(
                    key: const PageStorageKey('pocketforge-transcript'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                    itemCount: widget.session.messages.length,
                    itemBuilder: (context, index) => ChatMessageTile(
                      message: widget.session.messages[index],
                      images: _images,
                      compact: true,
                      messageFontSize: 13,
                      thinkingLive: false,
                      avatarBuilder: (context, role) => role == 'assistant'
                          ? Icon(
                              Icons.code_rounded,
                              size: 18,
                              color: FahColors.of(context).teal,
                            )
                          : null,
                    ),
                  ),
          ),
          if (widget.session.activity.isNotEmpty) _activity(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
            child: Row(
              children: [
                Icon(
                  widget.session.isRunning
                      ? Icons.more_horiz_rounded
                      : Icons.circle_outlined,
                  size: 12,
                  color: colors.dim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.session.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: forgeMono(context, size: 10),
                  ),
                ),
              ],
            ),
          ),
          _composer(context),
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final colors = FahColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.panelAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Icon(Icons.code_rounded, size: 22, color: colors.teal),
          ),
          const SizedBox(height: 28),
          Text(
            'What are we making?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.7,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Describe an app or a game. Your agent can work on its files and run it in the preview.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.dim, height: 1.6),
          ),
          const SizedBox(height: 28),
          _suggestion(context, 'Run the starter game', widget.onRunProject),
          const SizedBox(height: 10),
          _suggestion(context, 'Explore the workspace', widget.onOpenFiles),
          if (!widget.session.hasApiKey)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: TextButton.icon(
                onPressed: () =>
                    showPocketForgeSettings(context, widget.session),
                icon: const Icon(Icons.key_rounded, size: 16),
                label: const Text('Connect your model'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _suggestion(BuildContext context, String label, VoidCallback? action) {
    final colors = FahColors.of(context);
    return InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.text),
              ),
            ),
            Icon(Icons.north_west_rounded, size: 14, color: colors.dim),
          ],
        ),
      ),
    );
  }

  Widget _activity(BuildContext context) {
    final colors = FahColors.of(context);
    final activity = widget.session.activity;
    final visible = _activityExpanded
        ? activity.reversed.take(5).toList()
        : [activity.last];
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 2),
      decoration: BoxDecoration(
        color: colors.bgAlt,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _activityExpanded = !_activityExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
              child: Row(
                children: [
                  Icon(Icons.bolt_outlined, size: 13, color: colors.dim),
                  const SizedBox(width: 7),
                  Text('Tool activity', style: forgeMono(context, size: 10)),
                  const Spacer(),
                  Text(
                    '${activity.length}',
                    style: forgeMono(context, size: 10),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _activityExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: colors.dim,
                  ),
                ],
              ),
            ),
          ),
          for (final event in visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    event.failed
                        ? Icons.error_outline
                        : Icons.subdirectory_arrow_right_rounded,
                    size: 13,
                    color: event.failed ? colors.error : colors.dim,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.label,
                          style: forgeMono(
                            context,
                            color: event.failed ? colors.error : colors.text,
                            size: 10,
                          ),
                        ),
                        Text(
                          event.detail,
                          maxLines: _activityExpanded ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: forgeMono(context, size: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final colors = FahColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
            decoration: BoxDecoration(
              color: colors.panel,
              border: Border.all(color: colors.borderBright),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('forge-prompt'),
                    controller: _prompt,
                    minLines: 1,
                    maxLines: 5,
                    enabled: !widget.session.isRunning,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(() {}),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Ask your agent…',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: ValueKey(
                    widget.session.isRunning ? 'forge-stop' : 'forge-send',
                  ),
                  onPressed: widget.session.isRunning
                      ? widget.session.stop
                      : _prompt.text.trim().isEmpty
                      ? null
                      : _send,
                  tooltip: widget.session.isRunning
                      ? 'Stop agent'
                      : 'Send message',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(38, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon: Icon(
                    widget.session.isRunning
                        ? Icons.stop_rounded
                        : Icons.arrow_upward_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 11, color: colors.dim),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Workspace files only',
                  style: forgeMono(context, size: 9),
                ),
              ),
              Text('DeepSeek', style: forgeMono(context, size: 9)),
            ],
          ),
        ],
      ),
    );
  }
}
