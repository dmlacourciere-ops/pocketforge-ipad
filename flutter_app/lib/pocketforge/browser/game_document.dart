import 'dart:convert';

import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:path/path.dart' as path;

/// Bundles browser-ready project files into one isolated document, through
/// ExecutionEnv only. No file URL grants or credential bridge are necessary.
class GameDocumentBundler {
  GameDocumentBundler({required this.env, required String projectRoot})
    : root = path.posix.normalize(projectRoot.replaceAll('\\', '/'));
  final ExecutionEnv env;
  final String root;
  int _bytes = 0;
  static const int fileLimit = 2 * 1024 * 1024;
  static const int documentLimit = 8 * 1024 * 1024;

  Future<String> bundle(String entry, String runtime) async {
    _bytes = 0;
    final full = _resolve(root, entry);
    if (!full.toLowerCase().endsWith('.html') &&
        !full.toLowerCase().endsWith('.htm')) {
      throw ArgumentError('Choose a local .html file.');
    }
    final document = parser.parse(await _text(full));
    final directory = path.posix.dirname(full);
    for (final script in document.querySelectorAll('script')) {
      if (script.attributes['type']?.toLowerCase() == 'module') {
        throw UnsupportedError(
          'Use ordinary relative scripts for local games; module bundling is not available.',
        );
      }
      final src = script.attributes.remove('src');
      if (src == null) continue;
      final source = await _text(_resolve(directory, src));
      script.text = source.replaceAll(
        RegExp('</script', caseSensitive: false),
        r'<\/script',
      );
    }
    for (final link in document.querySelectorAll('link')) {
      final rel = (link.attributes['rel'] ?? '').toLowerCase().split(
        RegExp(r'\s+'),
      );
      final href = link.attributes['href'];
      if (!rel.contains('stylesheet') || href == null) {
        link.remove();
        continue;
      }
      final cssPath = _resolve(directory, href);
      final css = await _css(await _text(cssPath), path.posix.dirname(cssPath));
      link.replaceWith(
        dom.Element.tag('style')
          ..text = css.replaceAll(
            RegExp('</style', caseSensitive: false),
            r'<\/style',
          ),
      );
    }
    for (final style in document.querySelectorAll('style')) {
      style.text = (await _css(
        style.text,
        directory,
      )).replaceAll(RegExp('</style', caseSensitive: false), r'<\/style');
    }
    for (final node in document.querySelectorAll('img,audio,video,source')) {
      for (final attr in ['src', 'poster']) {
        final source = node.attributes[attr];
        if (source == null ||
            source.startsWith('data:') ||
            source.startsWith('blob:')) {
          continue;
        }
        node.attributes[attr] = await _asset(_resolve(directory, source));
      }
    }
    for (final base in document.querySelectorAll('base')) {
      base.remove();
    }
    const policy =
        "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' data: blob:; style-src 'unsafe-inline' data:; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
    document.head!.nodes.insertAll(0, [
      dom.Element.tag('meta')..attributes['charset'] = 'utf-8',
      dom.Element.tag('meta')
        ..attributes.addAll({
          'name': 'viewport',
          'content': 'width=device-width,initial-scale=1',
        }),
      dom.Element.tag('meta')
        ..attributes.addAll({
          'http-equiv': 'Content-Security-Policy',
          'content': policy,
        }),
      dom.Element.tag('script')
        ..text =
            '${runtime.replaceAll(RegExp('</script', caseSensitive: false), r'<\/script')}\n/*POCKETFORGE_RPC*/',
    ]);
    final serialized = document.outerHtml;
    return serialized.toLowerCase().startsWith('<!doctype')
        ? serialized
        : '<!doctype html>$serialized';
  }

  String _resolve(String directory, String reference) {
    if (reference.isEmpty ||
        reference.startsWith('/') ||
        reference.contains('\\') ||
        reference.contains(':')) {
      throw ArgumentError(
        'Only relative local project assets are supported: $reference',
      );
    }
    final decoded = Uri.decodeComponent(
      reference.split('#').first.split('?').first,
    );
    final resolved = path.posix.normalize(path.posix.join(directory, decoded));
    if (!path.posix.isWithin(root, resolved)) {
      throw ArgumentError('Asset path leaves the project: $reference');
    }
    return resolved;
  }

  Future<void> _check(String full) async {
    var current = root;
    final rootInfo = (await env.fileInfo(root)).getOrThrow();
    if (rootInfo.kind != FileKind.directory) {
      throw ArgumentError('The project root is not a directory.');
    }
    for (final segment in path.posix.relative(full, from: root).split('/')) {
      current = path.posix.join(current, segment);
      final info = (await env.fileInfo(current)).getOrThrow();
      if (info.kind == FileKind.symlink) {
        throw ArgumentError('Symbolic links are not allowed in game previews.');
      }
    }
    final info = (await env.fileInfo(full)).getOrThrow();
    if (info.kind != FileKind.file || info.size > fileLimit) {
      throw ArgumentError('Asset must be a regular file below 2 MiB: $full');
    }
    _bytes += info.size;
    if (_bytes > documentLimit) {
      throw ArgumentError('The bundled game exceeds 8 MiB.');
    }
  }

  Future<String> _text(String full) async {
    await _check(full);
    return (await env.readTextFile(full)).getOrThrow();
  }

  Future<String> _asset(String full) async {
    await _check(full);
    final bytes = (await env.readBinaryFile(full)).getOrThrow();
    final ext = path.posix.extension(full).toLowerCase();
    final mime =
        const {
          '.png': 'image/png',
          '.jpg': 'image/jpeg',
          '.jpeg': 'image/jpeg',
          '.gif': 'image/gif',
          '.webp': 'image/webp',
          '.svg': 'image/svg+xml',
          '.mp3': 'audio/mpeg',
          '.wav': 'audio/wav',
          '.mp4': 'video/mp4',
          '.woff': 'font/woff',
          '.woff2': 'font/woff2',
        }[ext] ??
        'application/octet-stream';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<String> _css(String source, String directory) => _replaceAsync(
    source,
    RegExp(r'''url\(\s*(["']?)(.*?)\1\s*\)''', caseSensitive: false),
    (match) async {
      final src = match[2]!;
      if (src.startsWith('data:') ||
          src.startsWith('blob:') ||
          src.startsWith('#')) {
        return match[0]!;
      }
      return 'url("${await _asset(_resolve(directory, src))}")';
    },
  );

  static Future<String> _replaceAsync(
    String source,
    RegExp pattern,
    Future<String> Function(RegExpMatch) replace,
  ) async {
    final out = StringBuffer();
    var cursor = 0;
    for (final match in pattern.allMatches(source)) {
      out.write(source.substring(cursor, match.start));
      out.write(await replace(match));
      cursor = match.end;
    }
    out.write(source.substring(cursor));
    return out.toString();
  }
}
