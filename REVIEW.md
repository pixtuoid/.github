# Review rules

What the shared review checks here, on top of [`AGENTS.md`](AGENTS.md) and the
contract in [`claude-review.yml`](.github/workflows/claude-review.yml), which
owns severity, format, evidence and the lenses. Each rule names the failure it
catches.

**Published contracts** here, each one every other repo runs from `main`: a
reusable workflow's or composite action's inputs, outputs and secrets; a check
name (`ci-gate`, `claude-review / claude-review`); the review's verdict line;
`.mergify.yml`'s rules; the plugin's skill names; org-rules.md and the stubs
its action checks.

## Do not flag

- Anything [`ci.yml`](.github/workflows/ci.yml) gates, each action's `test.sh`
  included; pure style.
- Behavior documented where it is constrained: read the item's comments first.
- Risks that need unreachable preconditions.

## Correctness

- **Blast radius**: a change to a published contract whose PR body links no
  consumer's update for it is blocking, since every repo's queue moves when it
  merges.
- **Fails closed**: a gate here (require-jobs, the review's verdict step,
  org-rules, workflow-lint) fails on an empty, missing, skipped or cancelled
  input, and a fork's, bot's or cancelled run still fails closed.
- **Test teeth**: a changed action or step has a `test.sh` case that fails
  when it is wrong, run on the step's own shell read from its file.
- **Security**: a secret in a command or log, event data spliced into a shell,
  a permission the diff widens, or an action outside `pixtuoid/.github/*` not
  pinned to a commit.

## Design

1. **One source**: a value a consumer must match has one copy here, and a
   copy a consumer holds is pinned by the org-rules action or a test.
2. **No repo's special case**: a branch here that serves one repo is a finding
   naming where that repo's own config holds it (its own Mergify rule, an
   inline zizmor ignore, its own step).

## Must-run

The review only reads, so the author runs each item the diff touches and
writes its result, for the head it ran at, into the PR body.

- **Plugin**: a change under `.claude-plugin/` or `plugins/` runs
  `claude plugin validate .`, which passes.
