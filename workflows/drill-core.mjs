// drill-core — the pure engine for the deeper-native dynamic workflow.
//
// NO agents, NO filesystem, NO clock/random. Just the depth-first tree state
// machine + termination logic that model.py and judge.sh encode in deeper,
// ported to pure JS so it can be unit-tested at $0 (no LLM calls).
//
// The block between CORE:BEGIN / CORE:END is MIRRORED verbatim into
// workflows/deeper-native.js (workflow scripts are sandboxed and cannot import
// local files). tests/test-drill-core.mjs sync-guards the two copies.

/* CORE:BEGIN */
const BEDROCK_CATEGORIES = ['constraint', 'stated-value', 'prior-decision', 'external-rule', 'identity', 'empirical']

function initTree(seed) {
  return { root: { claim: seed, kind: 'open', children: [] } }
}

// DFS-deepest open leaf (model.py:find_next_open_leaf). Returns a path of
// child-indices from root, or null when every leaf is closed.
function findOpenLeaf(node, path = []) {
  if (node.kind === 'open' && node.children.length === 0) return path
  for (let i = 0; i < node.children.length; i++) {
    const r = findOpenLeaf(node.children[i], [...path, i])
    if (r) return r
  }
  return null
}

function walk(tree, path) {
  let n = tree.root
  for (const i of path) n = n.children[i]
  return n
}

function ancestorChain(tree, path) {
  const chain = [tree.root.claim]
  let n = tree.root
  for (const i of path) { n = n.children[i]; chain.push(n.claim) }
  return chain
}

// Apply a schema-typed answer to the node at `path`. The answer is a
// discriminated union — that is the whole termination fix (see README §3).
//   answer = { kind:'descend'|'bedrock'|'branch'|'stop', claim?, category?, depth_delta? }
function applyAnswer(tree, path, answer) {
  const active = walk(tree, path)
  if (answer.kind === 'stop') return { outcome: 'stop', terminate: true }
  if (answer.kind === 'bedrock') {
    const validCat = BEDROCK_CATEGORIES.includes(answer.category)
    active.kind = 'bedrock'
    active.category = validCat ? answer.category : 'identity'
    const violation = path.length < 2 ? 'shallow-bedrock' : (validCat ? undefined : 'invalid-bedrock-category')
    return { outcome: 'bedrock', violation }
  }
  if (answer.kind === 'branch') {
    if (path.length > 0 && answer.claim) {
      walk(tree, path.slice(0, -1)).children.push({ claim: answer.claim, kind: 'open', children: [] })
      return { outcome: 'branch' }
    }
    if (answer.claim) {
      active.children.push({ claim: answer.claim, kind: 'open', children: [] })
      return { outcome: 'descend', violation: 'branch-at-root' }
    }
    return { outcome: 'empty', violation: 'empty-claim', terminate: true }
  }
  // descend (default)
  if (!answer.claim) return { outcome: 'empty', violation: 'empty-claim', terminate: true }
  active.children.push({ claim: answer.claim, kind: 'open', children: [] })
  return { outcome: 'descend' }
}

// done = no open leaves (judge.sh). Pure; no exit-code scaffolding needed.
function judge(tree) {
  let total = 0, closed = 0
  const visit = (n) => { total++; if (n.kind === 'bedrock') closed++; n.children.forEach(visit) }
  visit(tree.root)
  return { done: findOpenLeaf(tree.root) === null, total, closed }
}

// Adversarial gate: given skeptic verdicts [{refuted:bool}], does the bedrock
// survive? Majority-refute kills it (forces one more descent).
function bedrockSurvives(verdicts) {
  if (!verdicts || verdicts.length === 0) return true // no skeptics -> no opposition -> survives (fail-open)
  const refutes = verdicts.filter(v => v && v.refuted).length
  return refutes < Math.ceil(verdicts.length / 2)
}

function render(node, prefix = '') {
  const mark = node.kind === 'bedrock' ? '◆ [BEDROCK:' + node.category + ']' : '●'
  let s = prefix + mark + ' ' + node.claim + '\n'
  node.children.forEach(c => { s += render(c, prefix + '   ') })
  return s
}

// Self-improvement (ralph + feedback). Mirrors harness/feedback.sh: count the
// DISTINCT runs (within a sliding window) in which each violation key appears;
// promote any key hitting `threshold` into a binding lesson. Pure + idempotent
// (re-running on the same log yields the same bans). The drill's cold prompt
// reads these next run, biasing questions away from repeated mistakes.
//   runLog: [{ run_id, violations: [key, ...] }, ...]  (chronological, recent last)
function promoteBans(runLog, options) {
  const window = (options && options.window) || 5
  const threshold = (options && options.threshold) || 2
  const recent = (runLog || []).slice(-window)
  const runsByKey = {}
  for (const run of recent) {
    const seen = {}
    for (const key of (run.violations || [])) {
      if (seen[key]) continue
      seen[key] = true
      runsByKey[key] = (runsByKey[key] || 0) + 1
    }
  }
  const bans = []
  for (const key of Object.keys(runsByKey).sort()) {
    if (runsByKey[key] >= threshold) {
      bans.push({ key, rationale: 'promoted: appeared in ' + runsByKey[key] + ' of last ' + recent.length + ' runs' })
    }
  }
  return { bans, promoted: bans.map(b => b.key), window: recent.length }
}

// The drill loop. Deterministic; no turn boundaries, so ADR-002's judge_result
// race cannot exist. `answerFn` and `verifyFn` are injected — scripted arrays
// in tests ($0), agent() calls in the workflow.
//   answerFn(round, {tree, path, chain, active}) -> answer
//   verifyFn(round, {bedrockClaim, category, chain}) -> [{refuted, deeper_claim?}]  (optional)
async function runDrill(seed, answerFn, options) {
  const cap = (options && options.cap) || 12
  const verifyFn = (options && options.verifyFn) || null
  const tree = initTree(seed)
  const trace = []
  const violations = []
  let round = 0, spinning = 0, status = 'auto_cap'
  while (round < cap) {
    const path = findOpenLeaf(tree.root)
    if (path === null) { status = 'passed'; break }
    round++
    const active = walk(tree, path)
    const chain = ancestorChain(tree, path)
    let answer = await answerFn(round, { tree, path, chain, active })
    if (answer.kind === 'bedrock' && verifyFn) {
      const verdicts = await verifyFn(round, { bedrockClaim: active.claim, category: answer.category, chain })
      if (!bedrockSurvives(verdicts)) {
        const refuter = verdicts.find(v => v && v.refuted && v.deeper_claim)
        if (refuter) { answer = { kind: 'descend', claim: refuter.deeper_claim, depth_delta: 0.2 }; violations.push('bedrock-refuted') }
      }
    }
    const res = applyAnswer(tree, path, answer)
    if (res.violation) violations.push(res.violation)
    trace.push({ round, depth: path.length, active: active.claim, answer, outcome: res.outcome })
    if (res.terminate) { status = 'aborted'; break }
    const d = typeof answer.depth_delta === 'number' ? answer.depth_delta : 0.2
    if (d <= 0) { spinning++; if (spinning >= 3) { status = 'spinning'; violations.push('spinning'); break } }
    else spinning = 0
  }
  return { status, rounds: round, tree, trace, violations }
}
/* CORE:END */

export {
  BEDROCK_CATEGORIES, initTree, findOpenLeaf, walk, ancestorChain,
  applyAnswer, judge, bedrockSurvives, render, runDrill, promoteBans,
}
