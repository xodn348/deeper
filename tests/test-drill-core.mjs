// $0 test suite for the deeper-native engine. No LLM, no network — just the
// pure tree state machine + a sync-guard that the workflow's inlined CORE block
// matches the canonical module. Run:  node tests/test-drill-core.mjs
//
// Fits deeper's mock-driven testing culture (cf. tests/test-answer-mock.sh):
// the drill loop is exercised end-to-end by feeding SCRIPTED answer objects in
// place of the agent() calls, so the entire control logic is verified for free.

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import {
  initTree, findOpenLeaf, walk, ancestorChain,
  applyAnswer, judge, bedrockSurvives, render, runDrill, promoteBans,
} from '../nodes/deeper/drill-core.mjs'

let pass = 0, fail = 0
function ok(cond, msg) { if (cond) { pass++ } else { fail++; console.error('  ✗ FAIL:', msg) } }
function eq(a, b, msg) { ok(JSON.stringify(a) === JSON.stringify(b), `${msg} (got ${JSON.stringify(a)}, want ${JSON.stringify(b)})`) }

// scripted answer source: returns the next answer in the list each round
const scripted = (answers) => { let i = 0; return async () => answers[i++] }

// ---- 1. descend deepens the cursor ----
{
  const t = initTree('root')
  applyAnswer(t, findOpenLeaf(t.root), { kind: 'descend', claim: 'a' })
  eq(findOpenLeaf(t.root), [0], '1a descend -> cursor [0]')
  applyAnswer(t, findOpenLeaf(t.root), { kind: 'descend', claim: 'b' })
  eq(findOpenLeaf(t.root), [0, 0], '1b second descend -> cursor [0,0]')
  eq(walk(t, [0, 0]).claim, 'b', '1c walk reaches b')
  eq(ancestorChain(t, [0, 0]), ['root', 'a', 'b'], '1d ancestor chain root->a->b')
}

// ---- 2. bedrock at depth>=2 closes + terminates a linear chain ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })
  applyAnswer(t, [0], { kind: 'descend', claim: 'b' })
  const res = applyAnswer(t, [0, 0], { kind: 'bedrock', category: 'constraint' })
  eq(res.outcome, 'bedrock', '2a outcome bedrock')
  ok(res.violation === undefined, '2b no shallow violation at depth 2')
  ok(judge(t).done === true, '2c judge.done true — every leaf closed')
  eq(findOpenLeaf(t.root), null, '2d no open leaf -> cursor null')
}

// ---- 3. bedrock at depth<2 -> shallow-bedrock violation ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })
  const res = applyAnswer(t, [0], { kind: 'bedrock', category: 'constraint' })
  eq(res.violation, 'shallow-bedrock', '3 shallow-bedrock flagged at depth 1')
}

// ---- 4. invalid bedrock category -> coerced to identity + violation ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })
  applyAnswer(t, [0], { kind: 'descend', claim: 'b' })
  const res = applyAnswer(t, [0, 0], { kind: 'bedrock', category: 'nonsense' })
  eq(res.violation, 'invalid-bedrock-category', '4a invalid category flagged')
  eq(walk(t, [0, 0]).category, 'identity', '4b coerced to identity')
}

// ---- 5. branch creates a sibling under the parent ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })
  applyAnswer(t, [0], { kind: 'descend', claim: 'b' })
  const res = applyAnswer(t, [0, 0], { kind: 'branch', claim: 'b2' })
  eq(res.outcome, 'branch', '5a outcome branch')
  eq(walk(t, [0, 1]).claim, 'b2', '5b sibling b2 under parent a')
  eq(findOpenLeaf(t.root), [0, 0], '5c cursor stays at deepest-leftmost open leaf b')
}

// ---- 6. branch at root degrades to descend (model.py parity) ----
{
  const t = initTree('root')
  const res = applyAnswer(t, [], { kind: 'branch', claim: 'x' })
  eq(res.outcome, 'descend', '6a branch-at-root degrades to descend')
  eq(res.violation, 'branch-at-root', '6b branch-at-root flagged')
  eq(walk(t, [0]).claim, 'x', '6c x appended as child of root')
}

// ---- 7. adversarial gate: majority-refute kills the bedrock ----
{
  ok(bedrockSurvives([{ refuted: false }, { refuted: false }, { refuted: true }]) === true, '7a 1/3 refute -> survives')
  ok(bedrockSurvives([{ refuted: true }, { refuted: true }, { refuted: false }]) === false, '7b 2/3 refute -> dies')
  ok(bedrockSurvives([{ refuted: true }]) === false, '7c 1/1 refute -> dies')
  ok(bedrockSurvives([{ refuted: false }]) === true, '7d 0/1 refute -> survives')
}

// ---- 8. runDrill terminates at bedrock (the anti-drift proof) ----
{
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0.3 },
    { kind: 'descend', claim: 'b', depth_delta: 0.3 },
    { kind: 'bedrock', category: 'constraint', depth_delta: 0.4 },
  ]), { cap: 12 })
  eq(res.status, 'passed', '8a status passed (closed, not capped)')
  eq(res.rounds, 3, '8b terminated in 3 rounds')
  eq(judge(res.tree).closed, 1, '8c exactly one bedrock')
}

// ---- 9. spinning guard: 3 consecutive non-positive deltas -> stop ----
{
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'x1', depth_delta: 0 },
    { kind: 'descend', claim: 'x2', depth_delta: 0 },
    { kind: 'descend', claim: 'x3', depth_delta: 0 },
    { kind: 'descend', claim: 'x4', depth_delta: 0 },
  ]), { cap: 12 })
  eq(res.status, 'spinning', '9a status spinning')
  eq(res.rounds, 3, '9b stopped after 3 flat rounds')
}

// ---- 10. adversarial gate inside runDrill: refute forces one more descent ----
{
  const verifyFn = async (round) =>
    round === 3 ? [{ refuted: true, deeper_claim: 'c' }] : [{ refuted: false }]
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0.3 },
    { kind: 'descend', claim: 'b', depth_delta: 0.3 },
    { kind: 'bedrock', category: 'constraint', depth_delta: 0.4 }, // round 3 -> refuted
    { kind: 'bedrock', category: 'constraint', depth_delta: 0.4 }, // round 4 -> survives
  ]), { cap: 12, verifyFn })
  eq(res.status, 'passed', '10a eventually passes')
  eq(res.rounds, 4, '10b one extra round from the refute')
  ok(res.violations.includes('bedrock-refuted'), '10c bedrock-refuted recorded')
  eq(res.tree.root.children[0].children[0].children[0].category, 'constraint', '10d bedrock landed at depth 3 (c)')
}

// ---- 11. render produces a readable tree ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })
  applyAnswer(t, [0], { kind: 'bedrock', category: 'identity' })
  const r = render(t.root)
  ok(r.includes('● root') && r.includes('◆ [BEDROCK:identity] a'), '11 render shows tree + bedrock marker')
}

// ---- 13. multi-sibling: cursor advances to next open leaf after closing one ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })          // [0]
  applyAnswer(t, [0], { kind: 'descend', claim: 'b' })         // [0,0]
  applyAnswer(t, [0, 0], { kind: 'branch', claim: 'b2' })      // sibling [0,1]
  applyAnswer(t, [0, 0], { kind: 'branch', claim: 'b3' })      // sibling [0,2]
  eq(findOpenLeaf(t.root), [0, 0], '13a cursor at deepest-leftmost b')
  applyAnswer(t, [0, 0], { kind: 'bedrock', category: 'constraint' })
  eq(findOpenLeaf(t.root), [0, 1], '13b cursor advances to next open sibling b2')
}

// ---- 14. cap hit without closing -> auto_cap ----
{
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0.3 },
    { kind: 'descend', claim: 'b', depth_delta: 0.3 },
    { kind: 'descend', claim: 'c', depth_delta: 0.3 },
    { kind: 'descend', claim: 'd', depth_delta: 0.3 },
  ]), { cap: 3 })
  eq(res.status, 'auto_cap', '14a status auto_cap')
  eq(res.rounds, 3, '14b stopped at cap')
  ok(findOpenLeaf(res.tree.root) !== null, '14c tree still has an open leaf')
}

// ---- 15. all skeptics approve -> bedrock survives, no extra round ----
{
  const verifyFn = async () => [{ refuted: false }, { refuted: false }, { refuted: false }]
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0.3 },
    { kind: 'descend', claim: 'b', depth_delta: 0.3 },
    { kind: 'bedrock', category: 'constraint', depth_delta: 0.4 },
  ]), { cap: 12, verifyFn })
  eq(res.status, 'passed', '15a passed')
  eq(res.rounds, 3, '15b no extra descent')
  ok(!res.violations.includes('bedrock-refuted'), '15c no refute recorded')
}

// ---- 16. empty verdicts (all skeptics failed) -> fail-open, bedrock survives ----
{
  ok(bedrockSurvives([]) === true, '16a empty verdicts -> survives (fail-open)')
  const verifyFn = async () => []
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0.3 },
    { kind: 'descend', claim: 'b', depth_delta: 0.3 },
    { kind: 'bedrock', category: 'constraint', depth_delta: 0.4 },
  ]), { cap: 12, verifyFn })
  eq(res.status, 'passed', '16b drill still terminates when verify is unavailable')
  ok(!res.violations.includes('bedrock-refuted'), '16c no spurious refute on empty verdicts')
}

// ---- 17. stop kind aborts ----
{
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0.3 },
    { kind: 'stop' },
  ]), { cap: 12 })
  eq(res.status, 'aborted', '17a stop -> aborted')
  eq(res.rounds, 2, '17b aborted at round 2')
}

// ---- 18. empty-claim descend aborts ----
{
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: '', depth_delta: 0.3 },
  ]), { cap: 12 })
  eq(res.status, 'aborted', '18a empty claim -> aborted')
  ok(res.violations.includes('empty-claim'), '18b empty-claim violation recorded')
}

// ---- 19. judge counts on a branched multi-bedrock tree ----
{
  const t = initTree('root')
  applyAnswer(t, [], { kind: 'descend', claim: 'a' })          // [0]
  applyAnswer(t, [0], { kind: 'descend', claim: 'b' })         // [0,0]
  applyAnswer(t, [0, 0], { kind: 'branch', claim: 'b2' })      // [0,1]
  applyAnswer(t, [0, 0], { kind: 'bedrock', category: 'constraint' })
  applyAnswer(t, [0, 1], { kind: 'bedrock', category: 'empirical' })
  const j = judge(t)
  ok(j.done === true, '19a all leaves closed')
  eq(j.closed, 2, '19b two bedrocks counted')
  eq(j.total, 4, '19c total nodes = root + a + b + b2 (bedrock marks in-place, no marker child)')
}

// ---- 20. spinning counter resets on a positive delta ----
{
  const res = await runDrill('root', scripted([
    { kind: 'descend', claim: 'a', depth_delta: 0 },
    { kind: 'descend', claim: 'b', depth_delta: 0 },
    { kind: 'descend', claim: 'c', depth_delta: 0.5 },   // reset
    { kind: 'descend', claim: 'd', depth_delta: 0 },
    { kind: 'descend', claim: 'e', depth_delta: 0 },
    { kind: 'bedrock', category: 'constraint', depth_delta: 0.4 },
  ]), { cap: 12 })
  eq(res.status, 'passed', '20 positive delta resets the spinning counter (no false spin-out)')
}

// ---- 21-25. promoteBans: the cross-run self-improvement flywheel ----
{
  // 21: below threshold -> no promotion
  eq(promoteBans([{ run_id: 'r1', violations: ['shallow-bedrock'] }], { threshold: 2 }).promoted, [], '21 one run -> nothing promoted')
  // 22: threshold met across distinct runs -> promote
  eq(promoteBans([
    { run_id: 'r1', violations: ['shallow-bedrock'] },
    { run_id: 'r2', violations: ['shallow-bedrock', 'spinning'] },
  ], { threshold: 2 }).promoted, ['shallow-bedrock'], '22 violation in 2 runs -> promoted')
  // 23: duplicate within ONE run counts once
  eq(promoteBans([{ run_id: 'r1', violations: ['spinning', 'spinning'] }], { threshold: 2 }).promoted, [], '23 dup within one run != two runs')
  // 24: sliding window drops old runs
  const log = [{ run_id: 'r1', violations: ['x'] }, { run_id: 'r2', violations: ['y'] }, { run_id: 'r3', violations: ['x'] }]
  eq(promoteBans(log, { window: 2, threshold: 2 }).promoted, [], '24a window=2 sees only r2,r3 -> x once -> none')
  eq(promoteBans(log, { window: 3, threshold: 2 }).promoted, ['x'], '24b window=3 sees x in r1,r3 -> promoted')
  // 25: idempotent + empty
  eq(promoteBans([], {}).promoted, [], '25a empty log -> no bans')
  const once = promoteBans([{ run_id: 'r1', violations: ['x'] }, { run_id: 'r2', violations: ['x'] }], { threshold: 2 })
  eq(once.bans.length, 1, '25b promotes once, not per-occurrence')
}

// ---- 26. SYNC GUARD: workflow's inlined CORE == canonical module CORE ----
{
  const dir = import.meta.dirname
  const moduleSrc = readFileSync(join(dir, '..', 'nodes', 'deeper', 'drill-core.mjs'), 'utf8')
  const wfSrc = readFileSync(join(dir, '..', 'workflows', 'deeper-native.js'), 'utf8')
  const extract = (s) => { const m = s.match(/\/\* CORE:BEGIN \*\/([\s\S]*?)\/\* CORE:END \*\//); return m ? m[1] : null }
  const norm = (s) => (s || '').replace(/\s+/g, ' ').trim()
  const a = extract(moduleSrc), b = extract(wfSrc)
  ok(a && b, '12a both files contain a CORE block')
  ok(norm(a) === norm(b), '12b workflow CORE mirrors drill-core.mjs verbatim (sync guard)')
}

console.log(`\n${fail === 0 ? '✓ ALL PASS' : '✗ FAILURES'}: ${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
