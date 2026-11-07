import 'dart:io';

import 'package:fa/pocketforge/pocketforge_session.dart';
import 'package:fa/pocketforge/pocketforge_store.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

final class _NoVault implements PocketForgeKeyVault {
  @override
  Future<bool> available() async => false;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> save(String key) async => throw StateError('No vault');
  @override
  Future<void> delete() async {}
}

AssistantMessageEventStream _reply(
  Model model,
  Context context, {
  CancelToken? cancelToken,
}) {
  final message = AssistantMessage(
    content: [const TextContent(text: 'Saved on this device.')],
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: Usage.zero,
    stopReason: StopReason.stop,
    timestamp: DateTime.now(),
  );
  return AssistantMessageEventStream()
    ..push(DoneEvent(reason: StopReason.stop, message: message))
    ..end();
}

Future<PocketForgeSession> _open(String directory) async {
  final storage = await PocketForgeStore.createDurableNativeStorage(
    directoryPath: directory,
  );
  return PocketForgeSession.create(
    baseEnv: storage!,
    useNativeRuntime: false,
    keyVault: _NoVault(),
    streamFunction: _reply,
    starterFiles: {'index.html': '<!doctype html><title>Local starter</title>'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native file metadata exposes symlinks and refuses a linked project',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocketforge-links-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final project = await Directory(
        path.join(directory.path, 'pocketforge-project'),
      ).create();
      final outside = await File(
        path.join(directory.path, 'outside.txt'),
      ).writeAsString('private metadata');
      try {
        await Link(path.join(project.path, 'linked.txt')).create(outside.path);
        await Link(
          path.join(project.path, 'broken.txt'),
        ).create(path.join(directory.path, 'missing.txt'));
      } on FileSystemException {
        if (Platform.isWindows) {
          markTestSkipped(
            'This Windows account lacks symbolic-link creation privileges.',
          );
          return;
        }
        rethrow;
      }
      final storage = (await PocketForgeStore.createDurableNativeStorage(
        directoryPath: directory.path,
      ))!;
      expect(
        (await storage.fileInfo(
          path.join(project.path, 'linked.txt'),
        )).getOrThrow().kind,
        FileKind.symlink,
      );
      expect(
        (await storage.fileInfo(
          path.join(project.path, 'broken.txt'),
        )).getOrThrow().kind,
        FileKind.symlink,
      );
      final children = (await storage.listDir(project.path)).getOrThrow();
      expect(children.every((item) => item.kind == FileKind.symlink), isTrue);
      await expectLater(
        PocketForgeStore.create(storage, useNativeRuntime: false),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('symbolic links'),
          ),
        ),
      );
    },
  );

  test(
    'native disk storage survives full session recreation without WASI',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocketforge-disk-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final first = await _open(directory.path);
      expect(first.runtimeLabel, contains('Portable'));
      expect((await first.store.storage.exec('echo forbidden')).isErr, isTrue);
      await first.saveSettings(modelId: 'deepseek-flash', maxRequests: 3);
      await first.writeFile(
        'index.html',
        '<!doctype html><title>My persisted game</title>',
      );
      await first.send('Remember this conversation.');
      final checkpoint = first.checkpoints.first;
      expect(
        File(
          path.join(directory.path, 'pocketforge-project', 'index.html'),
        ).existsSync(),
        isTrue,
      );
      first.dispose();

      // A new native filesystem and new portable project shell are created.
      // No memory object from the first app session is reused.
      final second = await _open(directory.path);
      addTearDown(second.dispose);
      expect(
        await second.readFile('index.html'),
        contains('My persisted game'),
      );
      expect(second.maxRequests, 3);
      expect(
        second.messages.any(
          (message) => message.content == 'Remember this conversation.',
        ),
        isTrue,
      );
      expect(second.messages.last.content, 'Saved on this device.');
      expect(second.checkpoints, contains(checkpoint));
      expect(
        (await second.env.readTextFile(
          '/pocketforge-state/settings.json',
        )).isErr,
        isTrue,
      );
      final hidden = (await second.env.exec(
        'cat /pocketforge-state/settings.json',
      )).getOrThrow();
      expect(hidden.exitCode, isNot(0));
      await second.writeFile('index.html', 'changed');
      await second.restoreCheckpoint(checkpoint);
      expect(
        await second.readFile('index.html'),
        contains('My persisted game'),
      );
    },
  );
}
