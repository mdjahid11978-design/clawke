const assert = require('node:assert/strict');
const { existsSync, mkdtempSync, readFileSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { pathToFileURL } = require('node:url');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const suiteRunnerPath = join(root, 'test', 'ui-e2e', 'tools', 'suite-runner.mjs');
const runSuitePath = join(root, 'test', 'ui-e2e', 'tools', 'run-suite.sh');

test('UI E2E suite report summarizes all case results and links individual reports', async () => {
  assert.equal(existsSync(suiteRunnerPath), true);
  const { writeSuiteReport } = await import(pathToFileURL(suiteRunnerPath).href);
  const suiteDir = mkdtempSync(join(tmpdir(), 'clawke-ui-e2e-suite-'));

  const result = writeSuiteReport({
    suiteDir,
    suiteId: 'suite-1',
    branch: 'test-branch',
    commit: 'abc1234',
    caseResults: [
      {
        ok: true,
        case_id: 'p0-pass',
        module: '会话',
        title: '通过用例',
        step_count: 3,
        assertion_count: 1,
        screenshot_count: 1,
        report_html: '/tmp/p0-pass/report.html',
        report_md: '/tmp/p0-pass/report.md',
      },
      {
        ok: false,
        case_id: 'p0-fail',
        module: '技能管理',
        title: '失败用例',
        step_count: 2,
        assertion_count: 1,
        screenshot_count: 1,
        report_html: '/tmp/p0-fail/report.html',
        report_md: '/tmp/p0-fail/report.md',
        diagnostic_report: '/tmp/p0-fail/diagnostic-report.md',
        failure_type: 'test_infrastructure',
        bug_report_allowed: false,
        error: 'expected text not found',
      },
    ],
  });

  const json = JSON.parse(readFileSync(result.result_json, 'utf8'));
  assert.equal(json.total_count, 2);
  assert.equal(json.passed_count, 1);
  assert.equal(json.failed_count, 1);
  assert.deepEqual(
    json.case_results.map((item) => [item.case_id, item.status]),
    [
      ['p0-pass', 'success'],
      ['p0-fail', 'fail'],
    ],
  );

  const html = readFileSync(result.report_html, 'utf8');
  assert.match(html, /<th>total_count<\/th><td>2<\/td>/);
  assert.match(html, /<th>passed_count<\/th><td>1<\/td>/);
  assert.match(html, /<th>failed_count<\/th><td>1<\/td>/);
  assert.match(html, /p0-pass/);
  assert.match(html, /<th>所属模块\/页面<\/th>/);
  assert.match(html, /<th>测试内容<\/th>/);
  assert.match(html, /会话/);
  assert.match(html, /技能管理/);
  assert.match(html, /通过用例/);
  assert.match(html, /失败用例/);
  assert.match(html, /p0-fail/);
  assert.match(html, /href="\/tmp\/p0-pass\/report\.html"/);
  assert.match(html, /test_infrastructure/);
  assert.match(html, /bug_report_allowed/);
  assert.match(html, /href="\/tmp\/p0-fail\/diagnostic-report\.md"/);
  assert.match(html, /expected text not found/);

  const markdown = readFileSync(result.report_md, 'utf8');
  assert.match(markdown, /所属模块\/页面/);
  assert.match(markdown, /测试内容/);
  assert.match(markdown, /会话/);
  assert.match(markdown, /技能管理/);
});

test('UI E2E suite runner discovers selected cases in stable order', async () => {
  assert.equal(existsSync(suiteRunnerPath), true);
  const { discoverCases } = await import(pathToFileURL(suiteRunnerPath).href);
  const caseDir = mkdtempSync(join(tmpdir(), 'clawke-ui-e2e-cases-'));
  writeFileSync(join(caseDir, 'b-case.json'), '{"id":"b-case","title":"B"}\n');
  writeFileSync(join(caseDir, 'a-case.json'), '{"id":"a-case","title":"A"}\n');

  assert.deepEqual(
    discoverCases({ caseDir, selectedCaseIds: [] }).map((item) => item.id),
    ['a-case', 'b-case'],
  );
  assert.deepEqual(
    discoverCases({ caseDir, selectedCaseIds: ['b-case'] }).map((item) => item.id),
    ['b-case'],
  );
});

test('UI E2E suite shell wrapper invokes suite runner', () => {
  assert.equal(existsSync(runSuitePath), true);
  assert.match(readFileSync(runSuitePath, 'utf8'), /suite-runner\.mjs/);
});

test('UI E2E suite report uses system colors instead of fixed light backgrounds', () => {
  assert.equal(existsSync(suiteRunnerPath), true);
  const suiteRunner = readFileSync(suiteRunnerPath, 'utf8');
  assert.doesNotMatch(suiteRunner, /background:\s*#fff\b/i);
  assert.doesNotMatch(suiteRunner, /background:\s*#f6f7f9\b/i);
  assert.doesNotMatch(suiteRunner, /background:\s*#eef2f6\b/i);
  assert.match(suiteRunner, /color-scheme:\s*light dark/);
  assert.match(suiteRunner, /background:\s*Canvas/);
  assert.match(suiteRunner, /color:\s*CanvasText/);
});
