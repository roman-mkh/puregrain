// Runs inside Playwright's Docker image for scripts/check-web.mjs, under
// the image's own Node. Serves the built page (web/dist, mounted read-only
// at /opt/site) at http://localhost:8080/, then starts Playwright's server
// (the host's playwright-core, mounted read-only at /opt/playwright-core,
// so the check and the server are the same version) on port 3000, which
// check-web.mjs connects to. The browsers load the page from a local
// address inside the container: a secure context, as on GitHub Pages, and
// nothing on the host is within their reach.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn } from 'node:child_process';

const site = '/opt/site';
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

const server = http.createServer((request, response) => {
  const name = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const file = path.join(site, name.endsWith('/') ? `${name}index.html` : name);
  if (!file.startsWith(`${site}/`) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    response.writeHead(404);
    response.end();
    return;
  }
  response.writeHead(200, { 'Content-Type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(response);
});

server.listen(8080, '127.0.0.1', () => {
  const playwright = spawn('node', ['/opt/playwright-core/cli.js', 'run-server', '--port', '3000', '--host', '0.0.0.0'], {
    stdio: 'inherit',
  });
  playwright.on('exit', (code) => process.exit(code ?? 1));
});
