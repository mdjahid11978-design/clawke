const test = require('node:test');
const assert = require('node:assert/strict');
const { Database } = require('../dist/store/database');
const { MessageStore } = require('../dist/store/message-store');
const { ConversationStore } = require('../dist/store/conversation-store');
const { ConversationConfigStore } = require('../dist/store/conversation-config-store');
const { CupV2Handler } = require('../dist/protocol/cup-v2-handler');
const { MessageRouter } = require('../dist/upstream/message-router');
const { translateToCup } = require('../dist/translator/cup-encoder');

test('MessageRouter notifies push pipeline only after storing agent messages', () => {
  const db = new Database(':memory:');
  new ConversationConfigStore(db);
  const messageStore = new MessageStore(db);
  const conversationStore = new ConversationStore(db);
  const cupHandler = new CupV2Handler(messageStore, conversationStore);
  const notifications = [];
  const router = new MessageRouter(
    translateToCup,
    cupHandler,
    {
      recordTokens: () => {},
      recordToolCall: () => {},
      recordMessage: () => {},
      recordConversation: () => {},
    },
    () => {},
    conversationStore,
    (message) => {
      notifications.push(message);
    },
  );

  router.handleUpstreamMessage({
    type: 'agent_text_delta',
    message_id: 'stream_1',
    delta: 'hello',
  }, 'hermes');
  assert.equal(notifications.length, 0);

  router.handleUpstreamMessage({
    type: 'agent_text_done',
    message_id: 'stream_1',
    text: 'hello',
  }, 'hermes');

  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].conversationId, 'hermes');
  assert.equal(notifications[0].gatewayId, 'hermes');
  assert.match(notifications[0].messageId, /^smsg_/);
  assert.equal(notifications[0].seq, 1);
  db.close();
});
