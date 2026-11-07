import 'dart:typed_data';

import 'package:fa/pocketforge/browser/game_document.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryExecutionEnv env;
  setUp(() async {
    env = MemoryExecutionEnv(cwd: '/workspace');
    (await env.createDir('/workspace')).getOrThrow();
    (await env.writeFile(
      '/workspace/index.html',
      '<!doctype html><html><head><link rel="stylesheet" href="style.css"></head><body><button id="go">Play</button><script src="src/game.js"></script><img src="star.png"></body></html>',
    )).getOrThrow();
    (await env.writeFile(
      '/workspace/style.css',
      'body{color:cyan;background:url(star.png)}',
    )).getOrThrow();
    (await env.writeFile(
      '/workspace/src/game.js',
      'window.score=1; console.log("ready");',
    )).getOrThrow();
    (await env.writeBinaryFile(
      '/workspace/star.png',
      Uint8List.fromList([137, 80, 78, 71]),
    )).getOrThrow();
  });

  test(
    'bundles real local JavaScript, CSS, images and controlled runtime',
    () async {
      final html = await GameDocumentBundler(
        env: env,
        projectRoot: '/workspace',
      ).bundle('index.html', 'window.testRuntime=true;');
      expect(html, contains('window.score=1'));
      expect(html, contains('<style>body{color:cyan'));
      expect(html, contains('data:image/png;base64,iVBORw=='));
      expect(html, contains("connect-src 'none'"));
      expect(html, contains('/*POCKETFORGE_RPC*/'));
      expect(
        html.indexOf('window.testRuntime=true'),
        lessThan(html.indexOf('window.score=1')),
      );
      expect(html, isNot(contains('src="src/game.js"')));
    },
  );

  test(
    'rejects traversal, encoded traversal, remote scripts and oversized assets',
    () async {
      for (final entry in [
        '../secrets.html',
        '%2e%2e/secrets.html',
        '/etc/index.html',
        'https://example.com/index.html',
      ]) {
        await expectLater(
          GameDocumentBundler(
            env: env,
            projectRoot: '/workspace',
          ).bundle(entry, ''),
          throwsArgumentError,
        );
      }
      (await env.writeFile(
        '/workspace/index.html',
        '<script src="https://example.com/remote.js"></script>',
      )).getOrThrow();
      await expectLater(
        GameDocumentBundler(
          env: env,
          projectRoot: '/workspace',
        ).bundle('index.html', ''),
        throwsArgumentError,
      );
      (await env.writeFile(
        '/workspace/index.html',
        '<script src="huge.js"></script>',
      )).getOrThrow();
      (await env.writeFile(
        '/workspace/huge.js',
        'x' * (2 * 1024 * 1024 + 1),
      )).getOrThrow();
      await expectLater(
        GameDocumentBundler(
          env: env,
          projectRoot: '/workspace',
        ).bundle('index.html', ''),
        throwsArgumentError,
      );
    },
  );

  test(
    'rejects module scripts instead of claiming a Node/module runtime',
    () async {
      (await env.writeFile(
        '/workspace/index.html',
        '<script type="module" src="src/game.js"></script>',
      )).getOrThrow();
      await expectLater(
        GameDocumentBundler(
          env: env,
          projectRoot: '/workspace',
        ).bundle('index.html', ''),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'creates a valid document head for HTML snippets and escapes script terminators',
    () async {
      (await env.writeFile(
        '/workspace/index.html',
        '<h1>Game</h1><script src="src/game.js"></script>',
      )).getOrThrow();
      (await env.writeFile(
        '/workspace/src/game.js',
        'const text="</script><img src=x>";',
      )).getOrThrow();
      final html = await GameDocumentBundler(
        env: env,
        projectRoot: '/workspace',
      ).bundle('index.html', 'window.runtime=1;');
      expect(html, startsWith('<!doctype html><html><head>'));
      expect(html, contains(r'<\/script><img src=x>'));
    },
  );
}
