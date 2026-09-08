// Small ADB-only UI test helper. Screenshots are generated test artifacts.
import { execFile, execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import { createInterface } from 'node:readline';
const sdk = process.env.ANDROID_HOME ?? process.env.ANDROID_SDK_ROOT;
const executable = process.platform === 'win32' ? 'adb.exe' : 'adb';
const adb = process.env.ADB ?? (sdk ? resolve(sdk, 'platform-tools', executable) : executable);
// Without ANDROID_SERIAL, ADB itself rejects ambiguous multi-device selection.
const deviceArgs = process.env.ANDROID_SERIAL ? ['-s', process.env.ANDROID_SERIAL] : [];
const run = args => execFileSync(adb, [...deviceArgs, ...args], { windowsHide: true, timeout: 20000, maxBuffer: 16 * 1024 * 1024 });
const args = process.argv.slice(2);
function screenshot(filename) {
  const name = basename(filename);
  if (!name.endsWith('.png')) throw new Error('Expected screenshot .png');
  const dir = resolve('outputs/android-qa');
  mkdirSync(dir, {recursive: true});
  const path = resolve(dir, name);
  writeFileSync(path, run(['exec-out', 'screencap', '-p']));
  console.log(path);
}
while (args.length) {
  const op = args.shift();
  if (op === 'tap') run(['shell', 'input', 'tap', args.shift(), args.shift()]);
  else if (op === 'swipe') run(['shell', 'input', 'swipe', ...args.splice(0,5)]);
  else if (op === 'key') run(['shell', 'input', 'keyevent', args.shift()]);
  else if (op === 'text') run(['shell', 'input', 'text', args.shift()]);
  else if (op === 'secret') {
    if (process.stdin.isTTY) process.stdin.setRawMode(true);
    const input = createInterface({input: process.stdin, terminal: false});
    console.log('Waiting for masked field input on stdin');
    const value = await new Promise(resolve => input.once('line', resolve));
    input.close();
    if (process.stdin.isTTY) process.stdin.setRawMode(false);
    try { run(['shell', 'input', 'text', value]); }
    catch { throw new Error('Masked field input failed'); }
  }
  else if (op === 'clear') { run(['shell', 'input', 'keyevent', '123']); run(['shell', 'input', 'keyevent', ...Array(150).fill('67')]); }
  else if (op === 'wait') await new Promise(resolve => setTimeout(resolve, Math.min(3000, Number(args.shift()))));
  else if (op === 'shot') screenshot(args.shift());
  else if (op === 'holdshot') {
    const [x, y, filename] = args.splice(0, 3);
    if (![x, y].every(value => /^\d+$/.test(value))) throw new Error('Invalid point');
    const release = new Promise(resolve => execFile(adb,
      [...deviceArgs, 'shell', 'input', 'swipe', x, y, x, y, '1800'],
      {windowsHide: true, timeout: 10000}, error => resolve(error)));
    await new Promise(resolve => setTimeout(resolve, 450));
    screenshot(filename);
    const error = await release;
    if (error) throw error;
  } else throw new Error('Unknown QA action: ' + op);
}
