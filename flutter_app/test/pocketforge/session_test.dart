import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fa/pocketforge/browser/game_preview.dart';
import 'package:fa/pocketforge/browser/game_preview_backend.dart';
import 'package:fa/pocketforge/pocketforge_session.dart';
import 'package:fa/pocketforge/pocketforge_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

final class _Vault implements PocketForgeKeyVault {
  _Vault({this.secure = false});
  final bool secure;
  String? value;
  @override
  Future<bool> available() async => secure;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> save(String key) async {
    value = key;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

/// The WebKit boundary is mocked here; the real Fa loop, tool registry,
/// project filesystem, bundler, checkpoints and JSONL persistence are exercised.
final class _Browser extends GamePreviewBackend {
  _Browser({this.screenshotBytes = 0});
  final int screenshotBytes;
  String html = '';
  int loads = 0;
  int cancellations = 0;
  @override
  bool get attached => true;
  @override
  bool get isLoading => false;
  @override
  String get status => 'Mock page loaded';
  @override
  Future<void> load(String value) async {
    html = value;
    loads++;
  }

  @override
  Future<Object?> invoke(String method, Map<String, Object?> payload) async {
    if (method == 'read') return {'title': 'Test game', 'console': <String>[]};
    if (method == 'test') {
      return {
        'checks': [
          {
            'passed': html.contains('window.__score=1;'),
            'message': 'score starts at 1',
          },
        ],
      };
    }
    throw StateError('Unexpected browser operation $method');
  }

  @override
  Future<Uint8List> screenshot() async => Uint8List(screenshotBytes);
  @override
  void cancel() {
    cancellations++;
  }

  @override
  Widget buildView() => const SizedBox();
}

const _starter = {
  'index.html':
      '<!doctype html><title>Test game</title><script src="game.js"></script>',
  'game.js': 'window.__score=0;',
};

AssistantMessageEventStream _reply(Model model, List<ContentBlock> blocks) {
  final reason = blocks.any((block) => block is ToolCall)
      ? StopReason.toolUse
      : StopReason.stop;
  final message = AssistantMessage(
    content: blocks,
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: Usage.zero,
    stopReason: reason,
    timestamp: DateTime.now(),
  );
  return AssistantMessageEventStream()
    ..push(DoneEvent(reason: reason, message: message))
    ..end();
}

ToolCall _call(int id, String name, Map<String, dynamic> arguments) =>
    ToolCall(id: 'call-$id', name: name, arguments: arguments);

Future<PocketForgeSession> _create(
  ExecutionEnv storage,
  StreamFunction stream, {
  PocketForgeKeyVault? vault,
  _Browser? browser,
  Duration timeout = const Duration(minutes: 5),
}) => PocketForgeSession.create(
  baseEnv: storage,
  useNativeRuntime: false,
  streamFunction: stream,
  keyVault: vault ?? _Vault(),
  starterFiles: _starter,
  runTimeout: timeout,
  gameFactory: (env) => GamePreviewController(
    env: env,
    projectRoot: '/',
    backend: browser ?? _Browser(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real provider adapter sends DeepSeek wire format and private auth header',
    () async {
      const secret = 'sk-pocketforge-wire-test-key';
      const response =
          'data: {"id":"test","choices":[{"delta":{"content":"Ready."}}]}\n\n'
          'data: {"id":"test","choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n';
      final requests = <Map<String, dynamic>>[];
      final savedFactory = providerHttpClientFactory;
      resetSharedProviderHttpClient();
      providerHttpClientFactory = () =>
          http_testing.MockClient.streaming((request, requestBody) async {
            expect(request.method, 'POST');
            expect(
              request.url.toString(),
              'https://api.deepseek.com/chat/completions',
            );
            expect(request.headers['authorization'], 'Bearer $secret');
            final bodyText = await requestBody.bytesToString();
            expect(bodyText, isNot(contains(secret)));
            requests.add(jsonDecode(bodyText) as Map<String, dynamic>);
            return http.StreamedResponse(
              Stream.value(utf8.encode(response)),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          });
      addTearDown(() {
        resetSharedProviderHttpClient();
        providerHttpClientFactory = savedFactory;
      });
      final session = await PocketForgeSession.create(
        baseEnv: MemoryExecutionEnv(),
        useNativeRuntime: false,
        keyVault: _Vault(),
        starterFiles: _starter,
        gameFactory: (env) => GamePreviewController(
          env: env,
          projectRoot: '/',
          backend: _Browser(),
        ),
      );
      addTearDown(session.dispose);
      await session.saveSettings(
        modelId: 'deepseek-flash',
        apiKey: secret,
        maxRequests: 1,
      );
      await session.send('Say Ready.');
      expect(session.error, isNull);
      expect(requests, hasLength(1));
      final body = requests.single;
      expect(body['model'], 'deepseek-flash');
      expect(body['max_tokens'], 8192);
      expect(body.containsKey('max_completion_tokens'), isFalse);
      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body['stream'], isTrue);
      final tools = (body['tools'] as List).cast<Map<String, dynamic>>();
      expect(
        tools.any((tool) => (tool['function'] as Map)['name'] == 'game_test'),
        isTrue,
      );
      expect(tools.every((tool) => !tool.containsKey('strict')), isTrue);
      expect(session.messages.last.content, 'Ready.');
    },
  );

  test(
    'Fa loop observes failed browser check, repairs file and retests',
    () async {
      final storage = MemoryExecutionEnv();
      final browser = _Browser();
      var request = 0;
      var observedFailedCheck = false;
      final session = await _create(storage, (model, context, {cancelToken}) {
        request++;
        final lastTool = context.messages
            .whereType<ToolResultMessage>()
            .lastOrNull;
        switch (request) {
          case 1:
            return _reply(model, [_call(1, 'game_preview', {})]);
          case 2:
            return _reply(model, [
              _call(2, 'game_test', {
                'script': 'assert(window.__score===1,"score starts at 1");',
              }),
            ]);
          case 3:
            observedFailedCheck = jsonEncode(
              lastTool?.toJson(),
            ).contains('false');
            return _reply(model, [
              _call(3, 'write', {
                'path': 'game.js',
                'content': 'window.__score=1;',
              }),
            ]);
          case 4:
            return _reply(model, [_call(4, 'game_preview', {})]);
          case 5:
            return _reply(model, [
              _call(5, 'game_test', {
                'script': 'assert(window.__score===1,"score starts at 1");',
              }),
            ]);
          default:
            return _reply(model, [
              const TextContent(text: 'Fixed and retested.'),
            ]);
        }
      }, browser: browser);
      addTearDown(session.dispose);
      await session.send('Repair the starting score and test it.');
      expect(session.error, isNull);
      expect(request, 6);
      expect(observedFailedCheck, isTrue);
      expect(await session.readFile('game.js'), 'window.__score=1;');
      expect(browser.loads, 2);
      expect(session.game.lastTest?.passed, isTrue);
      expect(session.activity.any((event) => event.label == 'write'), isTrue);
      expect(session.checkpoints, isNotEmpty);
      expect(session.messages.last.content, 'Fixed and retested.');

      final reopened = await _create(
        storage,
        (model, context, {cancelToken}) =>
            _reply(model, [const TextContent(text: 'Loaded.')]),
      );
      addTearDown(reopened.dispose);
      expect(await reopened.readFile('game.js'), 'window.__score=1;');
      expect(reopened.messages.last.content, 'Fixed and retested.');
      final persisted = await _readAll(storage, session.store.sessionsPath);
      expect(persisted, contains('Fixed and retested.'));
      expect(persisted, contains('"type":"message"'));
    },
  );

  test(
    'request limit stops a continuing agent without another paid request',
    () async {
      var paidRequests = 0;
      final session = await _create(MemoryExecutionEnv(), (
        model,
        context, {
        cancelToken,
      }) {
        paidRequests++;
        return _reply(model, [
          _call(paidRequests, 'read', {'path': 'game.js'}),
        ]);
      });
      addTearDown(session.dispose);
      await session.saveSettings(modelId: 'deepseek-flash', maxRequests: 1);
      await session.send('Inspect until stopped.');
      expect(paidRequests, 1);
      expect(session.isRunning, isFalse);
      expect(session.status, contains('1-request run limit'));
      expect(await session.readFile('game.js'), _starter['game.js']);
    },
  );

  test(
    'Stop during initial checkpoint never starts a provider request',
    () async {
      var requests = 0;
      final session = await _create(MemoryExecutionEnv(), (
        model,
        context, {
        cancelToken,
      }) {
        requests++;
        return _reply(model, [const TextContent(text: 'Unexpected request.')]);
      });
      addTearDown(session.dispose);
      final running = session.send('Start building.');
      expect(session.isRunning, isTrue);
      expect(session.status, contains('checkpoint'));
      session.stop();
      await running;
      expect(requests, 0);
      expect(session.isRunning, isFalse);
      expect(session.status, contains('Stopped'));
      expect(session.error, isNull);
    },
  );

  test(
    'large screenshot does not exhaust text-only provider context budget',
    () async {
      var requests = 0;
      var rawContextBytes = 0;
      final browser = _Browser(screenshotBytes: 200000);
      final session = await _create(MemoryExecutionEnv(), (
        model,
        context, {
        cancelToken,
      }) {
        requests++;
        if (requests == 1) return _reply(model, [_call(1, 'game_preview', {})]);
        if (requests == 2) {
          return _reply(model, [_call(2, 'game_screenshot', {})]);
        }
        rawContextBytes = utf8
            .encode(
              jsonEncode(
                context.messages.map((message) => message.toJson()).toList(),
              ),
            )
            .length;
        return _reply(model, [
          const TextContent(text: 'Continued after screenshot.'),
        ]);
      }, browser: browser);
      addTearDown(session.dispose);
      await session.send('Capture the game and continue.');
      expect(browser.loads, 1);
      expect(session.game.lastScreenshot, hasLength(200000));
      expect(rawContextBytes, greaterThan(200000));
      expect(requests, 3);
      expect(session.error, isNull);
      expect(session.status, 'Ready.');
      expect(session.messages.last.content, 'Continued after screenshot.');
    },
  );

  test('Stop cancels provider token and outstanding browser work', () async {
    final entered = Completer<void>();
    final canceled = Completer<void>();
    final browser = _Browser();
    final session = await _create(MemoryExecutionEnv(), (
      model,
      context, {
      cancelToken,
    }) {
      final stream = AssistantMessageEventStream();
      entered.complete();
      unawaited(
        cancelToken!.onCancel.then((_) {
          canceled.complete();
          final message = AssistantMessage(
            content: const [],
            api: model.api,
            provider: model.provider,
            model: model.id,
            usage: Usage.zero,
            stopReason: StopReason.aborted,
            timestamp: DateTime.now(),
          );
          stream.push(ErrorEvent(reason: StopReason.aborted, error: message));
          stream.end();
        }),
      );
      return stream;
    }, browser: browser);
    addTearDown(session.dispose);
    final running = session.send('Wait for cancellation.');
    await entered.future.timeout(const Duration(seconds: 5));
    session.stop();
    await canceled.future.timeout(const Duration(seconds: 5));
    await running.timeout(const Duration(seconds: 5));
    expect(session.isRunning, isFalse);
    expect(browser.cancellations, greaterThan(0));
    expect(session.status, contains('Stopped'));
  });

  test('API key is absent from provider context, settings and JSONL', () async {
    const secret = 'sk-pocketforge-test-private-key';
    final storage = MemoryExecutionEnv();
    final vault = _Vault(secure: true);
    var sentContext = '';
    final session = await _create(storage, (model, context, {cancelToken}) {
      sentContext = jsonEncode(
        context.messages.map((message) => message.toJson()).toList(),
      );
      expect(model.baseUrl, 'https://api.deepseek.com');
      return _reply(model, [const TextContent(text: 'Saved.')]);
    }, vault: vault);
    addTearDown(session.dispose);
    await session.saveSettings(
      modelId: 'deepseek-flash',
      apiKey: secret,
      maxRequests: 2,
    );
    expect(vault.value, secret);
    await session.send('Do not repeat $secret');
    expect(sentContext, isNot(contains(secret)));
    final settings = (await storage.readTextFile(
      '${session.store.statePath}/settings.json',
    )).getOrThrow();
    expect(settings, isNot(contains(secret)));
    final sessionFiles = await _readAll(storage, session.store.sessionsPath);
    expect(sessionFiles, isNot(contains(secret)));
    expect(sessionFiles, contains('API key redacted'));
    await session.writeFile('private.txt', 'The value is $secret');
    expect(await session.readFile('private.txt'), isNot(contains(secret)));
    final persistedCode = (await storage.readTextFile(
      '${session.store.projectStoragePath}/private.txt',
    )).getOrThrow();
    expect(persistedCode, isNot(contains(secret)));
    expect((await session.env.exec('echo $secret')).isErr, isTrue);
    expect(
      (await session.env.readTextFile(
        '${session.store.statePath}/settings.json',
      )).isErr,
      isTrue,
    );
    final hidden = (await session.env.exec(
      'cat /pocketforge-state/settings.json',
    )).getOrThrow();
    expect(hidden.exitCode, isNot(0));
    expect(hidden.stdout, isNot(contains(secret)));
    await session.removeApiKey();
    expect(vault.value, isNull);
    expect(session.hasApiKey, isFalse);
  });

  test(
    'checkpoints restore project and invalid writes cannot escape project',
    () async {
      final store = await PocketForgeStore.create(
        MemoryExecutionEnv(),
        useNativeRuntime: false,
      );
      (await store.env.writeFile('index.html', 'first')).getOrThrow();
      final first = await store.checkpoint();
      (await store.env.writeFile('index.html', 'second')).getOrThrow();
      (await store.env.writeFile('nested/added.js', 'extra')).getOrThrow();
      expect(
        (await store.env.writeFile('../outside.txt', 'bad')).isErr,
        isTrue,
      );
      expect((await store.env.readTextFile('C:\\outside.txt')).isErr, isTrue);
      expect(
        (await store.env.writeFile(
          'huge.txt',
          'x' * (PocketForgeStore.maxFileBytes + 1),
        )).isErr,
        isTrue,
      );
      expect((await store.env.exec('python3 -c "print(1)"')).isErr, isTrue);
      expect(
        (await store.env.readTextFile('index.html')).getOrThrow(),
        'second',
      );
      await store.restore(first);
      expect(
        (await store.env.readTextFile('index.html')).getOrThrow(),
        'first',
      );
      expect((await store.env.exists('nested/added.js')).getOrThrow(), isFalse);
      for (var index = 0; index < 12; index++) {
        await store.checkpoint();
      }
      expect(await store.checkpoints(), hasLength(8));
    },
  );
}

Future<String> _readAll(ExecutionEnv fs, String path) async {
  final text = StringBuffer();
  for (final file in (await fs.listDir(path)).getOrThrow()) {
    if (file.kind == FileKind.directory) {
      text.write(await _readAll(fs, '$path/${file.name}'));
    } else {
      text.write((await fs.readTextFile('$path/${file.name}')).getOrThrow());
    }
  }
  return text.toString();
}
