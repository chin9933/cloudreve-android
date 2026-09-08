// Public build metadata only. Credentials belong in the signing environment.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const defaults = Object.freeze({
  APP_NAME: 'Cloudreve',
  APP_APPLICATION_ID: 'com.example.cloudreve',
  APP_DESCRIPTION: '安全存储 · 随时访问 · 轻松分享',
  CLOUDREVE_SITE_URL: '',
});
const valueOptions = {
  '--app-name': 'APP_NAME',
  '--application-id': 'APP_APPLICATION_ID',
  '--app-description': 'APP_DESCRIPTION',
  '--site-url': 'CLOUDREVE_SITE_URL',
  '--build-name': 'APP_VERSION_NAME',
  '--build-number': 'APP_VERSION_CODE',
};
const flags = new Set(['--online', '--split-per-abi', '--local-test', '--dry-run', '--help']);
const knownKeys = new Set([...Object.keys(defaults), 'APP_VERSION_NAME', 'APP_VERSION_CODE']);

export function validateMetadata(input) {
  for (const key of Object.keys(input)) {
    if (!knownKeys.has(key)) throw new Error(`Unknown build configuration key: ${key}`);
    if (typeof input[key] !== 'string' && !(key === 'APP_VERSION_CODE' && typeof input[key] === 'number')) {
      throw new Error(`${key} must be a string${key === 'APP_VERSION_CODE' ? ' or integer' : ''}.`);
    }
  }
  const metadata = Object.fromEntries(Object.entries(input).map(([key, value]) => [key, String(value).trim()]));
  for (const [key, maximum] of [['APP_NAME', 64], ['APP_DESCRIPTION', 240]]) {
    if (!metadata[key] || metadata[key].length > maximum || /[\u0000-\u001f\u007f]/u.test(metadata[key])) {
      throw new Error(`${key} must contain 1-${maximum} visible characters.`);
    }
  }
  if (!/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/u.test(metadata.APP_APPLICATION_ID ?? '')) {
    throw new Error('APP_APPLICATION_ID must use lowercase dotted identifiers, e.g. com.example.cloudreve.');
  }
  const site = metadata.CLOUDREVE_SITE_URL;
  if (site) {
    let parsed;
    try { parsed = new URL(site); } catch { throw new Error('CLOUDREVE_SITE_URL must be an HTTPS URL or empty.'); }
    if (parsed.protocol !== 'https:' || !parsed.hostname || parsed.username || parsed.password || parsed.search || parsed.hash || /[\s\\]/u.test(site) || /[?#]/u.test(site)) {
      throw new Error('CLOUDREVE_SITE_URL must use HTTPS without credentials, query parameters or fragments.');
    }
  }
  if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/u.test(metadata.APP_VERSION_NAME ?? '')) {
    throw new Error('APP_VERSION_NAME must be a version such as 1.2.0 or 1.2.0-beta.1.');
  }
  const code = Number(metadata.APP_VERSION_CODE);
  if (!/^[1-9]\d*$/u.test(metadata.APP_VERSION_CODE ?? '') || !Number.isSafeInteger(code) || code > 2100000000) {
    throw new Error('APP_VERSION_CODE must be an integer between 1 and 2100000000.');
  }
  return metadata;
}

export function parseBuildOptions(argv, {cwd = process.cwd(), read = path => readFileSync(path, 'utf8')} = {}) {
  const selectedFlags = new Set();
  const overrides = {};
  let configPath;
  for (let index = 0; index < argv.length; index++) {
    const token = argv[index];
    if (flags.has(token)) { selectedFlags.add(token); continue; }
    const split = token.indexOf('=');
    const option = split < 0 ? token : token.slice(0, split);
    if (option !== '--config' && !Object.hasOwn(valueOptions, option)) throw new Error(`Unknown option: ${option}`);
    const value = split < 0 ? argv[++index] : token.slice(split + 1);
    if (value === undefined || value.startsWith('--')) throw new Error(`Missing value for ${option}`);
    if (option === '--config') {
      if (configPath !== undefined) throw new Error('Specify --config only once.');
      if (!value) throw new Error('--config requires a JSON file.');
      configPath = resolve(cwd, value);
    } else {
      overrides[valueOptions[option]] = value;
    }
  }
  if (selectedFlags.has('--help')) return {help: true};
  const pubspec = read(resolve(root, 'pubspec.yaml'));
  const version = /^version:\s*([^\s+]+)\+(\d+)\s*$/mu.exec(pubspec);
  if (!version) throw new Error('pubspec.yaml must contain version: name+number.');
  const fromFile = configPath ? JSON.parse(read(configPath).replace(/^\uFEFF/u, '')) : {};
  if (!fromFile || typeof fromFile !== 'object' || Array.isArray(fromFile)) throw new Error('Build configuration must be a JSON object.');
  const metadata = validateMetadata({
    ...defaults,
    APP_VERSION_NAME: version[1], APP_VERSION_CODE: version[2],
    ...fromFile, ...overrides,
  });
  return {metadata, flags: selectedFlags};
}

export function gradleArguments(options) {
  const encoded = Object.entries(options.metadata).map(([key, value]) => Buffer.from(`${key}=${value}`, 'utf8').toString('base64')).join(',');
  return [
    'assembleRelease',
    ...(!options.flags.has('--online') ? ['--offline'] : []),
    ...(options.flags.has('--split-per-abi') ? [
      '-Psplit-per-abi=true',
      '-Ptarget-platform=android-arm,android-arm64,android-x64',
      '-Pforce-version-code-ignoring-abi=true',
    ] : []),
    ...(options.flags.has('--local-test') ? ['-PallowDebugReleaseSigning=true'] : []),
    `-Pdart-defines=${encoded}`,
    '-Ptree-shake-icons=true', '--no-daemon', '--console=plain', '--stacktrace',
  ];
}

const help = `Build a configurable Android release without editing source files.

Windows: tool\\build_android_release.cmd [options]
Other hosts with Flutter/Java/Android configured: node tool/build_android.mjs [options]

  --app-name TEXT          Launcher, startup, login and application information name
  --application-id ID     APK identity (default: com.example.cloudreve)
  --app-description TEXT  Startup/login tagline and application description
  --site-url URL          Default HTTPS server; use --site-url= for no preset
  --build-name VERSION    Version name (default: pubspec.yaml)
  --build-number NUMBER   Android version code (default: pubspec.yaml)
  --config FILE           Public metadata JSON; CLI values take precedence
  --split-per-abi         Separate armv7, arm64 and x86_64 APKs
  --online                Allow Gradle to download missing dependencies
  --local-test            Explicitly permit debug signing; never publish this APK
  --dry-run               Validate and display metadata without building
  --help                  Show this help

Do not put passwords, tokens or signing secrets in metadata. It is embedded in the APK.
Keep the same application ID and signing key to update an existing installation.
`;

export function main(argv = process.argv.slice(2)) {
  const options = parseBuildOptions(argv);
  if (options.help) { console.log(help); return 0; }
  console.log(JSON.stringify(options.metadata, null, 2));
  if (options.flags.has('--dry-run')) { console.log('Configuration valid. No build or source edits performed.'); return 0; }
  if (options.flags.has('--local-test')) console.log('LOCAL TEST ONLY: debug signing explicitly allowed. Do not publish.');
  const android = resolve(root, 'android');
  const args = gradleArguments(options);
  let result;
  if (process.platform === 'win32') {
    // Only fixed switches and base64 metadata reach cmd.exe, never raw user values.
    const wrapper = resolve(android, 'gradlew.bat');
    const command = `"${wrapper}" -p "${android}" ${args.join(' ')}`;
    result = spawnSync(command, {cwd: root, shell: process.env.ComSpec ?? 'cmd.exe', windowsHide: true, stdio: 'inherit'});
  } else {
    result = spawnSync(resolve(android, 'gradlew'), ['-p', android, ...args], {cwd: root, stdio: 'inherit'});
  }
  if (result.error) throw result.error;
  return result.status ?? 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { process.exitCode = main(); }
  catch (error) { console.error(error.message); process.exitCode = 2; }
}
