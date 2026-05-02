const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

function fakeWs(onSend) {
  const listeners = new Map();
  return {
    readyState: 1,
    sent: [],
    on(event, handler) {
      listeners.set(event, handler);
    },
    removeListener(event, handler) {
      if (listeners.get(event) === handler) listeners.delete(event);
    },
    send(raw) {
      this.sent.push(JSON.parse(raw));
      onSend?.(this.sent[this.sent.length - 1], listeners.get('message'));
    },
    listenerCount(event) {
      return listeners.has(event) ? 1 : 0;
    },
  };
}

describe('GatewayManageService', () => {
  it('returns deterministic system sessions per gateway', async () => {
    const { GatewayManageService } = require('../dist/services/gateway-manage-service');

    const service = new GatewayManageService({
      requestSystem: async () => ({ ok: true, json: { description: 'ok' } }),
    });

    const openclaw = service.getSystemSession('OpenClaw');
    const openclawAgain = service.getSystemSession('OpenClaw');
    const hermes = service.getSystemSession('Hermes');

    assert.equal(openclaw.gatewayId, 'OpenClaw');
    assert.equal(openclaw.sessionId, '__clawke_system__:OpenClaw');
    assert.equal(openclaw.kind, 'system');
    assert.equal(openclawAgain.sessionId, openclaw.sessionId);
    assert.equal(hermes.sessionId, '__clawke_system__:Hermes');
  });

  it('sends gateway_system_request and resolves matching response', async () => {
    const { GatewayManageService } = require('../dist/services/gateway-manage-service');
    const { sendGatewaySystemRequestForTest } = require('../dist/upstream/gateway-system-client');

    const ws = fakeWs((request, onMessage) => {
      assert.equal(request.type, 'gateway_system_request');
      assert.equal(request.gateway_id, 'OpenClaw');
      assert.equal(request.system_session_id, '__clawke_system__:OpenClaw');
      assert.equal(request.purpose, 'translation');
      assert.equal(request.prompt, 'Return strict JSON.');
      assert.deepEqual(request.response_schema, {
        type: 'object',
        required: ['description'],
        properties: { description: { type: 'string' } },
      });
      assert.deepEqual(request.metadata, {
        source: 'translation',
        entity_type: 'skill',
        entity_id: 'openclaw-bundled/1password',
        locale: 'zh',
      });
      assert.ok(request.request_id);

      onMessage(Buffer.from(JSON.stringify({
        type: 'gateway_system_response',
        request_id: 'other',
        ok: true,
        json: { description: 'wrong' },
      })));
      onMessage(Buffer.from(JSON.stringify({
        type: 'gateway_system_response',
        request_id: request.request_id,
        ok: true,
        json: { description: '设置并使用 1Password CLI。' },
      })));
    });

    const service = new GatewayManageService({
      requestSystem: (gatewayId, sessionId, input) => sendGatewaySystemRequestForTest(
        ws,
        gatewayId,
        sessionId,
        input,
        1000,
      ),
    });

    const response = await service.getSystemSession('OpenClaw').request({
      internal: true,
      purpose: 'translation',
      prompt: 'Return strict JSON.',
      responseSchema: {
        type: 'object',
        required: ['description'],
        properties: { description: { type: 'string' } },
      },
      metadata: {
        source: 'translation',
        entity_type: 'skill',
        entity_id: 'openclaw-bundled/1password',
        locale: 'zh',
      },
    });

    assert.equal(response.ok, true);
    assert.deepEqual(response.json, { description: '设置并使用 1Password CLI。' });
    assert.equal(ws.listenerCount('message'), 0);
  });

  it('rejects timeout when matching gateway_system_response never arrives', async () => {
    const { GatewaySystemError, sendGatewaySystemRequestForTest } = require('../dist/upstream/gateway-system-client');
    const ws = fakeWs(() => {});

    await assert.rejects(
      () => sendGatewaySystemRequestForTest(
        ws,
        'OpenClaw',
        '__clawke_system__:OpenClaw',
        {
          internal: true,
          purpose: 'translation',
          prompt: 'Return strict JSON.',
        },
        10,
      ),
      (err) => err instanceof GatewaySystemError
        && err.code === 'gateway_timeout'
        && err.status === 504,
    );
  });

  it('marks gateway_system_response as transient', async () => {
    const { isTransientGatewayResponseType } = require('../dist/upstream/gateway-listener');

    assert.equal(isTransientGatewayResponseType('gateway_system_response'), true);
    assert.equal(isTransientGatewayResponseType('agent_text'), false);
  });
});
