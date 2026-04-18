#!/usr/bin/env node
/**
 * abort-no-repeat-test.mjs
 * 验证：abort 后再发新问题，AI 不会重复回答被中止的问题。
 *
 * 流程：
 *   1. 发送 "1+51=?" → 等待首个 delta → abort
 *   2. 等 5 秒后发送 "2+2=?" → 收集完整回复
 *   3. 检查回复中是否包含 "52"（1+51 的答案）→ 包含=FAIL
 */
import WebSocket from 'ws';
import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

// 读取 relay token
let token = '';
try {
  const cfg = JSON.parse(readFileSync(join(homedir(), '.clawke', 'clawke.json'), 'utf-8'));
  token = cfg.relay?.token || '';
} catch {}

const WS_URL = `ws://127.0.0.1:8780/ws${token ? '?token=' + token : ''}`;
const TIMEOUT_MS = 90000;

// ───── 状态 ─────
let conversationId = null;
let accountId = null;
let phase = 0;             // 0=init, 1=abort测试, 2=no-repeat测试
let phase1Deltas = 0;
let abortSent = false;
let phase2FullText = '';
let phase2DeltaCount = 0;
let phase2Done = false;

async function main() {
  console.log('🧪 Abort No-Repeat 测试（abort 后 AI 不重复回答）\n');

  const ws = new WebSocket(WS_URL);

  const timeout = setTimeout(() => {
    console.log('\n⏰ 超时');
    printResult();
    ws.close();
    process.exit(1);
  }, TIMEOUT_MS);

  function printResult() {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`  Phase 1: Abort 拦截`);
    console.log(`    abort 前 delta: ${phase1Deltas}`);
    console.log('');
    console.log(`  Phase 2: No-Repeat 验证`);
    console.log(`    AI 回复: ${phase2FullText.slice(0, 120)}`);
    const contains52 = phase2FullText.includes('52');
    const contains1plus51 = phase2FullText.includes('1+51') || phase2FullText.includes('1 + 51');
    const contains4 = phase2FullText.includes('4');
    console.log(`    包含 "52" (1+51答案): ${contains52 ? '是 ❌' : '否 ✅'}`);
    console.log(`    包含 "1+51": ${contains1plus51 ? '是 ❌' : '否 ✅'}`);
    console.log(`    包含 "4" (2+2答案): ${contains4 ? '是 ✅' : '否 ⚠️'}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━');

    const pass = !contains52 && !contains1plus51 && phase2Done;
    console.log(pass ? '\n✅ PASS — AI 没有重复回答被中止的问题' : '\n❌ FAIL — AI 重复回答了被中止的问题');
    return pass;
  }

  ws.on('open', () => {
    console.log('✅ 已连接 Clawke Server');
    ws.send(JSON.stringify({
      id: 'sync_init',
      protocol: 'cup_v2',
      event_type: 'sync',
      data: { last_seq: 0, app_version: '0.1.0', platform: 'test' },
    }));
  });

  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    const type = msg.payload_type || msg.type;

    // 捕获 AI 在线状态
    if (type === 'system_status' && msg.status === 'ai_connected') {
      accountId = msg.account_id;
      console.log(`🤖 AI 后端在线: account=${accountId}`);
    }

    // sync 完成 → 获取会话
    if (type === 'sync_response') {
      fetchConversations();
      return;
    }

    // ───── Phase 1: 发送 1+51, abort ─────
    if (phase === 1) {
      if (type === 'text_delta') {
        phase1Deltas++;
        if (phase1Deltas === 1) {
          console.log('📥 首个 delta 到达');
        }
        // 收到首个 delta 后立刻 abort
        if (phase1Deltas >= 1 && !abortSent) {
          abortSent = true;
          console.log(`\n🛑 ABORT (收到 ${phase1Deltas} deltas)`);
          ws.send(JSON.stringify({
            event_type: 'abort',
            context: {
              account_id: accountId,
              conversation_id: conversationId,
            },
            data: { account_id: conversationId },
          }));
          // 5 秒后进入 Phase 2
          setTimeout(() => {
            if (phase === 1) {
              console.log('\n═══ Phase 2: No-Repeat 验证 ═══');
              phase = 2;
              sendPhase2Message();
            }
          }, 5000);
        }
      }
    }

    // ───── Phase 2: 发送 2+2, 检查回复 ─────
    if (phase === 2) {
      if (type === 'text_delta') {
        phase2DeltaCount++;
        phase2FullText += msg.delta || '';
        if (phase2DeltaCount === 1) {
          console.log('📥 Phase 2 首个 delta 到达');
        }
      }
      if (type === 'text_done' && phase2DeltaCount > 0) {
        phase2Done = true;
        if (msg.full_text) phase2FullText = msg.full_text;
        console.log(`📄 Phase 2 text_done (${phase2DeltaCount} deltas)`);
        setTimeout(() => {
          const pass = printResult();
          clearTimeout(timeout);
          ws.close();
          process.exit(pass ? 0 : 1);
        }, 500);
      }
    }
  });

  async function fetchConversations() {
    try {
      const resp = await fetch('http://127.0.0.1:8780/api/conversations', {
        headers: token ? { 'Authorization': `Bearer ${token}` } : {},
      });
      const data = await resp.json();
      const convs = Array.isArray(data) ? data : [];
      const conv = convs.find(c => c.account_id === accountId) || convs[0];
      if (conv) {
        conversationId = conv.id;
        accountId = accountId || conv.account_id;
        console.log(`📋 会话: ${conversationId}\n`);
        console.log('═══ Phase 1: 发送 "1+51=?" 然后 abort ═══');
        phase = 1;
        sendPhase1Message();
      } else {
        setTimeout(fetchConversations, 3000);
      }
    } catch (e) {
      setTimeout(fetchConversations, 3000);
    }
  }

  function sendPhase1Message() {
    const msgId = `test_norepeat_p1_${Date.now()}`;
    console.log('📤 发送: "请详细计算 1+51=? 并解释每一步"');
    ws.send(JSON.stringify({
      id: msgId,
      protocol: 'cup_v2',
      event_type: 'user_message',
      context: {
        client_msg_id: msgId,
        account_id: accountId,
        conversation_id: conversationId,
        device_id: 'test_device',
      },
      data: {
        type: 'text',
        content: '请详细计算 1+51=? 并一步一步解释计算过程，写得越详细越好',
      },
    }));
  }

  function sendPhase2Message() {
    const msgId = `test_norepeat_p2_${Date.now()}`;
    console.log('📤 发送: "2+2=?"');
    ws.send(JSON.stringify({
      id: msgId,
      protocol: 'cup_v2',
      event_type: 'user_message',
      context: {
        client_msg_id: msgId,
        account_id: accountId,
        conversation_id: conversationId,
        device_id: 'test_device',
      },
      data: {
        type: 'text',
        content: '2+2=?',
      },
    }));
    console.log('⏳ 等待回复...');
  }

  ws.on('error', (err) => {
    console.error(`❌ WebSocket 错误: ${err.message}`);
    process.exit(1);
  });
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
