// Read-only release hygiene guard. This is NOT a complete secret/security audit.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { basename, dirname, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const files = [...new Set(execFileSync('git', [
  'ls-files', '--cached', '--others', '--exclude-standard', '-z',
], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean))];
const failures = [];
const forbidden = /(^|\/)(outputs|\.tooling|\.dart_tool|build|coverage|\.idea|\.vscode)(\/|$)|(^|\/)(local|key)\.properties$|\.(apk|aab|jks|keystore|p12|pfx|pem|key|log)$/i;
const textExtensions = new Set(['.dart', '.java', '.kt', '.kts', '.yaml', '.yml', '.json', '.mjs', '.py', '.cmd', '.bat', '.sh', '.md', '.xml', '.properties', '.txt']);
const secretPatterns = [
  /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/,
  /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b/,
  /\bgithub_pat_[A-Za-z0-9_]{40,}\b/,
  /\bAKIA[A-Z0-9]{16}\b/,
];
let checked = 0;
for (const path of files) {
  const absolute = resolve(root, path);
  if (!existsSync(absolute) || !statSync(absolute).isFile()) continue;
  checked++;
  if (forbidden.test(path) || /^\.env(?:\.|$)/.test(path) && path !== '.env.example' || /^config\/.*\.local\.json$/.test(path)) {
    failures.push(`${path}: local/private artifact must not be tracked`);
  }
  if (/^(lib|test)\/.*\.dart$/.test(path) && !/^[a-z][a-z0-9_]*\.dart$/.test(basename(path))) {
    failures.push(`${path}: Dart file name must use lower_case_with_underscores`);
  }
  if (!textExtensions.has(extname(path)) || statSync(absolute).size > 4 * 1024 * 1024) continue;
  const content = readFileSync(absolute, 'utf8');
  if (/\b[A-Za-z]:[\\/]+Users[\\/]/.test(content)) failures.push(`${path}: developer-specific absolute path`);
  for (const pattern of secretPatterns) {
    if (pattern.test(content)) {
      failures.push(`${path}: possible credential; value suppressed`);
      break;
    }
  }
}
const required = [
  'README.md', 'CONTRIBUTING.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md',
  '.editorconfig', '.gitattributes', '.fvmrc', 'pubspec.lock',
  '.github/workflows/ci.yml',
  'android/gradlew', 'android/gradlew.bat', 'android/gradle/wrapper/gradle-wrapper.jar',
];
for (const path of required) {
  if (!files.includes(path) || !existsSync(resolve(root, path))) failures.push(`${path}: missing or ignored release source`);
}
if (failures.length) {
  console.error(failures.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Repository hygiene passed: ${checked} source files; no prohibited artifacts or recognized secret patterns.`);
  console.log('Before publishing, separately review Git history, licensing, dependencies and release signing.');
}
