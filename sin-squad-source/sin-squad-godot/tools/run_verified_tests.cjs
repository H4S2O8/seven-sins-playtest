/* Main-agent acceptance harness. A zero Godot exit code alone is not a pass. */
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const project = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const engineFlag = args.indexOf('--godot');
const engine = engineFlag >= 0 ? args[engineFlag + 1] : process.env.SIN_SQUAD_GODOT;
if (!engine || !fs.existsSync(engine)) {
  console.error('Provide the verified Godot console executable using --godot or SIN_SQUAD_GODOT.');
  process.exit(2);
}
const groupFlag = args.indexOf('--group');
const group = groupFlag >= 0 ? args[groupFlag + 1] : 'core';
const suites = [
  ['economy', 'run_economy_tests.gd', /ECONOMY_TESTS_PASSED count=([1-9]\d*)/, 379],
  ['economy', 'astra_session_review.gd', /ASTRA_SESSION_REVIEW checks=([1-9]\d*) failures=0/, 115],
  ['rules', 'rules_test.gd', /PASS: ([1-9]\d*) victory-rule assertions/, 97],
  ['rules', 'rules_symmetry_test.gd', /PASS: ([1-9]\d*) symmetry assertions/, 181710],
  ['battle', 'run_battle_tests.gd', /BATTLE_TESTS_PASSED count=([1-9]\d*)/, 40],
  ['battle', 'astra_battle_review.gd', /ASTRA_BATTLE_REVIEW passed=([1-9]\d*) failed=0/, 83],
  ['battle', 'astra_battle_symmetry.gd', /ASTRA_BATTLE_SYMMETRY checks=([1-9]\d*) pairs=60 failures=0/, 1741],
  ['integration', 'astra_assembler_test.gd', /ASTRA_ASSEMBLER_REVIEW checks=([1-9]\d*) failed=0/, 51],
  ['integration', 'astra_content_crosscheck.gd', /ASTRA_CONTENT_CROSSCHECK checks=([1-9]\d*) pairs=16 unique_handlers=34 failures=0/, 481],
  ['data', 'characters_data_test.gd', /CHARACTER_DATA_TEST_OK count=(98) unique_bindings=98/, 98],
  ['data', 'attachments_data_test.gd', /ATTACHMENT_DATA_TESTS_PASSED checks=([1-9]\d*) cards=100/, 416],
  ['data', 'environment_data_test.gd', /PASS: ([1-9]\d*) environment data assertions/, 1126],
];
if (!['core', 'all', 'economy', 'rules', 'battle', 'integration', 'data'].includes(group)) {
  console.error('Unknown test group: ' + group);
  process.exit(2);
}
const chosen = suites.filter(([g]) => group === 'all' || g === group || (group === 'core' && g !== 'data'));
let failures = 0;
const records = [];
for (const [category, script, marker, minimum] of chosen) {
  const file = path.join(project, 'tests', script);
  const start = Date.now();
  const proc = spawnSync(engine, ['--headless', '--path', project, '--script', `res://tests/${script}`], {
    cwd: project, encoding: 'utf8', windowsHide: true, timeout: 60000, maxBuffer: 8 * 1024 * 1024,
  });
  const output = `${proc.stdout || ''}\n${proc.stderr || ''}`;
  const match = output.match(marker);
  const runtimeError = /SCRIPT ERROR:|Parse Error:|Compile Error:|^ERROR:|^FAIL(?:ED|URE)?(?::|\s)/im.test(output);
  const ok = !proc.error && proc.status === 0 && !runtimeError && match && Number(match[1]) >= minimum;
  const record = { category, script, ok: Boolean(ok), count: match ? Number(match[1]) : null,
    duration_ms: Date.now() - start, exit: proc.status,
    test_sha256: fs.existsSync(file) ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : null };
  records.push(record);
  console.log(`${ok ? 'PASS' : 'FAIL'} ${script} count=${record.count} ${record.duration_ms}ms`);
  if (!ok) {
    failures++;
    console.error(proc.error ? proc.error.message : 'Missing pass marker, reduced coverage, or runtime error.');
    console.error(output);
  }
}
console.log(JSON.stringify({ status: failures ? 'REJECTED' : 'MECHANICAL_TESTS_ONLY_PASS',
  scope: group, excludes: ['visual acceptance', 'human input', 'all content semantics', 'published site'], records }, null, 2));
process.exitCode = failures ? 1 : 0;
