# CLAUDE.md

이 프로젝트에서 tmux 멀티에이전트 팀으로 작업할 때, 파인별 역할 지침은
`team/{역할}.md`가 `setup-team.sh`에 의해 `--append-system-prompt`로 주입된다.
(역할별 지침 원본: `team/lead.md`, `team/architect.md` 등)

아래 내용은 역할과 무관하게 모든 파인에 공통으로 적용된다.

## Skill routing

Below skills are provided by [gstack](https://github.com/garrytan/gstack), installed at
`~/.claude/skills/gstack` by `setup-team.sh` (runtime, since it lives in the `claude-home` volume).

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:

- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
