# Review rules

What the shared review checks here, on top of [`AGENTS.md`](AGENTS.md) and the
contract in [`claude-review.yml`](.github/workflows/claude-review.yml), which
owns severity, format, evidence and the lenses. Each rule names the failure it
catches.

**Published contracts** here, each one every other repo runs from `main`: a
reusable workflow's or composite action's inputs, outputs and secrets; a check
name (`ci-gate`, `claude-review / claude-review`); the review's verdict line;
what a shared action fails on, the bundled zizmor policy included;
`.mergify.yml`'s rules; the plugin's skill names; org-rules.md and the stubs
its action checks.

## Do not flag

- A defect zizmor, actionlint, shellcheck or a `test.sh` case that
  [`ci.yml`](.github/workflows/ci.yml) runs already reports; pure style.
- Behavior documented where it is constrained: read the item's comments first.
- Risks that need unreachable preconditions.

## Correctness

- **Fails closed**: a gate here (require-jobs, the review's verdict step,
  org-rules) fails on an empty, missing, skipped or cancelled input instead of
  passing vacuously.
- **Security**: a secret in a command or log, event data spliced into a shell,
  or a permission the diff widens.

## Design

- **No repo's special case**: a branch here that serves one repo is a finding
  naming where that repo's own config holds it (its own Mergify rule, an
  inline zizmor ignore, its own step).

## Must-run

The review only reads, so the author runs each item the diff touches and
writes its result, for the head it ran at, into the PR body.

- **Plugin**: a change under `.claude-plugin/` or `plugins/` runs
  `claude plugin validate .`, which passes.
