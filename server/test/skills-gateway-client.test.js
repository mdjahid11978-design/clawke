const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const {
  sendSkillGatewayRequestForTest,
  SkillGatewayError,
} = require('../dist/upstream/skill-gateway-client');

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
  };
}

describe('Skill gateway client', () => {
  it('routes skill_list with request_id and resolves matching response', async () => {
    const ws = fakeWs((request, onMessage) => {
      assert.equal(request.type, 'skill_list');
      assert.equal(request.account_id, 'hermes-work');
      assert.ok(request.request_id);
      onMessage(Buffer.from(JSON.stringify({
        type: 'skill_list_response',
        request_id: request.request_id,
        ok: true,
        skills: [{ id: 'apple/apple-notes', name: 'apple-notes' }],
      })));
    });

    const response = await sendSkillGatewayRequestForTest(ws, {
      type: 'skill_list',
      account_id: 'hermes-work',
    });

    assert.equal(response.type, 'skill_list_response');
    assert.equal(response.skills[0].id, 'apple/apple-notes');
  });

  it('rejects gateway error responses', async () => {
    const ws = fakeWs((request, onMessage) => {
      onMessage(Buffer.from(JSON.stringify({
        type: 'skill_mutation_response',
        request_id: request.request_id,
        ok: false,
        error: 'skill_error',
        message: 'boom',
      })));
    });

    await assert.rejects(
      () => sendSkillGatewayRequestForTest(ws, {
        type: 'skill_delete',
        account_id: 'hermes-work',
        skill_id: 'apple/apple-notes',
      }),
      (err) => err instanceof SkillGatewayError && err.code === 'skill_error' && err.message === 'boom',
    );
  });
});
