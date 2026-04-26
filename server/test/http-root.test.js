const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

describe('HTTP root route', () => {
  const servers = [];
  const tempDirs = [];
  let previousClawkeDataDir;

  beforeEach(() => {
    previousClawkeDataDir = process.env.CLAWKE_DATA_DIR;
  });

  afterEach(async () => {
    await Promise.all(
      servers.splice(0).map(
        (server) => new Promise((resolve) => server.close(resolve)),
      ),
    );
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    if (previousClawkeDataDir === undefined) delete process.env.CLAWKE_DATA_DIR;
    else process.env.CLAWKE_DATA_DIR = previousClawkeDataDir;
  });

  it('explains that the HTTP root is an API service without requiring auth', async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-http-root-'));
    tempDirs.push(tmpDir);
    process.env.CLAWKE_DATA_DIR = tmpDir;
    fs.writeFileSync(
      path.join(tmpDir, 'clawke.json'),
      JSON.stringify({
        relay: { token: 'root-route-token' },
        server: { mode: 'mock' },
      }),
    );

    const { startUnifiedServer } = require('../dist/http-server');
    const { server } = startUnifiedServer(0);
    servers.push(server);
    if (!server.listening) {
      await new Promise((resolve) => server.once('listening', resolve));
    }

    const port = server.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.service, 'clawke-cs');
    assert.equal(body.kind, 'api');
    assert.match(body.message, /API/);
    assert.ok(Array.isArray(body.endpoints));
  });
});
