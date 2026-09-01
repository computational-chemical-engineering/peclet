# Session prompt — the defect-correction campaign

Paste the block below as the first message of the executing session. It is written for both
models: Opus executes, Fable designs and rules; each checks which it is and behaves accordingly.

---

You are executing the suite-wide defect-correction campaign in `/home/frankp/Codes/suite`.
Read, in this order, before doing anything else:

1. `docs/DEFECT_CORRECTION_PLAN.md` — the rule (§0), the inventory (§1), the rungs (§2), the
   ownership and handoff protocol (§3), and **§4, the status log, which tells you where the
   previous session stopped**. Then §5, the working practices — they are not optional.
2. `docs/VOF_NEXT_SESSION.md` Item 1 (the evaluation that produced this plan) and
   `flow/doc/vof_workorders_v34.md` §4-5 (WO-M: the measured float-vs-double record, the
   `PECLET_FLOW_MG_DIAGRESUM` control, and the harness `flow/tests/study/precision_ab.py`).
3. `suite/CLAUDE.md`, then `flow/CLAUDE.md` and `core/CLAUDE.md` for build/test recipes.

**The campaign opens with a Fable design session.** Per plan §3 the order is **M1 + M2 design
(Fable) first**, then P1 → (P2, A0, A1) → M1 → M2 → P3 → D1 → X. If §4 is empty, the correct
first session is Fable writing both momentum design sections. P1 nevertheless remains the
implementation go/no-go — the design being on paper first does not lower that bar.

**Which model are you?** Say so in your first line.

- **If you are Opus**: execute the rungs in the order of plan §3, starting from the first [Opus]
  rung §4 does not mark done — which is P1 unless §4 says otherwise. Do every [Opus] rung
  yourself. Do not begin M1 or M2 implementation unless §4 already holds a Fable design section
  for it ending in `**Ready for Opus:**`; if §4 has no momentum design at all, run P1/P2/A0/A1
  (none depend on it), leave M1/M2 alone, and say in your closing summary that the momentum
  design is the queued Fable work. When a
  handoff trigger in §3 fires, stop that rung, append the `### Handoff → Fable:` section to §4
  exactly as §3 specifies (numbers, commands, build flags, np, what was tried, the believed
  mechanism, the decision needed), commit it, and continue with any *other* rung that does not
  depend on the answer. If none remains, end the session with a one-paragraph summary of where
  the plan stands and which decisions are queued for Fable.
- **If you are Fable**: if §4 holds no momentum design yet, that is your session — write the M1
  and M2 design sections (plan §2 lists what each must decide), against the §1 inventory rather
  than against P1 measurements, which do not exist yet. Where a decision genuinely needs a number
  P1 would produce, do not guess: write `**Depends on P1:** …` and give the *decision rule* so
  Opus can resolve it from P1's numbers without another handoff. Otherwise, read §4 for open
  `### Handoff → Fable:` sections and unwritten design sections (P2-`rescale`, D1). Answer each
  in place (`**Fable ruling (date):**` or the
  design section ending in `**Ready for Opus:**`), from first principles and measurement, not
  literature; if a ruling needs a probe, run it yourself. Commit. Then, if any [Opus] rung is
  unblocked and cheap, you may execute it — but the design work comes first.

**Non-negotiables for both.** Work in an isolated `git worktree` per submodule you touch
(`git worktree add ../<name>-dc <branch>` from inside the submodule); `git diff --cached --stat`
before every commit; never `git add -A`; submodule commit → push → umbrella pointer last. One
rung per commit, env-gated default OFF, byte-identical gate-off, gates as *numbers* in §4. A
capped solve is invalid. Never tune a gate to pass — if a gate measures the wrong thing, say so in
§4 and fix the gate. `OMP_NUM_THREADS=8 OMP_PROC_BIND=false` on every battery; never three heavy
batteries at once. Commit at each validated milestone and push directly to main.

**The one thing to remember when in doubt**: the residual and the Krylov matvec use the exact
double operator, in flux form; everything below is a preconditioner and may be float. If a change
you are about to make would alter a *double-build* result, it is not a precision change — stop
and hand off.

Start by stating which rung you are on and what its gates are, then go.
