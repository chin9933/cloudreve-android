import { readFileSync } from 'node:fs';
const [file, start = '1', end = '200'] = process.argv.slice(2);
const lines = readFileSync(file, 'utf8').split(/\r?\n/);
for (let i = Number(start) - 1; i < Math.min(Number(end), lines.length); i++) {
  process.stdout.write(`${i + 1}: ${lines[i]}\n`);
}
