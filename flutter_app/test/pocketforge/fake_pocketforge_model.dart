import 'package:fa/pocketforge/pocketforge_model.dart';
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

class FakePocketForgeModel extends PocketForgeModel {
  @override
  final ExecutionEnv env = MemoryExecutionEnv(cwd: '/workspace');
  @override
  final List<FaChatMessage> messages = [];
  @override
  final List<ForgeActivity> activity = [];
  @override
  bool isRunning = false;
  @override
  String status = 'Ready';
  @override
  String? error;
  @override
  String projectName = 'Neon Drift';
  @override
  String runtimeLabel = 'Local sandbox';
  @override
  List<String> files = ['index.html', 'game.js', 'style.css'];
  @override
  String modelId = 'deepseek-flash';
  @override
  int maxRequests = 20;
  @override
  bool hasApiKey = true;
  @override
  bool secureKeyStorage = true;
  @override
  List<String> checkpoints = ['2026-11-06-starter'];

  final fileContents = <String, String>{
    'index.html':
        '<!doctype html>\n<html lang="en">\n  <title>Neon Drift</title>\n  <canvas id="game"></canvas>\n  <script src="game.js"></script>\n</html>\n',
    'game.js':
        'const game = { score: 0, running: false };\n\nfunction start() {\n  game.running = true;\n  game.score = 0;\n}\n',
    'style.css': 'body { margin: 0; background: #111314; }\n',
  };
  final sent = <String>[];
  int stopCount = 0;
  int previewCount = 0;
  String? savedKey;

  @override
  Future<void> send(String prompt) async {
    sent.add(prompt);
    messages.add(FaChatMessage(role: 'user', content: prompt));
    notifyListeners();
  }

  @override
  void stop() {
    stopCount++;
    isRunning = false;
    status = 'Stopped';
    notifyListeners();
  }

  @override
  Future<void> saveSettings({
    required String modelId,
    String? apiKey,
    required int maxRequests,
  }) async {
    this.modelId = modelId;
    this.maxRequests = maxRequests;
    if (apiKey != null) {
      savedKey = apiKey;
      hasApiKey = true;
    }
    notifyListeners();
  }

  @override
  Future<void> removeApiKey() async {
    hasApiKey = false;
    savedKey = null;
    notifyListeners();
  }

  @override
  Future<String> readFile(String path) async => fileContents[path] ?? '';
  @override
  Future<void> writeFile(String path, String content) async {
    fileContents[path] = content;
    notifyListeners();
  }

  @override
  Future<void> refreshFiles() async {
    notifyListeners();
  }

  @override
  Future<void> runPreview() async {
    previewCount++;
    notifyListeners();
  }

  @override
  Future<void> resetConversation() async {
    messages.clear();
    notifyListeners();
  }

  @override
  Future<void> createCheckpoint() async {
    checkpoints.add('new-checkpoint');
    notifyListeners();
  }

  @override
  Future<void> restoreCheckpoint(String id) async {
    notifyListeners();
  }

  @override
  void clearError() {
    error = null;
    notifyListeners();
  }

  void changed() => notifyListeners();

  void addConversationFixture() {
    messages.addAll([
      FaChatMessage(
        role: 'user',
        content: 'Add touch controls and make the game feel faster.',
      ),
      FaChatMessage(
        role: 'assistant',
        content:
            'I added left and right touch controls, tightened the turning, and made speed increase as you play.\n\nRun the preview to try the updated game.',
      ),
    ]);
    activity.addAll([
      const ForgeActivity(label: 'read', detail: 'game.js'),
      const ForgeActivity(
        label: 'edit',
        detail: 'Updated steering and touch controls in game.js',
      ),
    ]);
  }
}
