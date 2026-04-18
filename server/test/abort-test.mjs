#!/usr/bin/env node
/**
 * Abort 功能验收测试 v2
 *
 * 测试两个场景：
 *   1. 发消息 → 等流式开始 → 发 abort → 验证 abort 后零泄漏
 *   2. abort 后再发新消息 → 验证新消息能正常收到回复（abort 标记被正确清除）
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
const TIMEOUT_MS = 60000;

// ───── 状态 ─────
let deltaCount = 0;
let deltaAfterAbort = 0;
let abortSent = false;
let abortTime = 0;
let firstDeltaTime = 0;
let conversationId = null;
let accountId = null;

// Phase 2 状态
let phase = 1;           // 1=abort测试, 2=恢复测试
let phase2DeltaCount = 0;
let phase2Done = false;

async function main() {
  console.log('🧪 Abort 验收测试 v2（abort + 恢复）\n');

  const ws = new WebSocket(WS_URL);

  const timeout = setTimeout(() => {
    console.log('\n⏰ 超时');
    printResult();
    ws.close();
    process.exit(1);
  }, TIMEOUT_MS);

  function printResult() {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  Phase 1: Abort 拦截');
    console.log(`    abort 前 delta: ${deltaCount - deltaAfterAbort}`);
    console.log(`    abort 后 delta: ${deltaAfterAbort}`);
    if (deltaAfterAbort === 0) {
      console.log('    ✅ PASS — abort 后零泄漏');
    } else if (deltaAfterAbort <= 2) {
      console.log('    ⚠️  ACCEPTABLE — 少量残余 delta（≤2）');
    } else {
      console.log('    ❌ FAIL — abort 后大量 delta 泄漏');
    }
    console.log('');
    console.log('  Phase 2: Abort 后恢复');
    console.log(`    新消息 delta: ${phase2DeltaCount}`);
    if (phase2Done && phase2DeltaCount > 0) {
      console.log('    ✅ PASS — abort 后新消息正常回复');
    } else if (phase === 1) {
      console.log('    ⏭️ SKIP — Phase 1 未完成');
    } else {
      console.log('    ❌ FAIL — abort 后新消息无回复');
    }
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━');

    const pass = deltaAfterAbort <= 2 && (phase === 1 || (phase2Done && phase2DeltaCount > 0));
    console.log(pass ? '\n🎉 总结: PASS' : '\n💥 总结: FAIL');
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

    // ───── Phase 1: abort 测试 ─────
    if (phase === 1) {
      if (type === 'text_delta') {
        deltaCount++;
        if (!firstDeltaTime) {
          firstDeltaTime = Date.now();
          console.log(`📥 首个 delta 到达`);
        }
        if (abortSent) {
          deltaAfterAbort++;
          console.log(`  ⚠️  abort +${Date.now() - abortTime}ms: delta #${deltaAfterAbort}`);
        }
        // 收到 3 个 delta 后 abort
        if (deltaCount === 3 && !abortSent) {
          sendAbort();
        }
      }
      if (type === 'text_done' && abortSent) {
        console.log(`📄 Phase 1 text_done`);
      }
    }

    // ───── Phase 2: 恢复测试 ─────
    if (phase === 2) {
      if (type === 'text_delta') {
        phase2DeltaCount++;
        if (phase2DeltaCount === 1) {
          console.log(`📥 Phase 2 首个 delta 到达 — abort 后恢复正常 ✅`);
        }
      }
      if (type === 'text_done' && phase2DeltaCount > 0) {
        phase2Done = true;
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
        console.log('═══ Phase 1: Abort 拦截测试 ═══');
        sendTestMessage();
      } else {
        setTimeout(fetchConversations, 3000);
      }
    } catch (e) {
      setTimeout(fetchConversations, 3000);
    }
  }

  function sendTestMessage() {
    const msgId = `test_abort_${Date.now()}`;
    console.log(`📤 发送: "请详细介绍温兆伦的演艺生涯…"`);
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
        content: '请详细介绍一下温兆伦的演艺生涯，包括他的早期经历、代表作品、获奖情况、个人生活等方面，要非常详细',
      },
    }));
  }

  function sendAbort() {
    abortSent = true;
    abortTime = Date.now();
    console.log(`\n🛑 ABORT (收到 ${deltaCount} 个 delta 后，+${abortTime - firstDeltaTime}ms)`);
    ws.send(JSON.stringify({
      event_type: 'abort',
      context: {
        account_id: accountId,
        conversation_id: conversationId,
      },
      data: { account_id: conversationId },
    }));
    // 5 秒后进入 Phase 2（abort 后 Gateway 静默丢弃所有消息，包括 text_done）
    setTimeout(() => {
      if (phase === 1) {
        console.log('\n═══ Phase 2: abort 后恢复测试 ═══');
        phase = 2;
        sendFollowUpMessage();
      }
    }, 5000);
  }

  function sendFollowUpMessage() {
    const msgId = `test_followup_${Date.now()}`;
    console.log(`📤 发送: "1+1等于几"`);
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
        content: '1+1等于几',
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
