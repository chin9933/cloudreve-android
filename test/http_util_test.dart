import 'package:cloudreve/utils/http_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cloudreve API 地址规范化', () {
    test('站点根地址自动补全 v4 API 路径', () {
      expect(
        HttpUtil.normalizeApiBaseUrl('https://cloud.example.com'),
        'https://cloud.example.com/api/v4/',
      );
    });

    test('保留已经填写的 v4 API 路径', () {
      expect(
        HttpUtil.normalizeApiBaseUrl(' https://cloud.example.com/api/v4 '),
        'https://cloud.example.com/api/v4/',
      );
    });

    test('拒绝明文 HTTP 和无效地址', () {
      expect(
        () => HttpUtil.normalizeApiBaseUrl('http://cloud.example.com'),
        throwsFormatException,
      );
      expect(
        () => HttpUtil.normalizeApiBaseUrl('not-a-url'),
        throwsFormatException,
      );
    });
  });
}
