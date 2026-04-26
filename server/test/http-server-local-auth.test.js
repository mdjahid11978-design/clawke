const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const WebSocket = require('ws');

function requireFresh(modulePath) {
  const resolved = require.resolve(modulePath);
  delete require.cache[resolved];
  return require(modulePath);
}

function waitForOpenOrError(ws) {
  return new Promise((resolve) => {
    ws.once('open', () => resolve({ ok: true }));
    ws.once('error', (error) => resolve({ ok: false, error }));
  });
}

describe('Unified server local auth bypass', () => {
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

  async function startServerWithRelayToken() {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-local-auth-'));
    tempDirs.push(tmpDir);
    process.env.CLAWKE_DATA_DIR = tmpDir;
    fs.writeFileSync(
      path.join(tmpDir, 'clawke.json'),
      JSON.stringify({
        relay: { token: 'local-auth-token' },
        server: { mode: 'mock' },
      }),
    );

    requireFresh('../dist/config');
    const { startUnifiedServer } = requireFresh('../dist/http-server');
    const { server } = startUnifiedServer(0);
    servers.push(server);
    if (!server.listening) {
      await new Promise((resolve) => server.once('listening', resolve));
    }
    return server.address().port;
  }

  it('allows local HTTP requests without token even when relay token exists', async () => {
    const port = await startServerWithRelayToken();

    const res = await fetch(`http://127.0.0.1:${port}/api/does-not-exist`);

    assert.equal(res.status, 404);
  });

  it('uses socket remote address instead of spoofable Host for auth', () => {
    const { isAuthorizedRequest } = requireFresh('../dist/http-server');

    assert.equal(isAuthorizedRequest({
      serverToken: 'local-auth-token',
      clientToken: '',
      remoteAddress: '203.0.113.10',
    }), false);
    assert.equal(isAuthorizedRequest({
      serverToken: 'local-auth-token',
      clientToken: '',
      remoteAddress: '127.0.0.1',
    }), true);
    assert.equal(isAuthorizedRequest({
      serverToken: 'local-auth-token',
      clientToken: '',
      remoteAddress: '::ffff:127.0.0.1',
    }), true);
    assert.equal(isAuthorizedRequest({
      serverToken: 'local-auth-token',
      clientToken: 'local-auth-token',
      remoteAddress: '203.0.113.10',
    }), true);
  });

  it('allows local WebSocket requests without token even when relay token exists', async () => {
    const port = await startServerWithRelayToken();
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);

    const result = await waitForOpenOrError(ws);
    ws.close();

    assert.equal(result.ok, true);
  });

});
