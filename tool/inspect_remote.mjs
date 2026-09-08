const url = process.argv[2];
const response = await fetch(url, { signal: AbortSignal.timeout(25000) });
console.log(response.status, response.url);
const body = await response.text();
if (url.includes('/git/trees/')) {
  const tree = JSON.parse(body).tree ?? [];
  const pattern = new RegExp(process.argv[3] ?? '.', 'i');
  console.log(tree.filter(entry => pattern.test(entry.path)).map(entry => entry.path).join('\n'));
} else {
  const clean = body.replace(/data:image\/[^;]+;base64,[A-Za-z0-9+/=]+/g, '[captcha image]');
  if (process.argv[3]) {
    const lines = clean.split('\n');
    const selected = new Set();
    lines.forEach((line, i) => { if (line.includes(process.argv[3])) for (let j = Math.max(0, i - 10); j <= Math.min(lines.length-1, i+25); j++) selected.add(j); });
    console.log([...selected].map(i => `${i+1}: ${lines[i]}`).join('\n'));
  } else console.log(clean);
}
