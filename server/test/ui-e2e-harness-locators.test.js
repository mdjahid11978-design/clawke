const assert = require('node:assert/strict');
const { readdirSync, readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const harness = readFileSync(
  join(root, 'client', 'integration_test', 'ui_e2e_app_test.dart'),
  'utf8',
);

test('UI E2E create_conversation uses semantic locators instead of injected UI keys', () => {
  const createConversation = harness.match(
    /Future<void> _createConversation[\s\S]*?\n}\n/,
  )?.[0];

  assert.ok(createConversation, 'create_conversation helper should exist');
  assert.doesNotMatch(createConversation, /ui_e2e_new_conversation_button/);
  assert.doesNotMatch(createConversation, /ui_e2e_conversation_name_field/);
  assert.doesNotMatch(createConversation, /ui_e2e_create_conversation_button/);
  assert.match(createConversation, /find\.byTooltip\('新建会话'\)/);
  assert.match(createConversation, /_waitForText\(tester, '新建会话'\)/);
  assert.match(createConversation, /find\.byType\(TextField\)/);
  assert.match(createConversation, /_tapButtonText\(tester, '创建'\)/);
});

test('UI E2E send_message uses visible chat input and send icon', () => {
  const sendMessage = harness.match(/Future<void> _sendMessage[\s\S]*?\n}\n/)?.[0];

  assert.ok(sendMessage, 'send_message helper should exist');
  assert.doesNotMatch(sendMessage, /ui_e2e_chat_input/);
  assert.doesNotMatch(sendMessage, /ui_e2e_send_button/);
  assert.match(sendMessage, /find\.widgetWithText\(TextField, '输入消息\.\.\.'\)/);
  assert.match(sendMessage, /_tapIcon\(tester, 'send'\)/);
});

test('UI E2E card actions support semantic tooltip and Material card surfaces', () => {
  assert.match(harness, /case 'tap_card_tooltip':/);
  assert.match(harness, /Future<void> _tapCardTooltip/);
  assert.match(harness, /find\.byTooltip\(tooltip\)/);
  assert.match(harness, /Future<Finder> _surfaceContainingText/);
  assert.match(harness, /find\.byType\(Card\)/);
  assert.match(harness, /find\.byType\(Material\)/);
  assert.match(harness, /find\.byType\(ListTile\)/);
});

test('UI E2E filter action supports segmented buttons without UI keys', () => {
  assert.match(harness, /Future<void> _tapFilterChip/);
  assert.match(harness, /widget is SegmentedButton/);
  assert.match(harness, /find\.widgetWithText\(FilterChip, text\)/);
});

test('P0 UI E2E cases do not depend on injected ui_e2e keys', () => {
  const caseDir = join(root, 'test', 'ui-e2e', 'test-cases');
  const caseFiles = readdirSync(caseDir).filter((name) => name.endsWith('.json'));

  assert.ok(caseFiles.length > 0, 'expected UI E2E case files');
  for (const fileName of caseFiles) {
    const text = readFileSync(join(caseDir, fileName), 'utf8');
    assert.doesNotMatch(text, /ui_e2e_/, `${fileName} should use semantic locators`);
  }
});
