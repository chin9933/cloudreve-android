import 'package:cloudreve/state/download_history_controller.dart';

class MemoryDownloadHistoryStore implements DownloadHistoryStore {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('storage full');
    values[key] = value;
  }
}
