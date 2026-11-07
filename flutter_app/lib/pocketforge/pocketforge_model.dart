// l10n:ignore-file — PocketForge is an English-only independent product entrypoint.
import 'package:flutter/foundation.dart';
import 'package:fa_ui/fa_ui.dart' show FaChatMessage;
import 'package:flutter_agent_harness/flutter_agent_harness.dart'
    show ExecutionEnv;

class ForgeActivity {
  const ForgeActivity({
    required this.label,
    required this.detail,
    this.failed = false,
  });
  final String label;
  final String detail;
  final bool failed;
}

/// Product boundary: UI observes real state; it never invents successful tools/tests.
abstract class PocketForgeModel extends ChangeNotifier {
  VoidCallback? onPreviewRequested;
  ExecutionEnv get env;
  List<FaChatMessage> get messages;
  List<ForgeActivity> get activity;
  bool get isRunning;
  String get status;
  String? get error;
  String get projectName;
  String get runtimeLabel;
  List<String> get files;
  String get modelId;
  int get maxRequests;
  bool get hasApiKey;
  bool get secureKeyStorage;
  List<String> get checkpoints;

  Future<void> send(String prompt);
  void stop();
  Future<void> saveSettings({
    required String modelId,
    String? apiKey,
    required int maxRequests,
  });
  Future<void> removeApiKey();
  Future<String> readFile(String path);
  Future<void> writeFile(String path, String content);
  Future<void> refreshFiles();
  Future<void> runPreview();
  Future<void> resetConversation();
  Future<void> createCheckpoint();
  Future<void> restoreCheckpoint(String id);
  void clearError();
}
