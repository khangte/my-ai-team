# 룰 체인 축소 후보 목록 (검토용 — 파일 미수정)

- 근거: `docs/architect-review/1_multi-agent-audit-verification.md` B절 / `4_config-sh-designer-and-t4-verdict.md` 3항
- 대상: `~/.claude/CLAUDE.md` → `RTK.md` + `~/.claude/rules/ecc/common/*.md` 10개 = **17,623B**
- **이 문서는 후보 목록이다. 파일은 하나도 수정하지 않았다.** 적용은 별도 확인 후.
- 환산 기준: 1KB ≈ 전체 입력의 **0.24%** (문서 1과 동일한 3.2자/토큰 기준, 턴당 ~320토큰 × 15,422턴 ≈ 4.7M)
- **전제: 이건 사용자 전역 파일이라 다른 프로젝트·개인 세션에도 그대로 적용된다.** T4 스파이크에서
  `CLAUDE_CONFIG_DIR`로 파인만 격리하는 길이 막혔으므로(`3_t4-claude-config-dir-spike.md`) 우회는 없다.
  각 항목에 파인 밖 영향을 같이 적었다.

---

## 요약

| 등급 | 내용 | 크기 | 절감 |
|---|---|---|---|
| **A** | 파인에서 **동작하지 않는 것이 검증된** 규칙 — 파일 통째 삭제 | 4,913B | ~1.18% |
| **B** | 다른 규칙·스킬과 중복되는 절 — 부분 삭제 | 4,073B | ~0.98% |
| **C** | 판단 여지 있음 — 선택 적용 | 858B | ~0.21% |
| | **합계** | **9,844B (전체의 56%)** | **~2.36%** |

남는 것은 7,779B. 룰 체인을 통째로 없앴을 때가 4.6%이므로, A+B만 해도 그 절반을 회수한다.

---

## A등급 — 파인에서 동작하지 않음 (파일 통째 삭제)

### A-1. `agents.md` 전체 — 1,544B (~0.37%)

**왜 불필요한가:** 이 파일이 이름을 대는 에이전트(`planner`, `architect`, `tdd-guide`, `code-reviewer`,
`security-reviewer`, `build-error-resolver`, `e2e-runner`, `refactor-cleaner`, `doc-updater`, `rust-reviewer`)는
**파인에서 하나도 호출할 수 없다.** 파인 시스템 프롬프트의 사용 가능 에이전트 목록은
`caveman:*`, `claude`, `claude-code-guide`, `Explore`, `general-purpose`, `Plan`, `statusline-setup`뿐이다
(`--setting-sources project`가 `~/.claude/agents/`를 차단한다 — architect 파인에서 직접 확인).
게다가 파인 시스템 프롬프트에는 `Do not call the AgentTool unless the user requested it`이 박혀 있다.

"Immediate Agent Usage"(복잡한 기능 → planner, 코드 작성 후 → code-reviewer)와
"Parallel Task Execution"은 **멀티 파인 팀 구조 자체와 중복**이다. 그 배분은 lead가 `say`로 한다.
파인이 서브에이전트를 또 띄우면 팀을 이중으로 돌리는 셈이 된다.

**파인 밖 영향:** `~/.claude/agents/` 파일 60여 개는 그대로 남는다. 지워지는 것은 "이런 에이전트가 있으니
쓰라"는 안내문이지 에이전트 자체가 아니다. 개인 세션에서 이름을 대고 호출하면 전과 같이 동작한다.

### A-2. `hooks.md` 전체 — 768B (~0.18%)

**왜 불필요한가:**

- `## Hook Types`, `## Auto-Accept Permissions` — 파인의 훅과 권한은 `setup-team.sh`가 만드는
  `.team/_runtime/{역할}.settings.json`이 정한다. 파인이 훅을 읽거나 고칠 일이 없다.
- `Never use dangerously-skip-permissions flag` — **파인은 전부 그 플래그로 뜬다**
  (`setup-team.sh`의 `start_claude_in_pane`). 매 턴 자기 실행 환경과 모순되는 지시가 들어가 있다.
- `## TodoWrite Best Practices` — harness 기본 동작으로 이미 다루는 일반론이다.

**파인 밖 영향:** 개인 세션에서 훅을 새로 만들 때 참고할 안내가 사라진다. 다만 그 작업은
`update-config` 스킬이 담당하고, 그쪽이 훨씬 정확하다.

### A-3. `performance.md` 전체 — 1,579B (~0.38%)

**왜 불필요한가:**

- `## Model Selection Strategy` (467B) — 파인 모델은 `team/config.sh`의 `MEMBER_MODELS`가 기동 시 고정한다.
  **파인은 자기 모델을 바꿀 수 없다.** 게다가 내용이 낡았다 — "Sonnet 4.6 / Opus 4.5"라고 적혀 있는데
  실제 파인은 Sonnet 5 / Opus 5로 돈다. 안 쓰이는 정도가 아니라 틀린 정보를 매 턴 넣고 있다.
- `## Extended Thinking + Plan Mode` (647B) — `Option+T`, `Ctrl+O` 같은 키보드 조작 안내다.
  **파인 앞에는 사람이 없다.** `alwaysThinkingEnabled`도 사용자 전역 설정이라 파인이 못 바꾼다.
- `## Context Window Management` (305B) — 취지는 맞지만 T1(`CLAUDE_CODE_DISABLE_1M_CONTEXT`, 200K 자동압축)과
  T5(`CLAUDE.md`의 재Read 금지 + offset/limit)가 더 구체적으로 대체한다.
- `## Build Troubleshooting` (132B) — `build-error-resolver` 에이전트 안내. A-1과 함께 죽는다.

**파인 밖 영향:** 모델 선택 가이드가 사라지는데, 어차피 모델명이 낡아 지금 상태로는 잘못된 안내다.

### A-4. `patterns.md` 전체 — 1,022B (~0.25%)

**왜 불필요한가:**

- `## Skeleton Projects` (324B) — "스켈레톤 검색 후 **병렬 에이전트로** 보안/확장성/적합성 평가"다.
  병렬 에이전트가 없으므로(A-1) 실행 불가능하고, 검색 지시 자체는 `development-workflow.md` 0단계와 중복이다.
- `## Design Patterns` (679B) — Repository 패턴, API 응답 봉투 형식. **프로젝트별 설계 결정**이고
  이 팀에서는 architect가 `docs/`에 쓰는 산출물이다. 모든 프로젝트의 매 턴에 상수로 붙일 내용이 아니다.
  (실제로 이 리포는 bash·tmux 하네스라 Repository 패턴이 적용될 데가 없다.)

---

## B등급 — 중복 (절 단위 삭제)

### B-1. `development-workflow.md`의 `## Feature Implementation Workflow` — 1,918B (~0.46%)

**중복 내역:**

| 단계 | 내용 | 왜 중복/불가 |
|---|---|---|
| 1. Plan First | "planner 에이전트로 계획 수립" | 에이전트 없음(A-1). 계획은 architect가 `superpowers:writing-plans`로 세운다 |
| 2. TDD Approach | "tdd-guide 에이전트" + testing.md 참조 | 에이전트 없음. developer가 `superpowers:test-driven-development`를 실제로 로드한다 |
| 3. Code Review | "code-reviewer 에이전트" | 에이전트 없음. reviewer 파인이 그 역할이다 |
| 4. Commit & Push | 커밋 형식 | `git-workflow.md`와 그대로 중복 |
| 5. Pre-Review Checks | CI 통과·충돌 해소 | `code-review.md`의 `## When to Review`와 중복 |

**0단계 `Research & Reuse`는 판단이 갈린다.** 새 구현 전에 `gh search repos` → `gh search code` →
Context7 → Exa를 **필수**로 돌리라고 못 박혀 있는데, 매 구현마다 강제되는 다중 도구 전치작업이라
그 자체가 토큰 비용이다. 이 팀의 작업(bash 하네스, 기존 코드 수정) 대부분에서 헛돈다.
**다만 신규 프로젝트 착수에는 실제 가치가 있는 규칙이라, 여기만 남기는 선택지도 있다**(0단계만 유지 시 절감 1,113B).

**유지:** `## Before You Start` (598B) — "가정을 드러내라, 불명확하면 멈추고 물어라, 성공 기준을 먼저 정의하라".
파인 팀에서 `say`로 되묻는 경로와 정확히 맞물리는 규칙이라 남긴다.

### B-2. `code-review.md`의 중복 절 4개 — 1,570B (~0.38%)

3,387B로 열 개 중 가장 큰 파일인데 절반이 다른 파일 재서술이다.

| 절 | 크기 | 삭제 근거 |
|---|---|---|
| `## Common Issues to Catch` | 840B | Security 소항목은 `security.md`와, Code Quality 소항목은 `coding-style.md`의 `## Code Smells to Avoid`·`## Error Handling`과 중복. 같은 파일 안의 `## Review Checklist`와도 겹친다 |
| `## Integration with Other Rules` | 262B | 다른 규칙 파일 목록을 나열하는 것뿐이다. 정보가 없다 |
| `## Agent Usage` | 241B | `code-reviewer`, `security-reviewer`, `rust-reviewer` 등 — 전부 파인에서 호출 불가(A-1) |
| `## Review Workflow` | 227B | "git diff → 보안 체크 → 품질 체크 → 테스트 → 커버리지 → 에이전트" 6단계. 앞 다섯은 같은 파일의 체크리스트 절과 중복, 마지막은 죽은 에이전트 |

**유지:** `## When to Review`, `## Review Checklist`, `## Security Review Triggers`,
`## Review Severity Levels`, `## Approval Criteria`. reviewer가 CRITICAL/HIGH 판정과 승인 기준을 실제로 쓴다.

### B-3. `testing.md`의 절 3개 — 491B (~0.12%)

| 절 | 크기 | 삭제 근거 |
|---|---|---|
| `## Test-Driven Development` | 221B | developer가 `superpowers:test-driven-development` 스킬을 실제로 로드한다. 6줄 요약본을 상수로 들고 다닐 이유가 없다 |
| `## Troubleshooting Test Failures` | 172B | 1번 항목이 "tdd-guide 에이전트 사용"이다(불가). 나머지는 `superpowers:systematic-debugging`이 대체 |
| `## Agent Support` | 98B | tdd-guide 안내 |

**유지:** `## Minimum Test Coverage: 80%`(reviewer의 판정 기준), `## Test Structure (AAA Pattern)`과 테스트 네이밍
(실제 코드 컨벤션이라 상수로 있을 값어치가 있다).

### B-4. `coding-style.md`의 `## Code Quality Checklist` — 94B (~0.02%)

내용이 "See code-review.md for the complete checklist" 한 줄인데, `code-review.md`의
`## Integration with Other Rules`는 다시 `coding-style.md`를 가리킨다. **순환 참조**다. 양쪽 다 지운다 — `code-review.md` 쪽 262B는 B-2에, 여기 94B는 이 항목에 계산돼 있다(중복 계산 아님).

**`coding-style.md`의 나머지 2,627B는 전부 유지한다.** Immutability, KISS/DRY/YAGNI, 에러 처리, 입력 검증,
네이밍, `## Surgical Changes`는 developer가 매 턴 실제로 따르는 규칙이고, 특히 `## Surgical Changes`
("네가 만든 것만 치워라, 인접 코드를 개선하지 마라")는 이 팀에서 리뷰 지적이 실제로 나오는 항목이다.

---

## C등급 — 판단 여지 있음 (선택)

### C-1. `git-workflow.md`의 `## Pull Request Workflow` — 410B (~0.10%)

이 리포는 lead가 main에 직접 커밋하는 흐름이라 PR 절차를 쓰지 않는다.
**다만 사용자의 다른 프로젝트에서 PR을 쓴다면 남겨야 한다.** 확인 필요.

`## Commit Message Format`(196B)은 **반드시 유지** — lead가 매번 쓰는 형식이다.

### C-2. `RTK.md`의 `## Installation Verification` — 318B (~0.08%)

`rtk --version` 확인, "reachingforthejack/rtk와 이름 충돌" 안내. **최초 설치 시 1회용 내용**인데
매 턴 상수로 붙는다. 이미 설치돼 돌고 있다(파인마다 `rtk hook claude`가 PreToolUse로 걸려 있다).

`## Meta Commands`(329B)와 `## Hook-Based Usage`(217B)는 유지 — 훅이 실제로 도는 중이고
`rtk gain`류를 직접 부를 때 필요하다.

### C-3. `security.md`의 `## Security Response Protocol` 축약 — ~130B (~0.03%)

5단계 중 2번 "use security-reviewer agent"만 죽었다. 절을 지우지 말고 그 줄만 뺀다.

**`## Secret Management`(222B)은 손대지 않는다.** 시크릿 하드코딩 금지·노출 시 로테이션은
신뢰 경계 규칙이라 절감 대상에서 제외한다.

---

## 손대지 않을 것

| 파일/절 | 이유 |
|---|---|
| `~/.claude/CLAUDE.md` (236B) | `@RTK.md` 로드와 graphify 트리거뿐. 더 줄일 것이 없다 |
| `coding-style.md` 2,627B | developer가 매 턴 따르는 실동 규칙 |
| `security.md` `## Secret Management` | 신뢰 경계 |
| `git-workflow.md` `## Commit Message Format` | lead가 매 커밋에 사용 |
| `testing.md` 커버리지·AAA·네이밍 | reviewer 판정 기준 + 실제 코드 컨벤션 |
| `code-review.md` 심각도·승인 기준 | reviewer 실사용 |
| `development-workflow.md` `## Before You Start` | 파인의 `say` 되묻기 경로와 직결 |
| `RTK.md` Meta Commands·Hook-Based Usage | rtk 훅이 실동 중 |

---

## 적용할 때 주의

1. **A등급부터 하고 측정한다.** 파일 4개 삭제(4,913B)는 되돌리기 쉽고 근거가 가장 단단하다.
   적용 후 파인을 새로 띄워 첫 턴 컨텍스트가 47.7k에서 얼마나 내려가는지 실측하면 환산 가정도 같이 검증된다.
2. **B-1의 0단계(Research & Reuse)는 사용자 의사를 따로 묻는다.** 유일하게 "안 쓰인다"가 아니라
   "비용 대비 가치 판단"인 항목이다.
3. **삭제 전 백업.** 사용자 전역 파일이므로 `~/.claude/rules/ecc/` 전체를 git이든 사본이든 남기고 시작한다.
4. **A-1 적용 시 잔여 참조를 같이 정리한다.** `agents.md`를 지우면 `code-review.md`,
   `testing.md`, `performance.md`, `development-workflow.md`, `security.md`가 가리키던 링크가 끊긴다 —
   위 B등급 절 삭제가 그 참조들을 대부분 함께 없애지만, 남는 문장이 있으면 그때 정리한다.
