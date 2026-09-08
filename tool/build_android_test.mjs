import assert from 'node:assert/strict';
import test from 'node:test';
import { defaults, gradleArguments, parseBuildOptions } from './build_android.mjs';

test('generic defaults have no deployment server; version comes from pubspec', () => {
  const options = parseBuildOptions([], {read: () => 'version: 2.7.0+19'});
  assert.equal(options.metadata.APP_NAME, 'Cloudreve');
  assert.equal(options.metadata.CLOUDREVE_SITE_URL, '');
  assert.equal(options.metadata.APP_APPLICATION_ID, 'com.example.cloudreve');
  assert.equal(options.metadata.APP_VERSION_NAME, '2.7.0');
  assert.equal(options.metadata.APP_VERSION_CODE, '19');
  assert.ok(gradleArguments(options).includes('--offline'));
  assert.ok(!gradleArguments(options).includes('-PallowDebugReleaseSigning=true'));
});

test('Unicode and shell punctuation are safely base64 encoded for both platforms', () => {
  const options = parseBuildOptions([
    '--app-name', '团队 云盘 & "Archive"', '--application-id=com.example.archive',
    '--site-url=https://cloud.example.com/drive', '--app-description', '共享、归档与预览',
    '--build-name=2.3.4-beta.1', '--build-number=42', '--split-per-abi', '--local-test', '--online',
  ]);
  const args = gradleArguments(options);
  const defines = args.find(value => value.startsWith('-Pdart-defines='));
  const decoded = Object.fromEntries(defines.slice('-Pdart-defines='.length).split(',').map(value => {
    const text = Buffer.from(value, 'base64').toString('utf8');
    const separator = text.indexOf('=');
    return [text.slice(0, separator), text.slice(separator + 1)];
  }));
  assert.deepEqual(decoded, options.metadata);
  assert.ok(!args.join(' ').includes('团队'));
  assert.ok(!args.includes('--offline'));
  assert.ok(args.includes('-Psplit-per-abi=true'));
  assert.ok(args.includes('-PallowDebugReleaseSigning=true'));
});

test('JSON supports a numeric version code and CLI overrides it regardless of order', () => {
  const read = path => path.endsWith('pubspec.yaml') ? 'version: 1.9.0+9' : JSON.stringify({
    APP_NAME: 'JSON Client', APP_VERSION_CODE: 12, CLOUDREVE_SITE_URL: 'https://cloud.example.com',
  });
  const options = parseBuildOptions(['--app-name=CLI Client', '--config=config/app.local.json', '--site-url=', '--build-number=13'], {read});
  assert.equal(options.metadata.APP_NAME, 'CLI Client');
  assert.equal(options.metadata.APP_VERSION_CODE, '13');
  assert.equal(options.metadata.APP_VERSION_NAME, '1.9.0');
  assert.equal(options.metadata.CLOUDREVE_SITE_URL, '');
});

test('missing values, unknown keys and invalid metadata fail before Gradle', () => {
  for (const argv of [
    ['--app-name'], ['--app-name='], ['--app-description='], ['--app-name=a\nb'],
    ['--application-id=bad-id'], ['--application-id=Com.Example.App'],
    ['--build-number=0'], ['--build-number=1.5'], ['--build-number=2100000001'],
    ['--build-name=not-a-version'], ['--site-url=http://cloud.example.com'],
    ['--site-url=https://user:secret@cloud.example.com'],
    ['--site-url=https://cloud.example.com?token=secret'],
    ['--site-url=https://cloud.example.com/#'], ['--typo=value'],
  ]) assert.throws(() => parseBuildOptions(argv), undefined, argv.join(' '));
  assert.throws(() => parseBuildOptions(['--config=bad.json'], {
    read: path => path.endsWith('pubspec.yaml') ? 'version: 1.0.0+1' : JSON.stringify({...defaults, API_TOKEN: 'must-not-be-accepted'}),
  }), /Unknown build configuration key/);
});

test('help does not read configuration or require an installed SDK', () => {
  assert.deepEqual(parseBuildOptions(['--help'], {read: () => {throw new Error('Unexpected read');}}), {help: true});
});
