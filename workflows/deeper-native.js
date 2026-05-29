// deeper-native — deeper's philosophy as a native dynamic workflow.
//
// See workflows/README.md for principle, architecture, and how this differs
// from a vanilla dynamic workflow.
//
// The block between CORE:BEGIN / CORE:END is a verbatim MIRROR of
// workflows/drill-core.mjs (workflow scripts are sandboxed and cannot import
// local files). It is sync-guarded by tests/test-drill-core.mjs — if you edit
// the engine, edit drill-core.mjs and paste the same block here, or the test fails.

export const meta = {
  name: 'deeper-native',
  description: "Self-improving depth-first interview on the dynamic Workflow runtime: cold-context ralph loop + DFS tree state machine + schema-typed termination + adversarial bedrock gate + cross-run BANS promotion. Pass {seed, cap?, verify_fanout?, bans?} via args.",
  phases: [
    { title: 'Bootstrap', detail: 'load accumulated lessons (BANS) + run log from the store' },
    { title: 'Drill', detail: 'cold Q/A per round, DFS to bedrock' },
    { title: 'Verify', detail: 'skeptics try to refute each bedrock candidate' },
    { title: 'Evolve', detail: 'record violations, promote recurring ones to BANS, persist the run' },
  ],
}

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

// ============================================================================
//  DRIVER — the only part that touches agent()/parallel(). The engine above is
//  pure; everything LLM-shaped lives here.
// ============================================================================

// args may arrive as an object OR a JSON-encoded string depending on how the
// workflow is invoked; normalize both so {seed, cap, ...} always take effect.
const A = (() => { try { return typeof args === 'string' ? JSON.parse(args) : (args || {}) } catch (_) { return {} } })()
const DEFAULT_SEED = 'Each deeper round must run in COLD context (a fresh process whose only input is the prompt + accumulated lessons + the ancestor chain — never the running session history).'
const SEED = (typeof A.seed === 'string' && A.seed.trim()) ? A.seed.trim() : DEFAULT_SEED
const FANOUT = Math.max(1, Math.min(7, Number(A.verify_fanout) || 3))
// Per-round answer fan-out: each round sprays ANSWER_FANOUT cold candidate answers
// (different drilling angles) in parallel, then a judge picks the deepest. THIS is
// what the workflow runtime buys — N independent attempts per round, not one.
const ANSWER_FANOUT = Math.max(1, Math.min(7, Number(A.answer_fanout) || 3))
// Rough budget heuristic: each round = one Q + ANSWER_FANOUT candidates + one judge;
// a bedrock round additionally spins up FANOUT skeptics.
const PER_ROUND = 45000 + ANSWER_FANOUT * 35000 + FANOUT * 30000
const CAP = Math.max(4, Math.min(30, Number(A.cap) || (budget && budget.total ? Math.floor(budget.total / PER_ROUND) : 12)))
let bans = Array.isArray(A.bans) ? [...A.bans] : []

// Self-improvement store (under $DEEPER_HOME, default ~/.deeper). Agents read/write here.
const STORE = '$HOME/.deeper/runs/deeper-native'
const renderBansMd = (b) => '# deeper-native — binding lessons (auto-promoted across runs)\n\n' +
  (b.length ? b.map(x => `- **${x.key}** — ${x.rationale}`).join('\n') : '_(none yet)_') + '\n'

const BOOT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['bans', 'run_log'],
  properties: {
    bans: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['key'], properties: { key: { type: 'string' }, rationale: { type: 'string' } } } },
    run_log: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['run_id', 'violations'], properties: { run_id: { type: 'string' }, violations: { type: 'array', items: { type: 'string' } } } } },
  },
}

// The cold PROMPT — re-injected verbatim every round (ralph). DNA #1.
const PROMPT = `You are running \`deeper\` — a DEPTH-FIRST interview that drills ONE claim straight down to its BEDROCK. You do NOT survey, enumerate options, compare alternatives, or widen scope. One claim, drilled vertically.

PRESSURE LADDER (walk downward): (1) Example — demand one concrete instance. (2) Hidden assumption — "what must be true for that to hold?" (3) Boundary — "where does it break?" (4) Root-cause-vs-symptom — "remove this; does the underlying thing persist?"
ONTOLOGIST 4Q (when the ladder stalls, pick one): What IS this, really? · Cause or symptom? · What must exist first? · What are we assuming?
FORBIDDEN — never emit these (they widen): "what else?", "any other...", "what are the options?", "how does this compare to X?", "would you like to explore Y?".

BEDROCK TEST: a claim is bedrock iff the honest answer to the next "why?" is terminal —
  constraint (physics/economics/time) · stated-value (a chosen preference) · prior-decision (settled, won't revisit) · external-rule (law/contract/standard) · identity (it is what it is, definitionally) · empirical (measured/observed). If "why?" still has a CONTESTABLE answer, it is NOT bedrock — keep drilling. Do not declare bedrock before depth 2 (shallow-bedrock error).`

// A's answer is a DISCRIMINATED UNION validated at the tool layer. THIS is the
// structural fix for deeper's confirmed bug (prose-buried "BEDROCK:" never
// recognized -> 50-round drift). DNA #3, repaired.
const ANSWER_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['kind', 'depth_delta', 'rationale'],
  properties: {
    kind: { enum: ['descend', 'bedrock', 'branch', 'stop'] },
    claim: { type: 'string', description: 'for descend: the deeper claim. for branch: the parallel-cause sibling. omit for bedrock/stop.' },
    category: { enum: BEDROCK_CATEGORIES, description: 'required iff kind=bedrock' },
    depth_delta: { type: 'number', description: '+0.4 hit bedrock, +0.3 surfaced hidden assumption/boundary, +0.2 cited a concrete instance, 0 restatement, negative if it widened' },
    rationale: { type: 'string', description: 'one short sentence: why this kind' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean', description: 'true if you found one more honest "why?" with a contestable answer (NOT yet bedrock)' },
    deeper_claim: { type: 'string', description: 'if refuted: the deeper claim the chain should descend into' },
    reason: { type: 'string', description: 'one sentence' },
  },
}

// Each per-round candidate is forced down a DIFFERENT angle so the fan-out is
// genuinely diverse (not N near-identical answers).
const ANGLES = [
  'mechanism — name the concrete causal step that makes the active claim true',
  'hidden assumption — surface what must already be true for it to hold',
  'boundary / counterexample — find where it breaks, or a case it fails',
  'root-vs-symptom — strip this away; does the underlying thing persist?',
  'incentive / constraint — whose decision or which hard limit forces it',
  'concrete instance — demand one specific, dated, named example',
  'definition — what IS this, really, at the most precise level',
]

// The judge's pick over the round's candidate answers.
const SELECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['index', 'reason'],
  properties: {
    index: { type: 'integer', description: '0-based index of the candidate that drills DEEPEST toward bedrock: most specific, most genuinely contestable, best-grounded. A correctly-justified bedrock outranks a weak/restating descend.' },
    reason: { type: 'string', description: 'one sentence: why this candidate wins' },
  },
}

function buildCtx(chain, active) {
  return `${PROMPT}

BINDING LESSONS (from earlier rounds/runs — obey):
${bans.length ? bans.map(b => `- ${b}`).join('\n') : '- (none yet)'}

ANCESTOR CHAIN (root -> active):
${chain.map((c, i) => `${i}. ${c}`).join('\n')}

ACTIVE CLAIM to drill: "${active.claim}"`
}

// answerFn: one cold Q agent, then ANSWER_FANOUT cold candidate A agents IN
// PARALLEL (each a different drilling angle), then a judge picks the deepest.
// This is the per-round fan-out — the reason the drill lives on the workflow
// runtime: parallel() gives N independent attempts every round, and the judge
// selects the one that descends hardest toward bedrock before the cursor moves.
async function answerFn(round, { chain, active }) {
  const ctx = buildCtx(chain, active)
  const q = (await agent(
    `${ctx}\n\nEmit EXACTLY ONE depth question targeting the ACTIVE CLAIM. No preamble, one line.`,
    { label: `R${round}·Q`, phase: 'Drill' }
  )).trim()

  const ask = (k) =>
    `${ctx}\n\nThe interview is autonomous — you stand in for the most honest, informed respondent.\nQUESTION: ${q}\n\nYou are candidate #${k + 1} of ${ANSWER_FANOUT}. Drill specifically from THIS angle: ${ANGLES[k % ANGLES.length]}.\nAnswer by drilling one level deeper, OR declare bedrock if the honest "why?" is now terminal, OR branch a genuinely parallel cause, OR stop.\nIf kind="bedrock" you MUST set category to one of: ${BEDROCK_CATEGORIES.join(', ')}. If kind="descend" or "branch" you MUST set claim.`

  // FAN OUT: N candidate answers in parallel, each forced down a distinct angle.
  const candidates = (await parallel(Array.from({ length: ANSWER_FANOUT }, (_, k) => () =>
    agent(ask(k), { label: `R${round}·A${k + 1}`, phase: 'Drill', schema: ANSWER_SCHEMA })
  ))).filter(Boolean)

  if (candidates.length === 0) return { kind: 'stop', depth_delta: 0, rationale: 'no candidate answer survived' }
  if (candidates.length === 1) return candidates[0]

  // JUDGE: pick the candidate that drills deepest toward bedrock.
  const list = candidates.map((c, i) =>
    `[${i}] kind=${c.kind}${c.category ? '/' + c.category : ''} Δ${c.depth_delta} ${c.kind === 'bedrock' ? '(bedrock)' : JSON.stringify(c.claim || '')} — ${c.rationale}`
  ).join('\n')
  try {
    const sel = await agent(
      `${ctx}\n\nQUESTION asked this round: ${q}\n\n${candidates.length} candidate answers were generated, each from a different angle. Pick the ONE that drills DEEPEST toward bedrock — most specific, most genuinely contestable, best-grounded. Reject restatements and any that widen the scope.\n\nCANDIDATES:\n${list}`,
      { label: `R${round}·judge`, phase: 'Drill', schema: SELECT_SCHEMA }
    )
    if (sel && Number.isInteger(sel.index) && sel.index >= 0 && sel.index < candidates.length) return candidates[sel.index]
  } catch (_) { /* fall through to heuristic */ }
  // fallback if the judge fails: deepest by depth_delta.
  return candidates.reduce((best, c) => (c.depth_delta > best.depth_delta ? c : best), candidates[0])
}

// verifyFn: FANOUT skeptics try to refute the bedrock candidate, in parallel.
// This is the one place breadth enters — in service of depth discipline.
async function verifyFn(round, { bedrockClaim, category, chain }) {
  const verdicts = await parallel(Array.from({ length: FANOUT }, (_, k) => () =>
    agent(
      `You are skeptic #${k + 1} of ${FANOUT}. The drill wants to declare this claim BEDROCK (category: ${category}):\n"${bedrockClaim}"\n\nAncestor chain (root -> here):\n${chain.map((c, i) => `${i}. ${c}`).join('\n')}\n\nTry to ask ONE more honest "why?" whose answer is still CONTESTABLE (i.e. not yet a terminal axiom). If you find one, set refuted=true and give the deeper_claim it descends into. If the claim is genuinely terminal under the bedrock test, set refuted=false.`,
      { label: `R${round}·verify${k + 1}`, phase: 'Verify', schema: VERDICT_SCHEMA }
    )
  ))
  return verdicts.filter(Boolean)
}

// ---- Bootstrap: load accumulated lessons + run log (agents do FS; body stays pure) ----
phase('Bootstrap')
let priorRunLog = []
try {
  const boot = await agent(
    `Read the deeper-native self-improvement store and return its contents — this is how the drill carries lessons across runs. Use Bash to cat each file if it exists; if a file is missing, treat it as empty.
1. BANS:    ${STORE}/bans.json     — a JSON array of {key, rationale}. Missing -> [].
2. RUN LOG: ${STORE}/runlog.jsonl  — one JSON object per line: {run_id, violations:[...]}. Missing -> [].
Parse and return both exactly as found. Do NOT invent entries.`,
    { label: 'bootstrap', phase: 'Bootstrap', schema: BOOT_SCHEMA }
  )
  priorRunLog = boot.run_log || []
  const loaded = (boot.bans || []).map(b => b.rationale ? `${b.key} (${b.rationale})` : b.key)
  bans = [...loaded, ...bans]
  log(`bootstrap: ${loaded.length} lesson(s) loaded, ${priorRunLog.length} prior run(s)`)
} catch (e) {
  log('bootstrap: fresh store (' + (e && e.message) + ')')
}

phase('Drill')
log(`drilling: "${SEED.slice(0, 90)}..." (cap=${CAP}, verify_fanout=${FANOUT}, bans=${bans.length})`)
const result = await runDrill(SEED, answerFn, { cap: CAP, verifyFn })
log(`drill ${result.status} in ${result.rounds} rounds`)

// ---- assemble outcome (pure JS) ----
const treeStr = render(result.tree.root)
const bedrocks = []
;(function collect(n, d) { if (n.kind === 'bedrock') bedrocks.push({ depth: d, category: n.category, claim: n.claim }); n.children.forEach(c => collect(c, d + 1)) })(result.tree.root, 0)
const violations_total = result.violations.reduce((m, v) => (m[v] = (m[v] || 0) + 1, m), {})
const outcome = { status: result.status, rounds: result.rounds, seed: SEED, bedrocks, violations_total }

// ---- Evolve: record this run, promote recurring violations, persist (agents do FS) ----
// The PROMOTION is computed here by the pure promoteBans(); the agent only writes files.
phase('Evolve')
const evolved = promoteBans([...priorRunLog, { run_id: 'pending', violations: result.violations }], { window: 5, threshold: 2 })
let run_dir = null
try {
  const ev = await agent(
    `Persist this deeper-native run AND update the self-improvement store. Use Bash for paths/append; the Write tool for exact file contents (no heredocs).
1. Bash:  RUN_ID="deeper-native-$(date -u +%Y%m%dT%H%M%SZ)" ; DIR="$HOME/.deeper/runs/deeper-native/$RUN_ID" ; mkdir -p "$DIR" ; echo "$DIR"
2. Write "<DIR>/outcome.json" EXACTLY:
${JSON.stringify(outcome, null, 2)}
3. Write "<DIR>/tree.txt" EXACTLY:
${treeStr}
4. Append ONE line to "$HOME/.deeper/runs/deeper-native/runlog.jsonl" (create it if missing), using the RUN_ID from step 1. Run exactly:
   printf '%s\\n' '{"run_id":"'"$RUN_ID"'","violations":${JSON.stringify(result.violations)}}' >> "$HOME/.deeper/runs/deeper-native/runlog.jsonl"
5. Write "$HOME/.deeper/runs/deeper-native/bans.json" EXACTLY (the recomputed promoted lessons):
${JSON.stringify(evolved.bans, null, 2)}
6. Write "$HOME/.deeper/runs/deeper-native/BANS.md" EXACTLY:
${renderBansMd(evolved.bans)}
Return ONLY the absolute DIR path (nothing else).`,
    { label: 'evolve', phase: 'Evolve' }
  )
  run_dir = (ev || '').trim() || null
} catch (e) {
  log('evolve failed (non-fatal): ' + (e && e.message))
}
log(`evolve: ${evolved.promoted.length} active lesson(s)${evolved.promoted.length ? ' [' + evolved.promoted.join(', ') + ']' : ''}`)

return { outcome, tree: treeStr, trace: result.trace, active_bans: evolved.bans, promoted: evolved.promoted, run_dir }
