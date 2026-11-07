// l10n:ignore-file — PocketForge is an independent English-only product.
import 'dart:async';
import 'dart:convert';

import 'package:fa/sandbox/env_factory.dart';
import 'package:fa/sandbox/wasm_setup_stub.dart'
    if (dart.library.io) 'package:fa/sandbox/wasm_setup_io.dart';
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import '../prompts.g.dart';
import 'browser/game_preview.dart';
import 'pocketforge_model.dart';
import 'pocketforge_store.dart';

/// A write-only key settings surface; no plaintext-file fallback is permitted.
abstract interface class PocketForgeKeyVault {
  Future<bool> available();
  Future<String?> read();
  Future<void> save(String key);
  Future<void> delete();
}

final class _DeviceKeyVault implements PocketForgeKeyVault {
  static const account = 'POCKETFORGE_DEEPSEEK';
  final _keys = const KeychainStore();
  @override
  Future<bool> available() => _keys.isAvailable();
  @override
  Future<String?> read() async => (await _keys.readAll())[account];
  @override
  Future<void> save(String key) async {
    if (!await _keys.set(account, key)) {
      throw StateError('The device Keychain could not save this key.');
    }
  }

  @override
  Future<void> delete() async {
    if (!await _keys.delete(account)) {
      throw StateError('The device Keychain could not remove this key.');
    }
  }
}

final class PocketForgeSession extends PocketForgeModel {
  PocketForgeSession._(
    this.store,
    this._vault,
    this._streamOverride,
    this._runTimeout,
    this._promptOverride,
    this._starterOverride,
  );

  final PocketForgeStore store;
  final PocketForgeKeyVault _vault;
  final StreamFunction? _streamOverride;
  final Duration _runTimeout;
  final String? _promptOverride;
  final Map<String, String>? _starterOverride;
  late final GamePreviewController game;
  late Agent _agent;
  late Session _session;
  late JsonlSessionRepo _repo;
  void Function()? _unsubscribe;
  String _apiKey = '';
  String _model = 'deepseek-flash';
  int _maxRequests = 20;
  int _requests = 0;
  int _tools = 0;
  bool _secure = false;
  bool _running = false;
  bool _disposed = false;
  bool _agentReady = false;
  bool _stopped = false;
  String _status = 'Ready to build.';
  String? _error;
  String? _limitReason;
  List<String> _files = [];
  List<String> _checkpoints = [];
  final List<ForgeActivity> _activity = [];
  final List<FaChatMessage> _messages = [];

  static Future<PocketForgeSession> create({
    ExecutionEnv? baseEnv,
    StreamFunction? streamFunction,
    PocketForgeKeyVault? keyVault,
    GamePreviewController Function(ExecutionEnv env)? gameFactory,
    Duration runTimeout = const Duration(minutes: 5),
    String? systemPrompt,
    Map<String, String>? starterFiles,
    bool useNativeRuntime = true,
  }) async {
    if (baseEnv == null) {
      // Plugin-backed calls must follow WidgetsFlutterBinding initialization
      // in the entrypoint; wasm_run is linked statically on iOS.
      try {
        await setUpWasmRuntime();
      } on Object {
        /* factory reports fallback */
      }
    }
    final storage =
        baseEnv ??
        await PocketForgeStore.createDurableNativeStorage() ??
        await createPlatformEnv();
    final store = await PocketForgeStore.create(
      storage,
      useNativeRuntime: useNativeRuntime,
    );
    final result = PocketForgeSession._(
      store,
      keyVault ?? _DeviceKeyVault(),
      streamFunction,
      runTimeout,
      systemPrompt,
      starterFiles,
    );
    store.redactText = result._redact;
    result.game =
        gameFactory?.call(result.env) ??
        GamePreviewController(env: result.env, projectRoot: '/');
    result.game.onFocusRequest = () => result.onPreviewRequested?.call();
    try {
      await result._initialize();
    } on Object {
      result.dispose();
      rethrow;
    }
    return result;
  }

  @override
  ExecutionEnv get env => store.env;
  @override
  List<FaChatMessage> get messages => List.unmodifiable(_messages);
  @override
  List<ForgeActivity> get activity => List.unmodifiable(_activity);
  @override
  bool get isRunning => _running;
  @override
  String get status => _status;
  @override
  String? get error => _error;
  @override
  String get projectName => 'Untitled game';
  @override
  String get runtimeLabel => store.runtimeLabel;
  @override
  List<String> get files => List.unmodifiable(_files);
  @override
  String get modelId => _model;
  @override
  int get maxRequests => _maxRequests;
  @override
  bool get hasApiKey => _apiKey.isNotEmpty;
  @override
  bool get secureKeyStorage => _secure;
  @override
  List<String> get checkpoints => List.unmodifiable(_checkpoints);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _redact(String text) =>
      _apiKey.isEmpty ? text : text.replaceAll(_apiKey, '[API key redacted]');
  Message _redactMessage(Message message) => messageFromJson(
    jsonDecode(_redact(jsonEncode(message.toJson()))) as Map<String, dynamic>,
  );

  Future<void> _initialize() async {
    final settings = await store.readSettings();
    final savedModel = settings['model'];
    if (savedModel is String && savedModel.trim().isNotEmpty) {
      _model = savedModel;
    }
    final savedLimit = settings['maxRequests'];
    if (savedLimit is int) _maxRequests = savedLimit.clamp(1, 40);
    _secure = await _vault.available();
    if (_secure) _apiKey = await _vault.read() ?? '';
    if ((await store.files()).isEmpty) {
      final starters =
          _starterOverride ??
          {
            'index.html': await rootBundle.loadString(
              'assets/pocketforge/starter-index.html',
            ),
            'style.css': await rootBundle.loadString(
              'assets/pocketforge/starter-style.css',
            ),
            'game.js': await rootBundle.loadString(
              'assets/pocketforge/starter-game.js',
            ),
          };
      for (final entry in starters.entries) {
        (await store.backend.writeFile(entry.key, entry.value)).getOrThrow();
      }
      await store.flush();
    }
    _repo = JsonlSessionRepo(
      fs: store.storage,
      sessionsRoot: store.sessionsPath,
      persistTransform: _redactMessage,
    );
    final previous = await _repo.list(cwd: '/');
    if (previous.isEmpty) {
      _session = await _repo.create(
        const JsonlSessionCreateOptions(
          cwd: '/',
          metadata: {'agent': 'PocketForge'},
        ),
      );
    } else {
      _session = await _repo.open(previous.first);
    }
    await _buildAgent(await _session.buildContextMessages());
    await refreshFiles();
    _checkpoints = await store.checkpoints();
  }

  Future<void> _buildAgent(List<Message> history) async {
    _unsubscribe?.call();
    final profile = HostCapabilityProfile(
      name: 'pocketforge',
      states: {
        for (final capability in HostCapability.values)
          capability:
              {
                HostCapability.approvalGate,
                HostCapability.hostExtensionApi,
              }.contains(capability)
              ? CapabilityState.on
              : CapabilityState.off(
                  'Outside the first PocketForge game-workspace milestone.',
                ),
      },
    );
    final extension = HostExtension(
      name: 'pocketforge-game',
      tools: pocketGameTools(game),
      profileStates: {
        for (final name in builtInProfiles.keys)
          name:
              name == 'ios' ||
                  name == 'android' ||
                  name == 'macos' ||
                  name == 'web'
              ? CapabilityState.on
              : CapabilityState.off(
                  'This product preview is mounted only in supported Flutter browser hosts.',
                ),
        'pocketforge': CapabilityState.on,
      },
    );
    final wired = wireAgentCore(
      profile: profile,
      services: AgentCoreServices(
        baseEnv: env,
        extensions: [extension],
        shellAutoBackgroundAfter: Duration.zero,
      ),
    );
    final template = _promptOverride ?? pocketForgeGamePrompt;
    final stack = wired.buildAgentStack(
      spec: AgentWiringSpec(
        model: Model(
          id: _model,
          name: _model,
          api: 'openai-completions',
          provider: 'deepseek',
          baseUrl: 'https://api.deepseek.com',
          contextWindow: 65536,
          maxTokens: 8192,
          compat: const OpenAICompletionsCompat(
            maxTokensField: 'max_tokens',
            sendsToolStrict: false,
          ),
          input: const ['text'],
        ),
        systemPrompt: template,
        maxEmptyRetries: 0,
        emptyHiccupRetries: 0,
        contextWindowCap: 65536,
      ),
      streamFunction: _stream,
    );
    _agent = stack.agent..toolExecution = ToolExecutionMode.sequential;
    _agentReady = true;
    _agent.state.messages = history;
    _agent.beforeToolCall = (context, token) {
      token?.throwIfCancelled();
      if (_redact(jsonEncode(context.toolCall.arguments)) !=
          jsonEncode(context.toolCall.arguments)) {
        return const BeforeToolCallResult(
          block: true,
          reason: 'Provider credentials cannot be placed in tool arguments.',
        );
      }
      if (++_tools > 80) {
        _limitReason =
            'The 80-tool run limit was reached. Files are saved; send Continue.';
        _agent.abort();
        return BeforeToolCallResult(block: true, reason: _limitReason);
      }
      // This standalone product is intentionally scoped to its isolated
      // project and browser. No credentials or host files are mounted.
      if (context.toolCall.name == 'request_secret' ||
          context.toolCall.name == 'ask') {
        return const BeforeToolCallResult(
          block: true,
          reason:
              'Use the PocketForge Settings and prompt field. Credentials never belong in chat.',
        );
      }
      return null;
    };
    final approval = ApprovalManager(
      mode: ApprovalMode.yolo,
      overrides: {'bash': ApprovalPolicy.allow},
    );
    // Critical commands still deny by default without an interactive approval
    // surface. The ordinary workspace tools run within the isolated project.
    attachApproval(_agent, approval);
    final redactor = SecretRedactor.fromSecrets(
      _apiKey.isEmpty ? {} : {'POCKETFORGE_API_KEY': _apiKey},
    );
    attachSecretRedactor(_agent, redactor);
    _unsubscribe = _agent.subscribe(_onEvent);
    _rebuildMessages();
  }

  AssistantMessageEventStream _stream(
    Model model,
    Context context, {
    CancelToken? cancelToken,
  }) {
    if (++_requests > _maxRequests) {
      _limitReason =
          'The $_maxRequests-request run limit was reached. Files are saved; send Continue.';
      return _failureStream(model, _limitReason!, StopReason.aborted);
    }
    if (utf8
            .encode(
              jsonEncode(
                downgradeUnsupportedImages(
                  context.messages,
                  model,
                ).map((message) => message.toJson()).toList(),
              ),
            )
            .length >
        200000) {
      _limitReason =
          'Conversation reached the 200 KB context limit. Start a new conversation; project files are saved.';
      return _failureStream(model, _limitReason!, StopReason.aborted);
    }
    _status = 'Thinking · request $_requests/$_maxRequests';
    _notify();
    if (_streamOverride != null) {
      return _streamOverride(model, context, cancelToken: cancelToken);
    }
    return streamOpenAICompletions(
      model,
      context,
      OpenAICompletionsOptions(
        apiKey: _apiKey,
        maxTokens: 8192,
        cancelToken: cancelToken,
        onPayload: (payload, _) {
          payload['thinking'] = {'type': 'disabled'};
          return payload;
        },
      ),
    );
  }

  AssistantMessageEventStream _failureStream(
    Model model,
    String text,
    StopReason reason,
  ) {
    final message = AssistantMessage(
      content: const [],
      api: model.api,
      provider: model.provider,
      model: model.id,
      usage: Usage.zero,
      stopReason: reason,
      errorMessage: text,
      timestamp: DateTime.now(),
    );
    return AssistantMessageEventStream()
      ..push(ErrorEvent(reason: reason, error: message))
      ..end();
  }

  Future<void> _onEvent(AgentEvent event, CancelToken token) async {
    if (_disposed) return;
    if (event is MessageEndEvent) {
      await _session.appendMessage(_redactMessage(event.message));
      if (event.message case AssistantMessage(
        stopReason: StopReason.error,
        :final errorMessage,
      )) {
        _error = _redact(errorMessage ?? 'The provider request failed.');
      }
    }
    if (event is ToolExecutionStartEvent) {
      _status = 'Using ${event.toolName}';
      _activity.add(
        ForgeActivity(
          label: event.toolName,
          detail: _redact(
            jsonEncode(event.args),
          ).substring(0, _redact(jsonEncode(event.args)).length.clamp(0, 350)),
        ),
      );
    }
    if (event is ToolExecutionEndEvent) {
      final text = event.result.content
          .whereType<TextContent>()
          .map((block) => block.text)
          .join('\n');
      _activity.add(
        ForgeActivity(
          label: event.toolName,
          detail: _redact(
            text,
          ).substring(0, _redact(text).length.clamp(0, 1200)),
          failed: event.isError,
        ),
      );
      if (_activity.length > 120) {
        _activity.removeRange(0, _activity.length - 120);
      }
      await refreshFiles();
      _checkpoints = await store.checkpoints();
    }
    _rebuildMessages();
    _notify();
  }

  void _rebuildMessages() {
    _messages.clear();
    final messages = [..._agent.state.messages];
    final partial = _agent.state.streamingMessage;
    if (partial != null) messages.add(partial);
    for (final message in messages) {
      final Object content;
      final String role;
      if (message is UserMessage) {
        content = message.content;
        role = 'user';
      } else if (message is AssistantMessage) {
        content = message.content;
        role = 'assistant';
      } else if (message is ToolResultMessage) {
        content = message.content;
        role = 'tool';
      } else {
        continue;
      }
      final text = content is String
          ? content
          : (content as List<ContentBlock>)
                .whereType<TextContent>()
                .map((block) => block.text)
                .join('\n');
      if (text.isEmpty) continue;
      _messages.add(
        FaChatMessage(
          role: role,
          content: _redact(text),
          toolName: message is ToolResultMessage ? message.toolName : null,
          isError: message is ToolResultMessage && message.isError,
        ),
      );
    }
  }

  @override
  Future<void> send(String prompt) async {
    if (_running || prompt.trim().isEmpty) return;
    if (_apiKey.isEmpty && _streamOverride == null) {
      _error = 'Add your DeepSeek API key in Settings first.';
      _notify();
      return;
    }
    if (utf8.encode(prompt).length > 32000) {
      _error = 'Keep prompts below 32 KB.';
      _notify();
      return;
    }
    _running = true;
    _stopped = false;
    _error = null;
    _limitReason = null;
    _requests = 0;
    _tools = 0;
    _status = 'Preparing project checkpoint…';
    _notify();
    Timer? deadline;
    try {
      await store.checkpoint();
      if (_stopped || _disposed) {
        _status = 'Stopped. Files are saved.';
        return;
      }
      deadline = Timer(_runTimeout, () {
        _limitReason =
            'The run reached its time limit. Files are saved; send Continue.';
        stop();
      });
      await _agent.prompt(_redact(prompt.trim()));
      await _agent.waitForIdle();
      await store.flush();
      _status =
          _limitReason ??
          (_stopped
              ? 'Stopped. Files are saved.'
              : (_error == null ? 'Ready.' : 'Run failed.'));
    } on Object catch (error) {
      _error = _redact('$error');
      _status = 'Run failed.';
    } finally {
      deadline?.cancel();
      _running = false;
      await refreshFiles();
      _checkpoints = await store.checkpoints();
      _rebuildMessages();
      _notify();
    }
  }

  @override
  void stop() {
    _stopped = true;
    if (_agentReady) _agent.abort();
    game.cancel();
    _status = 'Stopping…';
    _notify();
  }

  @override
  Future<void> saveSettings({
    required String modelId,
    String? apiKey,
    required int maxRequests,
  }) async {
    if (_running) return;
    try {
      final model = modelId.trim();
      if (model.isEmpty ||
          model.length > 150 ||
          model.contains(RegExp(r'[\r\n]'))) {
        throw StateError('Enter a valid DeepSeek model ID.');
      }
      final key = apiKey?.trim();
      if (key != null && key.isNotEmpty) {
        if (key.contains(RegExp(r'[\r\n]'))) {
          throw StateError('Enter a single API key without line breaks.');
        }
        if (_secure) await _vault.save(key);
        _apiKey = key;
      }
      _model = model;
      _maxRequests = maxRequests.clamp(1, 40);
      await store.writeSettings({'model': _model, 'maxRequests': _maxRequests});
      await _buildAgent(_agent.state.messages);
      _status = _secure
          ? 'Settings saved securely.'
          : 'Settings saved. API key is held only for this session.';
      _error = null;
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  Future<void> removeApiKey() async {
    if (_running) return;
    try {
      if (_secure) await _vault.delete();
      _apiKey = '';
      _error = null;
      _status = 'API key removed.';
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  Future<String> readFile(String path) async =>
      (await env.readTextFile(path)).getOrThrow();
  @override
  Future<void> writeFile(String path, String content) async {
    if (_running) return;
    try {
      (await env.writeFile(path, content)).getOrThrow();
      await refreshFiles();
      _checkpoints = await store.checkpoints();
      _error = null;
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  Future<void> refreshFiles() async {
    try {
      _files = await store.files();
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  Future<void> runPreview() async {
    if (_running) return;
    try {
      await game.preview();
      _status = game.status;
      _error = null;
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  Future<void> resetConversation() async {
    if (_running) return;
    _session = await _repo.create(
      const JsonlSessionCreateOptions(
        cwd: '/',
        metadata: {'agent': 'PocketForge'},
      ),
    );
    await _buildAgent([]);
    _activity.clear();
    _error = null;
    _status = 'New conversation.';
    _notify();
  }

  @override
  Future<void> createCheckpoint() async {
    if (_running) return;
    try {
      await store.checkpoint();
      _checkpoints = await store.checkpoints();
      _status = 'Checkpoint saved.';
      _error = null;
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  Future<void> restoreCheckpoint(String id) async {
    if (_running) return;
    try {
      game.cancel();
      await store.restore(id);
      await refreshFiles();
      _checkpoints = await store.checkpoints();
      _status = 'Project files restored. Conversation kept.';
      _error = null;
    } on Object catch (error) {
      _error = _redact('$error');
    }
    _notify();
  }

  @override
  void clearError() {
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _unsubscribe?.call();
    if (_agentReady) _agent.abort();
    game.dispose();
    store.dispose();
    super.dispose();
  }
}
