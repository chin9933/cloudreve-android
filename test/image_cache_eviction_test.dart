import 'dart:io';
import 'dart:typed_data';

import 'package:cloudreve/utils/cache_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp(
      'cloudreve-image-cache-test-',
    );
  });
  tearDown(() async {
    final parent = Directory.systemTemp.absolute.path;
    expect(
      scratch.absolute.path.startsWith(
        '$parent${Platform.pathSeparator}cloudreve-image-cache-test-',
      ),
      isTrue,
    );
    await scratch.delete(recursive: true);
  });
  Future<File> entry(String hex, {int bytes = 10, int ageHours = 0}) async {
    final file = File('${scratch.path}/v2-${hex.padLeft(64, '0')}');
    await file.writeAsBytes(Uint8List(bytes));
    await file.setLastModified(
      DateTime.now().subtract(Duration(hours: ageHours)),
    );
    return file;
  }

  test('expiry removes only owned versioned cache files', () async {
    final expired = await entry('1', ageHours: 96);
    final fresh = await entry('2');
    final unrelated = File('${scratch.path}/original.txt');
    await unrelated.writeAsString('must survive');
    final similar = File('${scratch.path}/prefix-v2-${'3'.padLeft(64, '0')}');
    await similar.writeAsString('must also survive');
    await similar.setLastModified(
      DateTime.now().subtract(const Duration(days: 4)),
    );
    await CacheUtil.trimImages(scratch, 'image');
    expect(await expired.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await unrelated.readAsString(), 'must survive');
    expect(await similar.exists(), isTrue);
  });

  test('disk budget evicts older images before newer images', () async {
    final old = await entry('a', bytes: 5 * 1024 * 1024, ageHours: 1);
    final recent = await entry('b', bytes: 5 * 1024 * 1024);
    await CacheUtil.trimImages(scratch, 'avatar');
    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isTrue);
  });

  test('unknown cache bucket fails without deleting any files', () async {
    final file = await entry('f', ageHours: 96);
    await expectLater(
      CacheUtil.trimImages(scratch, '../data'),
      throwsArgumentError,
    );
    expect(await file.exists(), isTrue);
  });
}
