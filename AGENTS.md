# AGENTS.md

pixtuoid/.github holds what every pixtuoid repo shares, so each one references
it instead of keeping a copy: the review (`claude-review.yml`, which each
repo's `review.yml` starts), the composite actions under `.github/actions/`,
the Mergify queue (`.mergify.yml`, which each repo's extends), the Claude Code
plugin marketplace (`.claude-plugin/`, `plugins/`), and the org's profile and
community health files. The marketplace and its plugin are `pixtuoid-dev`
because `pixtuoid@pixtuoid` is the pixtuoid product's own hooks plugin
(pixtuoid/pixtuoid's `crates/pixtuoid/src/install/host_plugin.rs`, `NAME`),
and a user registers one marketplace per name
(code.claude.com/docs/en/plugins/marketplace-reference).

<!-- org-rules:begin -->
## Org rules

Shared by every pixtuoid repo. The source is pixtuoid/.github's `.github/actions/org-rules/org-rules.md`, and that action fails CI when a repo's copy differs: change the rules there, then sync each repo's copy.

The owner's bar: every change is best practice, the best architecture design and the most future-proof, follows the industry's standard practice and these md rules, and refactors existing code that breaks them; no low-ROI work, no over-engineering, no legacy or backward-compatibility paths.

- **Evidence.** An external claim, "best practice" included, cites a doc URL or `path:line` fetched this session, or is labelled opinion.
- **Refactor.** Existing code a change touches that breaks a written rule is refactored in that change. Any other code may be, in a commit of its own, when that removes a named defect, never on taste alone.
- **Every mechanism earns its upkeep.** Code, config, a test, a CI job or a doc stays only if it names a failure it prevents that nothing else already does. A maintained library, the platform or the upstream tool's own mechanism is reused before one is built.
- **One source.** What every repo shares lives once, in pixtuoid/.github or, for CodeRabbit, pixtuoid/coderabbit, and is referenced, never copied, but for these rules in each agent guide and the files a repo holds to reference the rest, whose drift the org-rules action fails CI on. The org's agent skills are pixtuoid/.github's `pixtuoid-dev` Claude Code plugin, which project settings enable but each clone installs once (code.claude.com/docs/en/plugins/loading, "Enabled in project settings but not installed"): `claude plugin install pixtuoid-dev --marketplace pixtuoid/.github --scope project`, which also declares the marketplace in the user's settings (code.claude.com/docs/en/discover-plugins, "Add and install from your shell", Claude Code v2.1.292 or later).
- **TDD.** A failing test, then the minimal implementation, then the commit.
- **Comments are WHY only**, doc prose included, and sit on the narrowest thing they constrain; a PR body says what the change does and why (the problem, why this approach, its shortcomings) as claims each checked against the diff, never how it got there, and is re-read against the head before it queues. Name the authority instead of restating its value. Measurements go in the PR body, which the queue squashes into main's commit message.
- **No magic numbers.** Reuse the existing authority, else one named constant at the narrowest scope; when a copy of a value must cross a boundary, a test pins the pair. No `unwrap()` outside tests.
- **Review findings.** A finding's premise is checked against the item it names before it is accepted. A refuted finding produces a mechanism (a test, a compile-time constraint, a CI gate) or nothing.
- **Docs** change in the same commit as what they describe, and no new doc lands unless the owner asks.
- **Git.** Never force-push and never skip hooks. A change reaches `main` only through a pull request and the org's Mergify queue, a release PR aside, which merges by hand. The session that opened a PR queues it (`@mergifyio queue`) once every finding has its disposition and the repo's must-run results are in the body; whoever queues a bot's PR reads it first.
- **The [Roadmap](https://github.com/orgs/pixtuoid/projects/1) is the plan of record**, the owner's rule: every step (an item started or finished, a PR opened, merged or closed, a reorder) updates its item, the draft or the issue it tracks, in the same turn. Agents add Roadmap draft items, never issues.
<!-- org-rules:end -->

## This repo's rules

- Every other repo runs this one's `main`: its workflows and actions at
  `@main`, its queue and its plugin as `main` holds them, so a change to a
  published contract ([REVIEW.md](REVIEW.md) lists them) lands only with
  each consumer's update ready to merge after it, and its PR body links
  them.
- Each action's `test.sh` runs the action's own shell, read from its
  `action.yml`, against fixtures, and `ci.yml` runs every one: a change to an
  action starts with a case there that fails.
- A PR opens once `/pixtuoid-dev:local-review` has run on its head.
