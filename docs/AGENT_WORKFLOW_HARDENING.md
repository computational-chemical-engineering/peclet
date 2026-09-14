# Agent workflow hardening — design note

*Written 2026-09-14 against the brief `fable-brief-workflow-hardening.md` (seven failure classes
A–G, ~20 verified events over 14 days, ~12 concurrent sessions). Status: **proposal** — nothing here
is installed. Everything named as a file, flag or workflow was opened and checked on the day; where
a claim rests on something not checked, the note says so.*

---

## Diagnosis

Every event in the record is a claim whose truth condition sat one hop away from the evidence the
agent actually looked at: `git push` exit code versus the live site (A1); a probe workflow versus
the tag workflow (A2); the check that *runs* pages versus the job that *renders* them (A3); "my
commits" versus the range `git push` actually sends (B1, B2); a green job at 4 h 59 versus a cap at
6 h 00 (C1); np=1 bitwise versus np=4 at another thread count (D1); the badge markdown versus the
file it points to (E1); a request for the node versus a request for its memory (G1). In each case
the agent verified something local, immediate and under its own control, and reported something
remote, delayed, or owned by someone else. The bridge was an assumption — and in every class except
F the assumption's falsity was already written down, in a file the agent could have opened in one
command, or had loaded at session start. So the record does **not** show constraints being lost. It
shows constraints held in *pull* media (a note the agent must decide to open) while the actions that
violate them go through *push* media (a tool call whose return the agent cannot avoid seeing). An
agent under task pressure acts on the tool's return; a check that is not in the return is an
optional extra step, and optional steps are what get skipped in the sixth hour. G3 — the one trap in
the record that was avoided — was avoided because its note is in the per-session loaded index: push,
not pull. That is the whole diagnosis: **the checks exist; nothing binds them to the action.**

Three consequences fix the shape of the answer. (i) A check must live *in the path the action
takes* — inside the tool's admission (a hook that refuses) or inside its return (a wrapper whose exit
status encodes the downstream truth) — never beside it in a document. (ii) The places to bind are
the irreversible boundaries — commit, push, tag, submit, settings change — few enough to enumerate,
rare enough that a sub-second check is free, and exactly where the claim–evidence gap opens. Nothing
should bind to "every Bash call" or "every file write". (iii) Class D is the same fault turned on the
tests: a gate is a claim about the code's reproducibility class, and D1–D3 assumed that class instead
of measuring it — so the validity criterion must demand the measurement as part of the gate. Class B
is the same fault with another session as the counterparty: "the range I am pushing is mine" is an
assumption about shared state that git can check in milliseconds and nobody asked. Class F alone is
not a binding failure but a reporting-discipline one, and gets the weakest treatment below.

**Addendum, 2026-09-14, from the release session that executed against this note's findings.** Pull
media has a second failure mode this diagnosis understated: it can be *false*, not merely unread.
`RELEASE.md` §11 stated that the CUDA wheel job "runs only on tags", and on that basis §11.2 filed a
`workflow_dispatch` rehearsal as future work. Neither is true: no `cuda-wheel` job in any of the four
wheel-building repos carries an `if:` — only `publish` is tag-gated — so the rehearsal existed, in all
four, the whole time. The capability was there; the document denied it; and the voro job that was
killed at the 6 h cap is exactly the job that rehearsal would have exercised. So the escape needed no
skipped step: an agent that read the guide, believed it, and acted on it would still have been
stranded. That strengthens rather than weakens the thesis — a check bound to the action would have
refused the tag regardless of what the prose claimed — but it adds an obligation the contract below
does not carry: **a document asserting that a capability is absent should be as checkable as a
document asserting one is present**, or it becomes a licence not to try. Corrected in `RELEASE.md`
(`60313e0`), with the rehearsal's first use measured in voro run `34865945237` (four CUDA jobs,
one per interpreter, all started within one second of each other).

---

## The contract

Rules of the contract. Every check is a script with an exit code. *Refuse* means the action does not
happen and the reason — with the remedy — is what the agent sees next. Every bypass is an explicit
environment variable that the hook **logs** (`.git/peclet/overrides.log`: time, session, variable,
the DECISION line the agent must supply), so "never stall" survives and every override is greppable
the next morning. Where a boundary is a git hook, it fires for agents, humans and scripts alike;
where it is a Claude Code hook, it fires only for sessions that load the settings — which is why the
highest-leverage rows are git hooks.

| # | Boundary | Check (runnable) | Surface | On failure | Classes | Cost |
|---|---|---|---|---|---|---|
| 1 | **push** (every repo) | The range `remote..local` for each pushed branch carries **one** `Claude-Session:` trailer value (trailer-less commits count as the human's). Computed by `git log --format='%H %(trailers:key=Claude-Session,valueonly)' <remote>..<local>` on the stdin `pre-push` receives. | git `pre-push` in `suite/tools/githooks/`, activated per repo by `core.hooksPath` (worktrees share it). | Refuse; print the foreign commits with their session URLs and the three-command detour of §Coordination. Bypass `PECLET_PUSH_MULTI_SESSION=1`, logged. | B1, B2 | ~20 ms |
| 2 | **push** | `.git/peclet/PUSH_HOLD` exists naming this branch → refuse and print its reason and owner. Written by `tools/githooks/hold "<reason>"`, removed by `unhold`. | same hook | Refuse; bypass `PECLET_PUSH_HOLD_OVERRIDE=1`, logged. | B1 | ~1 ms |
| 3 | **push** (`peclet-examples`) | `tools/check_pages.py --sync-only --freeze`: for every `index.qmd` with python chunks, `_freeze/…/execute-results/html.json` exists and its `hash` equals `md5(index.qmd)` — **verified**: `backward-facing-step` freeze hash `ad3735b4…` is exactly the file's md5. Also the existing SYNC + DATA + badge-target checks. | same hook, repo-conditional | Refuse: "N pages would re-execute in a peclet-free CI". | A3, E1, E2 | <1 s (53 md5) |
| 4 | **push** (`peclet-examples`) | Provenance: a page whose prose claims a local build must have a frozen output line `peclet.<mod> from …/build_gal_cuda` (the bootstrap chunk prints `module.__file__`); `--freeze` greps the freeze JSON for it. | same | Refuse with the page list. | E4 | ms; needs one `print` added to the bootstrap chunk |
| 5 | **push of `refs/tags/v*`** (every member) | `tools/release/check_release_state.sh --ci` exits 0, **and** either `git diff <last-successful-tag>..HEAD -- .github/workflows/release.yml packaging/ pyproject.toml` is empty **or** `gh run list -w Release -e workflow_dispatch -c <sha> --json conclusion` shows `success` at this exact sha. (voro's `cuda-wheel` job *does* run on dispatch — checked: only `publish` is tag-gated — so a rehearsal exercises the job that died.) | same hook, tag refs | Refuse: "dispatch Release at this sha first". | A2, C2 | 2–5 s; a rehearsal only when the workflow changed |
| 6 | **CI** | Every job in every `release.yml` has an explicit `timeout-minutes` (none does today — GitHub's silent default is the 360 min hard cap) set to ~1.5× its last measured duration; `check_release_state.sh` gains a duration audit of the last tag run (`gh run view --json jobs`), `!!` when any job exceeds 60 % of its timeout. | CI YAML + script | Release refused by row 5 until the audit is clean. | C1 | one `gh` call per repo |
| 7 | **turn end** ("done") | PostToolUse on `Bash(git push*)` appends `(repo, sha, t)` to `$scratchpad/pushes.jsonl`. Stop hook: for each entry, `gh run list -R <repo> -c <sha> --json status,conclusion,workflowName,url`; **failure** → `decision: "block"` with the run URL ("fix it or report it as failed"); **in progress** → block once with "state that run X is still running" (`stop_hook_active` lets the second stop through); success → drop the entry. | Claude Code hooks | The agent cannot end a turn silently on a red run it caused. | A1 | 1–2 s per turn end *only* while pushes are outstanding |
| 8 | **repo settings** | `gh api` with `-X PUT/PATCH/POST/DELETE` on `/repos/*/environments`, `branches/*/protection`, `rulesets`, `secrets`, `variables`; `gh repo edit`; `gh secret`; `gh variable`. | Claude PreToolUse, `if: Bash(gh *)` | Refuse: **human gate**, no bypass variable. | B4 | ms |
| 9 | **commit** | `git add -A\|--all\|.`; `git commit -a\|--all`; `git commit` with no pathspec after stripping `-m/-F` arguments (shlex); `--no-verify`; `-c core.hooksPath=…`; `push --force*` to `main`. | Claude PreToolUse, `if: Bash(git *)` | Refuse with the pathspec form. | B3 (+ closes the bypasses of rows 1–5) | ~50 ms |
| 10 | **sbatch** | `VAR=x sbatch …` (also inside `ssh … 'VAR=x sbatch'`) → refuse with `--export=ALL,VAR=x`. A local `*.slurm` argument is linted by `tools/hpc/sbatch_lint.sh`: `--exclusive` without `--mem` → refuse; no `--time` → refuse. | Claude PreToolUse, `if: Bash(*sbatch*)` + script | Refuse; the lint is also the first line of the remote submit wrapper. | G1, G3 | ms |
| 11 | **configure/install** | `tools/hpc/install_*.sh` and a `cmake` wrapper refuse a build tree whose `CMakeCache.txt` records another `CMAKE_PREFIX_PATH` backend, and a prefix/venv carrying another backend's `PECLET_BACKEND` stamp file. | script | Refuse. Catches *reuse* of a tree; does not catch a fresh mis-plan. | G2 (partial) | ms |
| 12 | **gate authoring** | `tools/check_gates.py`: any tolerance literal ≤ 1e-8 in a `tests/**/*mpi*` CHECK/REQUIRE, and any `d(iters)` gate, must sit within 5 lines of a `// GATE: class=… evidence=… perturbed=…` block (§Gate validity). CI runs the `mpi`-labelled parity tests at `OMP_NUM_THREADS ∈ {1, 3}`. | lint in `quality.yml` + ctest matrix | Lint fails the quality job; the matrix fails the gate that D1 would have failed. | D1–D3 | seconds; parity subset ×2 |
| 13 | **push** (`peclet-examples`, only when `_freeze/` changed) | `check_pages.py --drift`: numeric tokens in a page's frozen output that moved by > 5 % relative between the pushed and the previous freeze must be named in the page's `## Changes since last render` or in `ISSUES.md`; else refuse. | pre-push | Refuse with the token list. | F1 | <1 s |
| 14 | **session start** | Idempotently set `core.hooksPath` in every suite repo and the gallery to `suite/tools/githooks` (absolute path — the gallery is a separate repo); print any `PUSH_HOLD` files; write `.sessions/<session_id>.json` (cwd, tmux pane, task line). | Claude SessionStart hook (stdout is injected as context) | — | B5 (partial), enables 1–5 | <1 s |

**Wiring.** One script, `suite/tools/hooks/peclet_hook.py`, dispatched on `hook_event_name`, registered
in **`~/.claude/settings.json`** (user scope) — sessions start in `suite/`, in a submodule, and in
`peclet-examples`, and the documentation does not state whether project-scope hooks apply from a
submodule cwd; user scope is safe either way and the script no-ops outside the two trees. The git
hooks live in `suite/tools/githooks/` (committed, reviewed like code). The PreToolUse hook denies the
two ways round a git hook (`--no-verify`, `-c core.hooksPath=`), so the only way through is the
logged variable. Settled facts about the hook contract (checked against the Claude Code docs today):
PreToolUse stdin carries `session_id`, `cwd`, `tool_input.command`; deny is exit 0 +
`hookSpecificOutput.permissionDecision: "deny"`; `if: "Bash(git *)"` filters by command; Stop hooks
block with `decision: "block"` and receive `stop_hook_active`; default hook timeout 600 s. **Not stated
in the docs, must be tested (one minute each):** whether hooks fire for `Agent`-spawned subagents
and for `claude -p`. Rows 1–5 do not depend on the answer; rows 7–10 do, and if the answer is no, the
subagent brief carries the same rules in prose (the status quo) while the git hooks still hold.

---

## Coordination on shared state

The protocol has five rules; each has an enforcer, and the enforcer is what distinguishes it from
the sentences in `CLAUDE.md` that already say most of this.

1. **Ownership is per commit and already marked.** The `Claude-Session:` trailer the harness adds to
   every commit is the ownership mark; nothing new to write. A push range carries one owner (row 1).
   Merges by a coordinator, and a session resuming a predecessor's branch, are the two legitimate
   multi-owner pushes — both are rare, deliberate, and go through the logged override.
2. **A hold is declared, not narrated.** `PROGRESS.md` said "not pushed" in prose; row 2 puts the
   same sentence where the push happens. The holder writes it; the hook reads it; the refusal quotes
   it. Cost to the holder: one command.
3. **Worktrees stay the rule for build repos** (already directed, not relitigated). For the gallery,
   which has no build, the answer is *not* "worktrees always" — it is **push only a range you
   own**, and the hook makes that the path of least resistance: when refused, the remedy printed is
   `git worktree add ../peclet-examples-push origin/main && git -C ../peclet-examples-push
   cherry-pick <your shas> && git -C ../peclet-examples-push push origin HEAD:main`. That is exactly
   the "surgical deploy" the acting session improvised on 2026-09-14, now the documented path, with
   the shared checkout kept for editing and GPU rendering (which need the freeze tree and the
   `build_gal_cuda` modules beside it).
4. **The remote `main` is a queue, not a merge point.** Direct push, no PRs (directive). Git already
   refuses non-fast-forward; row 9 refuses `--force` on `main`. Two sessions that both own commits
   above `origin/main` in different worktrees resolve by rebasing their own range — row 1 does not
   fire, because each range still has one owner.
5. **Repository settings, environments, protection and secrets are a human gate** (row 8). The
   user's own policy already lists "hard to reverse or outward-facing" as the case that may block;
   B4 was one and the peer session was right. A refusal here is a `DECISION:` line plus a push
   notification, not a stall.

**Session addressing (B5)** is only partly solvable from inside the tools. Row 14's registry gives
each session a file naming its cwd, tmux pane and task; a brief is then addressed by reading the
registry rather than by guessing from a pane name. Whether the harness's `ListAgents` names can be
mapped onto those files is not established — it needs one experiment, and until then the registry
is a lookup aid, not an addressing mechanism.

---

## Gate validity

A validity criterion can be stated, and about two thirds of it can be checked by a script. A gate
is valid only if all of the following hold, and rows 12's `// GATE:` block records the first four:

- **Class.** The compared quantity's reproducibility class is *named and measured*, not assumed:
  `bitwise`, `ulp-bounded` (with the bound and how it was derived), `solver-tolerance-bounded`
  (bound as a function of the solver's rtol), `conservation` (a global invariant instead of a
  field), or `statistical` (n runs, the observed spread). D1 asserted `bitwise` at 1e-11 on a field
  built by a branch-selecting reconstruction — a class that does not exist for such a field, as the
  decision register now records.
- **Configuration match.** The two runs share a fingerprint asserted *in the test*: solver selection
  (peclet switches its momentum solver below ~65k cells/rank), np, thread count, precision flags. A
  mismatch fails as "configuration mismatch", never as a numeric disagreement. D3 lacked this and
  produced a 3.7e-07 that hid a real 8.4e-11.
- **Determinism of discrete quantities.** Iteration counts and branch selections are gated only
  when shown to be deterministic functions of the compared inputs. A rest state whose `r0` is the
  round-off of hydrostatic balance is not (D2).
- **Teeth.** The gate has failed once on a deliberately perturbed input, and the block records the
  run. A gate that has never failed is unvalidated.
- **Thread and rank coverage.** Run at ≥ 2 thread counts and ≥ 2 rank counts before it counts as
  passing — D1's np=4 passed at 1, 8 and 16 threads and failed at 2, 3, 4, 6 and 12; the failing
  set is not monotone, so CI's 4 CPUs seeing one value is no evidence. Row 12's `{1, 3}` matrix is
  the cheap version of this.

What remains a review matter, and is declared so: whether the *derived* bound is right (the physics
of why one ulp flips `mycNormal`'s estimator is an analysis, not a lint). The decision register is
the right home for that analysis — it already holds the VoF entry — and the `// GATE:` block's
`evidence=` field is the pointer to it.

---

## Intent continuity: verdict

**Reject as a remedy for this record; adapt one idea from it.**

1. Not one of the ~20 events is "a requirement stated earlier in the acting session's conversation
   was forgotten." In A2 the acting session *wrote* §11.2 itself; in B1 the constraint lived in
   another session's file; G1's note is in `SNELLIUS.md` §"Memory"; G3 was avoided *by* retrieval.
   Intent continuity's extractor scans conversation history for trigger phrases — the B1 and G1
   constraints were never in the conversation to be extracted.
2. It has no persistence across restarts (author-stated). This workflow already has a better
   constraint store than IC's — the decision register, the STATE files, the per-session memory
   index — and the record shows that store *working* as retrieval. What it lacks is enforcement at
   the action, and IC has none: its "verification" step is supersession and scope filtering of
   *text*, not a check of the action against the text.
3. The evidence is 8 synthetic tasks on a deterministic template agent, 22 stars, +28 % tokens per
   turn. Paid by 12 sessions on every turn, that is the cost class this brief says will be routed
   around; and there is no evidence it transfers to an LLM under task pressure.
4. Where the brief's instinct could be wrong, and the honest test of it: had the right constraint
   been injected into the prompt *at push time*, would B1 have happened? Plausibly not. But an
   action-scoped injection with a hard stop is precisely what a hook's refusal message is — and it
   costs nothing until the action. IC's hand-authored `COMPONENT_RELATIONSHIPS` graph is the
   `if:` matcher of a hook without the refusal. The instinct stands.

**Adapt:** the supersession rule with an explicit key. `DECISIONS.md` already has "Superseded —
history, do not re-derive" sections, so supersession exists; what it lacks is a machine-checkable
`(component, scope, target)` key on each entry, so that "is there an in-force decision about X" is a
grep and adding a second in-force entry on the same key without marking the first superseded is a
lint failure. That is a ~20-line script over `docs/decisions/*.md` and is worth doing.

**What would change the verdict:** a failure in which a session's own earlier constraint was lost
across a compaction. None is in this record. If one appears, the free answer is a SessionStart /
post-compaction hook re-injecting the STATE file (row 14 already does the mechanism); IC is the
second answer, not the first.

---

## Cost

Per routine action:

| Action | Added | Source |
|---|---|---|
| commit | ~50 ms | row 9 regex |
| push, code repo | ~20 ms | rows 1–2 |
| push, gallery | < 1 s | rows 1–4, 13 (53 md5s + JSON reads) |
| turn end, no outstanding push | 0 | row 7 no-ops |
| turn end, outstanding push | 1–2 s per repo pushed | one `gh run list` |
| `sbatch` | ms | row 10 |
| tag | 2–5 s, plus one Release dispatch **only** when the workflow or packaging changed | rows 5–6 |
| session start | < 1 s | row 14 |

Over the last 14 days: 914 commits across the nine repos (273 umbrella, 257 flow, 128 gallery,
71 voro, …) → under a minute of commit-hook time in total; pushes are fewer than commits, so rows
1–4 total under two minutes for the fortnight; row 7's `gh` calls are bounded by pushes → under ten
minutes across all sessions. The one real cost is row 5: the 1.0.1 cycle changed `release.yml` in
all four wheel-building members, so it would have demanded four dispatches — background, ~1 h for
the CPU members, ~5 h for voro's CUDA job — which is the run that would have shown 4 h 55 against
a 6 h cap **a day before the tag**, when the fix was a workflow edit rather than a public-ref
decision. Set against the cost of the failures: nine days of a stale site, a release that reaches
no user, two red Publish runs in a day, and a day on D1.

---

## What this does not catch

- **F2-type anomalies** (a reproducible number with an unexplained mechanism). Row 13 forces the
  *acknowledgement* of a moved number; it cannot tell a regression from a backend difference. That
  is an A/B and a person.
- **A wrong derivation behind a right-looking gate** (§Gate validity, last paragraph) — review.
- **An override used badly.** Every bypass is logged, not prevented; the log is only useful if
  someone greps it. Recommended: the SessionStart hook prints the last 24 h of overrides.
- **A fresh mis-plan** (G2's first form): row 11 catches reuse of a tree by the wrong backend, not
  a plan that allocates one tree for two backends before either exists.
- **Claims not tied to a push** — "tests pass" with no ctest log, "verified" with no command. Row 7
  binds only push → CI. `RELEASE_PREP.md` §4 already asks that a "tests pass" claim be qualified; a
  ctest-ledger variant of row 7 is possible and is deliberately not proposed here — it would fire
  on every turn and be the ceremony the brief warns about.
- **Semantic conflicts between worktrees** — two sessions changing the same function in
  compatible-looking ways; git merges text, and CI catches only what a test covers.
- **Session addressing** beyond the registry (B5).
- **Hook coverage of subagents and `claude -p`** until the two experiments in §Wiring are run. The
  git hooks (rows 1–5) hold regardless.
- **A human pushing from a clone without `core.hooksPath` set.** Rows 1–5 are per-clone
  configuration; row 14 installs them for agent sessions only.

---

## Adoption order

1. **Rows 1 + 2 — the pre-push single-owner rule and the hold file.** *If only one thing is
   adopted, this is it.* About forty lines of shell in `suite/tools/githooks/pre-push`, zero
   per-push cost, no Claude-side dependency, and it addresses the class that happened twice in one
   day and is live as this is written: `peclet-examples` has five unpushed commits on `main` above a
   HEAD (`5f55a70`) whose Publish run is red.
2. **Row 7** (post-push ledger + Stop-hook CI check) — A1, the class the brief's author owns.
3. **Row 3** (`--freeze` on the gallery pre-push) and **row 14** (the installer), which make 1–3
   automatic for every session.
4. **Row 9** (the PreToolUse deny list) — closes `--no-verify` and the blanket adds, ms each.
5. **Rows 5 + 6** (tag rehearsal rule, `timeout-minutes`, duration audit) — before the next tag.
6. **Row 12** (GATE lint + thread matrix) — before the next parity gate is written.
7. **Rows 8, 10, 11** (settings gate, sbatch lint, backend stamp) — before the next cluster campaign.
8. Optional: **row 13** (drift), **row 4** (provenance), the decision-key lint from §Intent
   continuity, the session registry's `ListAgents` mapping.

This note is itself pull media. Step 1 is what moves its first rule into the path of the action.
