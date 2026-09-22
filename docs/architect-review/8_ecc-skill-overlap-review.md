# everything-claude-code 스킬 중복·추가 검토

- 작성일: 2026-08-20

`setup-team.sh`가 파인에 실어주는 스킬·플러그인과 이미 설치되어 있는
everything-claude-code(이하 ecc)의 스킬 카탈로그를 대조한 결과다.

**결론 (2026-08-20 확정): ecc는 추가하지 않는다.** 플러그인 등록도, 개별 스킬
편입(`context-budget`·`search-first`)도 하지 않는 것으로 사용자가 결정했다.
§4의 편입 권고는 기각된 제안으로 기록만 남긴다.

대신 검토 중 발견한 **developer 디버깅 스킬 3중 중복**을 §5에서 정리한다.
결론: `systematic-debugging`만 남기고 `investigate`를 뺀다.

수정은 적용하지 않았다.

---

## 1. 현재 setup-team.sh가 로드하는 것

### 플러그인 (`[3/7]` `PLUGIN_ROLES`)

| 플러그인                              | 대상 역할                         | 파인당 고정비 |
| ------------------------------------- | --------------------------------- | ------------- |
| `superpowers@claude-plugins-official` | (설치만, `enabledPlugins` 미등록) | 0             |
| `serena@claude-plugins-official`      | developer, reviewer               | ~6K tok       |
| `ponytail@ponytail`                   | developer                         | ~2.2K tok     |
| `caveman@caveman`                     | 전 파인 (`*`)                     | ~3.9K tok     |

### 스킬 (`[4/7]` 심볼릭 링크 — 총 17종)

| 역할       | gstack                                                          | superpowers                                                              |
| ---------- | --------------------------------------------------------------- | ------------------------------------------------------------------------ |
| lead       | (없음)                                                          | `finishing-a-development-branch`                                         |
| architect  | `spec` `diagram` `document-generate` `health` `plan-eng-review` | `brainstorming` `writing-plans`                                          |
| researcher | `scrape` `browse` `investigate`                                 | (없음)                                                                   |
| designer   | `design-consultation` `design-review` `design-html` `diagram`   | `brainstorming`                                                          |
| developer  | `investigate` `health` `codex` `learn`                          | `test-driven-development` `systematic-debugging` `receiving-code-review` |
| reviewer   | `review` `qa` `health` `investigate`                            | `verification-before-completion`                                         |

`config.sh` 기준 현재 활성 역할은 designer를 제외한 5개다.

### ecc의 현재 상태

ecc는 `~/.claude/plugins/cache/everything-claude-code/ecc/2.2.0`에 **이미 설치되어
있지만** `PLUGIN_ROLES`에 없다. 즉 파인들은 ecc 스킬을 전혀 받지 않는다.
지금 이 세션(사용자 세션)에서만 보이는 이유는 유저 전역 `settings.json`의
`enabledPlugins`를 통해서다. 파인은 `--setting-sources project`로 뜨므로 차단된다.

규모: **스킬 286개, 에이전트 68개, 커맨드 94개.**

---

## 2. 중복 항목

이름이 정확히 겹치는 스킬은 **하나도 없다.** 기능이 겹치는 것만 있다.

| 현재 스킬                                                | 겹치는 ecc 스킬                                                   | 판정                                                                                                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `verification-before-completion` (superpowers, reviewer) | `verification-loop`, `agent-self-evaluation`, `delivery-gate`     | **중복.** ecc `verification-loop`은 npm/pnpm 빌드 명령을 하드코딩한 언어 종속 체크리스트라 오히려 범용성이 낮다. 교체 이득 없음                     |
| `investigate` (gstack, 3개 역할)                         | `agent-introspection-debugging`                                   | **중복.** 후자는 대상이 "AI 에이전트 실패"로 좁다. 일반 디버깅은 `systematic-debugging`이 이미 담당                                                 |
| `systematic-debugging` (superpowers, developer)          | `investigate-first`(caveman), `agent-introspection-debugging`     | **삼중 중복.** developer가 이미 `investigate` + `systematic-debugging` 둘 다 받는데 caveman 플러그인이 `investigate-first`까지 얹는다. 아래 §4 참조 |
| `review` `qa` (gstack, reviewer)                         | `security-review`, `code-review` 계열, 언어별 `*-reviewer` 68종   | **부분 중복.** 언어별 리뷰어는 이 리포가 특정 스택에 묶여 있지 않아 대부분 죽은 무게                                                                |
| `brainstorming` (superpowers)                            | `dev-team`, `team-builder`                                        | **개념 중복.** 후자는 페르소나 시뮬레이션이라 실제 파인 6개를 띄우는 이 리포 구조와 정면으로 겹치고 열등하다                                        |
| `document-generate` (gstack, architect)                  | `living-docs-governance`, `code-tour`, `codebase-onboarding`      | **부분 중복.** 생성은 겹치나 거버넌스·온보딩 축은 새로움                                                                                            |
| `health` (gstack, 3개 역할)                              | `plankton-code-quality`, `codehealth-mcp`                         | **중복.** 둘 다 외부 서비스(Plankton, CodeScene MCP) 의존이라 추가 설치 없이는 동작하지 않음                                                        |
| `learn` (gstack, developer)                              | `continuous-learning-v2`, `instinct-*` 계열                       | **중복.** ecc 쪽은 훅 기반 상시 관찰 구조라 파인 5개에 붙이면 고정비가 곱으로 붙는다                                                                |
| `scrape` `browse` (gstack, researcher)                   | `data-scraper-agent`, `exa-search`, `deep-research`, `browser-qa` | **부분 중복.** `exa-search`/`deep-research`는 각각 Exa·firecrawl MCP를 요구                                                                         |
| `codex` (gstack, developer)                              | `agent-eval`, `council-multi-model`, `multi-*` 커맨드             | **부분 중복.** 멀티모델 축은 같으나 `codex`가 더 좁고 싸다                                                                                          |

**정리: 순수 신규 가치가 있는 겹치지 않는 영역은 "컨텍스트 예산 감사"와
"기존 코드 탐색 전 검색" 둘뿐이다.**

---

## 3. 왜 ecc 플러그인 전체 활성화는 안 되는가

`PLUGIN_ROLES`에 `["ecc@everything-claude-code"]="*"` 를 넣는 순간:

```
스킬 286개 description frontmatter ≈ 82.9KB ≈ 20.7K 토큰
```

이것이 **파인당·매 턴** 시스템 프롬프트로 들어간다. 에이전트 68개와 커맨드
94개 정의는 별도다.

비교 기준 — 이 리포가 지금까지 깎아낸 총량:

| 항목                                      | 절감량            |
| ----------------------------------------- | ----------------- |
| gstack 스킬 56개 → 역할별 3~5개 (`[4/7]`) | ~5.7K tok/파인    |
| serena 역할 스코핑                        | ~6K tok × 3파인   |
| ponytail을 developer로 스코핑             | ~2.2K tok × 4파인 |

**ecc 전체 활성화 한 번이 지금까지의 최적화 작업(T1–T6, 문서 5·6·7번)을 전부
합친 것보다 큰 고정비를 되돌려 놓는다.** 파인 5개 기준 매 턴 약 103K 토큰이다.
`--setting-sources project` 차단 장치를 세워둔 리포에서 그 벽을 스스로 허무는 셈.

---

## 4. 추가 검토 결과 — 편입 권고 (기각됨)

> **최종 판정: 아래 권고 A·B 모두 채택하지 않는다.** 사용자 결정으로 ecc는
> 어떤 형태로도 추가하지 않는다. 검토 근거 기록용으로만 남긴다.

플러그인 활성화가 아니라 **`[4/7]`의 심볼릭 링크 방식**으로 개별 스킬만 넣으면
고정비는 해당 스킬의 description 1줄(~50 tok)뿐이다. 그 기준으로 286개를 훑어
살아남았던 것은 2개다.

### 권고 A — `context-budget` → architect

```
description: Audits Claude Code context window consumption across agents, skills,
MCP servers, and rules. Identifies bloat, redundant components, and produces
prioritized token-savings recommendations.
```

- 5,840 bytes, 외부 의존 없음, SKILL.md 단일 파일
- **이 리포의 핵심 관심사와 정확히 일치한다.** `docs/token-cost.md`와
  `docs/architect-review/2_token-optimization-tasks.md`에서 수작업으로 하던
  고정비 감사를 절차화한 것
- architect가 적임 — 이 리포에서 토큰 구조 판단은 architect 몫이고,
  `5_rule-chain-reduction-candidates.md`·`7_*-spec.md` 같은 문서를 낸 주체다
- 비용: description ~50 tok, architect 1파인만

### 권고 B — `search-first` → developer

```
description: Research-before-coding workflow. Search for existing tools, libraries,
and patterns before writing custom code.
```

- 8,021 bytes, 외부 의존 없음
- ponytail 사다리 2단("이미 이 코드베이스에 있는가")·5단("설치된 의존성이
  해결하는가)을 **절차로 강제한다.** ponytail은 반사 규칙이고 이쪽은 실행 워크플로라
  중복이 아니라 보완 관계
- developer가 유일한 ponytail 보유 역할이므로 대상도 developer
- 비용: description ~50 tok, developer 1파인만
- 단, SKILL.md가 "researcher 에이전트를 호출한다"고 되어 있는데 그 에이전트는
  ecc 플러그인 소속이라 파인에서는 안 걸린다. 워크플로 텍스트만 쓰이고
  에이전트 호출 부분은 무시되므로 **동작은 하되 반쪽이다.** 편입한다면 이 점을
  역할 지침에 명시해야 한다

### 보류 — `codebase-onboarding`

남의 프로젝트에 팀을 띄우는 이 리포 구조상 매력적이지만(`[4/7]` 주석이 상정하는
시나리오), 8,235 bytes에 산출물이 CLAUDE.md 생성이라 `setup-team.sh`가 이미
마커 블록으로 하는 일과 충돌 소지가 있다. 실사용 요구가 생기면 그때 재검토.

### 기각 목록 (대표)

| 스킬                                                                                     | 기각 사유                                                                                         |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `team-agent-orchestration`, `dev-team`, `team-builder`                                   | 이 리포가 tmux 파인으로 실제 구현한 것의 열등한 프롬프트 시뮬레이션                               |
| `cost-tracking`, `ecc-tools-cost-audit`                                                  | ecc `stop:cost-tracker` 훅이 쓰는 `~/.claude/metrics/costs.jsonl` 전제. 이 리포는 rtk 집계를 쓴다 |
| `token-budget-advisor`                                                                   | 사용자에게 응답 길이를 되묻는 대화형. caveman이 이미 무조건 압축하므로 상충                       |
| 언어별 `*-testing`, `*-verification`, `*-patterns` (~120개)                              | 이 리포는 bash + 문서 리포라 전부 죽은 무게                                                       |
| `healthcare-*`, `prediction-market-*`, `evm-*`, `llm-trading-*`, `visa-doc-translate` 등 | 도메인 무관                                                                                       |
| `exa-search`, `deep-research`, `codehealth-mcp`, `nutrient-*`                            | 미설치 외부 MCP·API 키 요구                                                                       |
| `plan-canvas`, `frontend-design-direction`, `liquid-glass-design`                        | designer 비활성 상태이고, 활성화해도 gstack `design-*` 3종과 중복                                 |

---

## 5. developer 디버깅 스킬 정리 — 본 검토의 실제 조치 항목

ecc와 무관하게 지금 구조에 이미 있는 문제다. developer 파인 하나가 같은
"고치기 전에 근본 원인부터" 교리를 **세 경로로 중복 수령**한다.

| 출처             | 항목                                                                                                 | 경유                       |
| ---------------- | ---------------------------------------------------------------------------------------------------- | -------------------------- |
| superpowers      | `systematic-debugging`                                                                               | `[4/7]` 심볼릭 링크        |
| gstack           | `investigate`                                                                                        | `[4/7]` 심볼릭 링크        |
| caveman 플러그인 | `investigate-first`, `verify-and-stop`, `safe-refactor`, `surgical-patch`, `lean-build`, `migration` | `[3/7]` `PLUGIN_ROLES="*"` |

### 실측 — 세 스킬 본문 비교

| 스킬                              | 크기          | 구조                                                                                   |
| --------------------------------- | ------------- | -------------------------------------------------------------------------------------- |
| gstack `investigate`              | **62,601 B** (1,104줄) | 실제 디버깅 내용은 852줄 이후 ~250줄뿐. 앞 851줄은 gstack 공용 보일러플레이트 |
| superpowers `systematic-debugging` | **9,465 B** (단일 파일 + 참조 4종) | 전량이 디버깅 내용                                                     |
| caveman `investigate-first`       | **688 B**     | 5줄 요약 규칙                                                                          |

### 세 스킬은 같은 교리다

- gstack: `## Iron Law` → "**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**"
  4단계 = investigate / analyze / hypothesize / implement
- superpowers: `## The Iron Law` → "`NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST`"
  4단계 = Root Cause / Pattern Analysis / Hypothesis / Implementation

문구까지 사실상 동일하다. **가치 차이가 아니라 순수 중복이다.**

### 권고: `systematic-debugging`만 남기고 `investigate`를 뺀다

**근거 1 — 크기가 6.6배인데 알맹이는 더 적다.**
`investigate` 62.6KB 중 디버깅 실체는 뒤쪽 ~250줄이고, 앞 851줄은
`Preamble (run first)` · `Skill routing` · `Artifacts Sync` · `Telemetry` ·
`Voice` · `Question Tuning` 등 gstack 런타임 보일러플레이트다. 스킬은 호출 시
본문 전체가 컨텍스트에 들어오므로, 한 번 부를 때마다 ~15K 토큰을 태우고
그중 실제 디버깅 지침은 1/4 이하다. `systematic-debugging`은 9.5KB 전량이
디버깅 내용이다.

**근거 2 — gstack 런타임 의존이 파인에서 깨진다.**
`investigate` 본문에 `~/.claude/skills/gstack/` 경로 참조가 **92곳** 있다.
Preamble이 `gstack-update-check` · `gstack-config` 바이너리를 실행하고,
frontmatter의 `hooks.PreToolUse`가 `freeze/bin/check-freeze.sh`를 물리며,
`gbrain.context_queries`가 `~/.gstack/projects/{repo_slug}/learnings.jsonl`을
읽는다. `[4/7]`은 SKILL.md 하나만 심볼릭 링크하고, 파인은
`--setting-sources project`로 뜨므로 **frontmatter의 훅도 gbrain 쿼리도 걸리지
않는다.** 즉 파인에서는 이 절반이 죽은 텍스트다.

**근거 3 — `systematic-debugging`은 팀의 다른 스킬과 이미 물려 있다.**
본문이 `superpowers:test-driven-development`(Phase 4.1)와
`superpowers:verification-before-completion`(Phase 4.3)을 명시적으로 호출한다.
developer는 전자를, reviewer는 후자를 이미 갖고 있어 체인이 실제로 성립한다.
`investigate`의 `## Skill routing`은 gstack 스킬(`/ship`, `/review` 등)로
연결되는데 developer에는 그 대부분이 없다.

**근거 4 — 3회 실패 시 아키텍처 질문 규약이 있다.**
`systematic-debugging` Phase 4.5는 "고치기 3번 실패 = 아키텍처 문제, 4번째
시도 전에 사람과 논의"를 강제한다. 파인이 혼자 무한 루프를 도는 것이 가장
비싼 실패인 이 구조에서 값이 크고, `investigate`에는 대응물이 없다.

### `investigate-first`(caveman)는 어떻게 되나

**따로 손대지 않는다.** 688B짜리 5줄이라 비용이 무시 가능하고,
`systematic-debugging`의 요약본처럼 동작해 상충하지 않는다. 다만 이것은
caveman `"*"` 배포에 딸려 오는 것이라 developer가 선택한 결과가 아니다.

### 부수 효과 — reviewer·researcher

`investigate`는 developer 외에 **researcher·reviewer도** 받고 있다
(`GSTACK_SKILL_SETS`). 이 둘은 `systematic-debugging`이 없으므로 함께 빼면
디버깅 지침이 0이 된다.

- **reviewer**: `verification-before-completion` + `review` + `qa`가 있어
  자기 역할(검증)은 충족된다. 근본 원인 추적은 developer 몫이므로 빼도 무방
- **researcher**: 웹 조사가 주 업무라 원래 죽은 무게에 가깝다. 빼는 쪽이 맞다

즉 `investigate`는 세 역할 모두에서 제거 가능하며, 그 경우 gstack
`investigate` 심볼릭 링크 자체가 사라진다.

### 최종 배치안

| 역할       | 현재                                                | 권고                                            |
| ---------- | --------------------------------------------------- | ----------------------------------------------- |
| developer  | `investigate` + `systematic-debugging` (+caveman 6종) | **`systematic-debugging`만** — `investigate` 제거 |
| reviewer   | `investigate` + `verification-before-completion`    | `investigate` 제거                              |
| researcher | `investigate`                                       | `investigate` 제거                              |

적용 지점은 `setup-team.sh`의 `GSTACK_SKILL_SETS`에서 `investigate` 3개를
지우는 것뿐이다. `SUPERPOWERS_SKILL_SETS`는 그대로 둔다.

> 참고: `6_caveman-ponytail-role-scoping.md`의 caveman 전 파인 배포 결정 근거는
> "출력 문체 통일"이었는데, 실제로 실려 오는 ~2.8K tok frontmatter에는
> `investigate-first`·`safe-refactor`·`migration` 등 문체와 무관한 워크플로
> 스킬 description이 함께 들어 있다. 그 자체는 별건이며 이번 조치 대상이 아니다.

---

## 6. 요약

| 항목                             | 판단                                                                       |
| -------------------------------- | -------------------------------------------------------------------------- |
| ecc 플러그인 `PLUGIN_ROLES` 등록 | **추가 안 함 (확정).** 파인당 매 턴 ~20.7K tok, 5파인 ~103K tok            |
| ecc 개별 스킬 편입               | **추가 안 함 (확정).** §4 권고 A·B 모두 기각                               |
| 이름 충돌                        | 없음                                                                       |
| 기능 중복                        | 10개 영역에서 중복, 대부분 현재 스킬이 우세하거나 대등                     |
| **조치 항목**                    | **`GSTACK_SKILL_SETS`에서 `investigate` 제거** (developer·reviewer·researcher) |
| 유지                             | `systematic-debugging`(developer), `investigate-first`(caveman 부수)        |
