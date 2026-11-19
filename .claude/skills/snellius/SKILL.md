---
name: snellius
description: Build, run and collect peclet jobs on the Snellius cluster (SURF) from TRS2 through the `sn` toolkit (tools/hpc/sn): push a source tree, build it per target (h100, a100, cpu), run a driver from a job template (gpu1, gpu-mpi, genoa-mpi, genoa-hybrid, quiet1) with arrays and restart chains, pull results, check budget. Use whenever a session wants anything on Snellius -- a build, a benchmark or production run, a smoke certification, a quiet-node timing gate, the SBU budget -- instead of writing its own sbatch scripts. Not for release site installs (tools/hpc/install_snellius.sh, docs/RELEASE.md §7) or LUMI.
---

# Snellius through `sn`: the procedure

The rules and traps live in `docs/SNELLIUS.md` (section "The `sn` toolkit" first, then the toolchain,
submitting and anomaly sections). Read the section your task touches; do not work from recollection.
`sn` runs on TRS2: `~/Codes/suite/tools/hpc/sn` (a worktree's copy works the same).

## Hard rules
- **Every billed submit needs its own signed Decision Desk card.** Free: `budget`, `push`, `pull`,
  `status`, `cancel`, and `--test-only` on any billed command. Billed: `build`, `run`, `smoke`,
  `check-gpu-aware`.
- Never write your own sbatch script, never `VAR=x sbatch` (SURF's wrapper drops it), never `srun`/
  `salloc` by hand. If a template does not fit, ask the toolkit's owner (vof) rather than working around it.
- Never touch other paths under `/projects/0/prjs1022` (other users' data). A tree in `src/` is
  read-only by design; never `chmod` it back.

## The billed step, every time
1. `sn <billed command> ... --test-only` -> read its three lines: the sbatch line, SURF's "charged for" line
   and slot, the SBU estimate against the budget line. `sn budget` for the whole picture.
2. `sn <same command> --print-action` -> the exact action text.
3. Send hub a DECISION-REQUEST with that action text and the estimate (the user's directive: decisions for
   the user go through session `hub` to the Decision Desk). Do not idle: switch to unblocked work.
4. When the card is signed: fetch it with ArtifactData into a dir D (`get decisions/<id>`, `list keys`),
   then `sn <same command> --card <id> --desk D`. `sn` verifies the card itself and submits only on
   VERIFIED; a card covers one submit.
5. Write `executed: {at, by, result}` (the job id) on the card, as `sn`'s `EXECUTED-NOTE` line says.

## Use cases
**voronoi / voronoi_fable** (one tree shared by both; gpu1 arrays from local commits):
```bash
sn push m7 voro=../voro-m7-statics core=../core-amgpar      # prints TREE m7-<hash>; reused if unchanged
sn build m7-<hash> h100 voro                                  # billed (card)
sn run m7-<hash> h100 m7/phaseB gpu1 --array cases.txt --chain 4 --time 02:00:00 -- <driver in the tree>
sn status m7;  sn pull m7/phaseB ~/Codes/.../results/phaseB --only '*.summary,*.npz,summary.tsv'
```
The driver must be in the pushed tree (path relative to the tree) or already on Snellius; it ends a chain
by creating `$SN_DONE` and resumes from its own checkpoint in `$SN_OUT`.

**pnm / A7** (gpu-mpi arrays, CERT line, restarts):
```bash
sn push a7 flow=<sha> pnm=<sha>
sn build a7-<hash> h100 flow pnm
sn run a7-<hash> h100 a7/<tag> gpu-mpi --gpus 4 --array scenes.txt --chain K -- <driver>
sn pull a7/<tag> <dir> --only 'fields.npz,meta.json,summary.tsv'
```
The driver prints `CERT <key=value ...>` as its last such line; it lands in `summary.tsv`.

**peclet-papers (A1/H1/G1)**: pinned releases stay on `tools/hpc/install_snellius.sh <tag>`
(docs/RELEASE.md §7); or `sn push <paper> umbrella=<tag>` and `sn build`. Runs: `genoa-mpi --ranks N`
(to 1536), `genoa-hybrid --nodes N`, `gpu-mpi --gpus N` (to 16 or more; N > 4 a multiple of 4), with arrays.

**peclet-health** (timing gates TRS2 load leaves inconclusive):
```bash
sn run <tree> cpu health/<gate> quiet1 --time 00:30:00 -- <timing gate script>
```
genoa node sets vary (3.2 vs 8.0 s/step measured): repeat on another allocation, report best-of or spread.

**Certification of a new build**: `sn smoke <tree> <target>` (np=1 and np=4 `k` must agree to all digits;
the CERT line says `match=yes`), and for GPU-aware MPI measurements `sn check-gpu-aware <tree> h100`.
Host-staged halos (`PECLET_CORE_GPU_AWARE_MPI=0`) stay the default (anomaly G5); `--env
PECLET_CORE_GPU_AWARE_MPI=1` measures the other path.

## When something fails
- `sn` refusals name the cause (dirty worktree, missing sibling, built dir, existing tag, budget). Fix
  the cause; do not bypass the check.
- A failed build leaves `build/<tree>-<target>/build-<jobid>.out` and `BUILD_INFO.part`: read them by
  `ssh snellius 'tail -n 40 ...'`, never whole. `core_include ... FAIL` means a package did not compile
  the tree's core: push the missing sibling.
- Toolkit check after any edit to `tools/hpc/sn` or `tools/hpc/snellius/`: `tools/hpc/snellius/selftest.sh`
  (one line, PASS n/n).
