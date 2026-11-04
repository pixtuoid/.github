## Org rules

Shared by every pixtuoid repo. The source is pixtuoid/.github's `.github/actions/org-rules/org-rules.md`, and that action fails CI when a repo's copy differs: change the rules there, then sync each repo's copy.

The owner's bar, in their words:

> 反正一定要确保所有的改动是best pracitce + best arch design + best future proof + 符合业界标准做法 + 符合md 规则 如果existing codebase不符合规范就去refactor 不做低ROI 不over engineer 不向legacy/下兼容

- **Evidence.** An external claim, "best practice" included, cites a doc URL or `path:line` fetched this session, or is labelled opinion.
- **Refactor.** Existing code a change touches that breaks a written rule is refactored in that change. Any other code may be, in a commit of its own, when that removes a named defect, never on taste alone.
- **Every mechanism earns its upkeep.** Code, config, a test, a CI job or a doc stays only if it names a failure it prevents that nothing else already does. A maintained library, the platform or the upstream tool's own mechanism is reused before one is built.
- **TDD.** A failing test, then the minimal implementation, then the commit.
- **Comments are WHY only**, doc prose and PR bodies included, and sit on the narrowest thing they constrain. Name the authority instead of restating its value. Measurements go in commit messages.
- **No magic numbers.** Reuse the existing authority, else one named constant at the narrowest scope; when a copy of a value must cross a boundary, a test pins the pair. No `unwrap()` outside tests.
- **Review findings.** A finding's premise is checked against the item it names before it is accepted. A refuted finding produces a mechanism (a test, a compile-time constraint, a CI gate) or nothing.
- **Docs** change in the same commit as what they describe, and no new doc lands unless the owner asks.
- **Git.** Never force-push or push to `main`, and never skip hooks.
- **The [Roadmap](https://github.com/orgs/pixtuoid/projects/1) is the plan of record**, the owner's rule ("每做一步都需要sync board"): every step (an item started or finished, a PR opened, merged or closed, a reorder) updates its item, the draft or the issue it tracks, in the same turn. Who may file an issue is each repo's own rule.
