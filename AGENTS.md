# AGENTS.md

pixtuoid/.github holds what every pixtuoid repo shares, so each one references
it instead of keeping a copy: the review (`claude-review.yml`, which each
repo's `review.yml` starts), the composite actions under `.github/actions/`,
the Mergify queue (`.mergify.yml`, which each repo's extends), the Claude Code
plugin marketplace (`.claude-plugin/`, `plugins/`), and the org's profile and
community health files.

<!-- org-rules:begin -->
## Org rules

Shared by every pixtuoid repo. The source is pixtuoid/.github's `.github/actions/org-rules/org-rules.md`, and that action fails CI when a repo's copy differs: change the rules there, then sync each repo's copy.

The owner's bar: every change is best practice, the best architecture design and the most future-proof, follows the industry's standard practice and these md rules, and refactors existing code that breaks them; no low-ROI work, no over-engineering, no legacy or backward-compatibility paths.

- **Evidence.** An external claim, "best practice" included, cites a doc URL or `path:line` fetched this session, or is labelled opinion.
- **Refactor.** Existing code a change touches that breaks a written rule is refactored in that change. Any other code may be, in a commit of its own, when that removes a named defect, never on taste alone.
- **Every mechanism earns its upkeep.** Code, config, a test, a CI job or a doc stays only if it names a failure it prevents that nothing else already does. A maintained library, the platform or the upstream tool's own mechanism is reused before one is built.
- **One source.** What every repo shares lives once and is referenced, never copied: pixtuoid/.github's actions, review, Mergify config and plugin marketplace, and pixtuoid/coderabbit's CodeRabbit config. Where a repo must hold a file to reference one, the org-rules action fails CI when it drifts.
- **TDD.** A failing test, then the minimal implementation, then the commit.
- **Comments are WHY only**, doc prose included, and sit on the narrowest thing they constrain; a PR body states its claims and their why. Name the authority instead of restating its value. Measurements go in commit messages.
- **No magic numbers.** Reuse the existing authority, else one named constant at the narrowest scope; when a copy of a value must cross a boundary, a test pins the pair. No `unwrap()` outside tests.
- **Review findings.** A finding's premise is checked against the item it names before it is accepted. A refuted finding produces a mechanism (a test, a compile-time constraint, a CI gate) or nothing.
- **Docs** change in the same commit as what they describe, and no new doc lands unless the owner asks.
- **Git.** Never force-push and never skip hooks. A change reaches `main` only through a pull request and the org's Mergify queue, queued (`@mergifyio queue`) by the session that opened it once every finding has its disposition and the repo's must-run results are in the body.
- **The [Roadmap](https://github.com/orgs/pixtuoid/projects/1) is the plan of record**, the owner's rule: every step (an item started or finished, a PR opened, merged or closed, a reorder) updates its item, the draft or the issue it tracks, in the same turn. Agents add Roadmap draft items, never issues.
<!-- org-rules:end -->

## This repo's rules

- Every other repo runs this one's `main`: its workflows and actions at
  `@main`, its queue and its plugin as `main` holds them. A change to a shared
  action's inputs, a check name, the review's `Blocking:` verdict line,
  org-rules.md or a stub its action checks moves every repo's queue, so it
  lands only with each consumer's update ready to merge after it, and its PR
  body links them.
- Each action's `test.sh` runs the action's own shell, read from its
  `action.yml`, against fixtures, and `ci.yml` runs every one: a change to an
  action starts with a case there that fails.
- A PR opens once `/pixtuoid:local-review` has run on its head.
