# 역할별 스킬 사용 실측과 재배분

- 작성일: 2026-09-30
- 대상: `team/config.claude.sh`, `team/config.codex.sh`, `team/*.md`, `setup-team.sh`
- 근거 데이터: commerce-data-platform 팀 세션 원본(`~/.claude/projects/*--team-{역할}/`, 2026-09-18~09-29)
- 관련 커밋: `46ce17c` `7d38869` `b071d7c` `dc4fa18` `faceb4f`

**결론:** 파인에 배정한 스킬 중 역할 지침(`team/{역할}.md`의 `## 스킬`)에 사용 조건이
적혀 있지 않은 스킬은 11일 동안 한 번도 호출되지 않았다. 호출이 없던 스킬은 빼고,
남긴 스킬은 지침에 언제 쓰는지 함께 적는다. 사용자와 대화하는 스킬(`spec`,
`plan-eng-review`)은 사용자와 직접 대화하는 유일한 파인인 lead로 옮긴다.
Codex 파인은 Claude용 배분을 읽지 못하므로 Codex 쪽 배분을 따로 정비한다.

## 1. 전제: 스킬·플러그인이 파인에 걸리는 방식

- `claude plugin install`, `claude plugin marketplace add`는 LLM을 호출하지 않는다.
  이미 설치된 상태에서 `setup-team.sh`를 다시 돌려도 토큰은 들지 않는다.
- 토큰 고정비는 세션이 뜬 뒤에 생긴다. 걸린 스킬의 frontmatter(설명문)와 플러그인의
  에이전트·MCP 지침이 매 턴 시스템 프롬프트에 들어간다. 스킬 본문은 호출할 때만 들어간다.
- 전역 설정을 그대로 쓰는 세션은 전역에 켜진 플러그인과 `~/.claude/skills`를 **전부** 싣는다
  (실측: 팀 밖 세션 498~543개 스킬). 걸지 않으면 안 들어가는 게 아니라, 막지 않으면 다 들어간다.
- 그래서 `setup-team.sh`는 역할 디렉터리를 cwd로 `--setting-sources project`로 띄워 전역을 차단하고,
  필요한 것만 다시 넣는다.
  - 플러그인: `--settings`의 `enabledPlugins` (`CLAUDE_PLUGIN_ROLES`)
  - 스킬: `.team/{역할}/.claude/skills` 심볼릭 링크 (`CLAUDE_*_SKILL_SETS`)
  - 번들 스킬: `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1`

## 2. 실측 방법

- 세션 원본의 `skill_listing` attachment로 **모델에 실제 노출된 스킬 목록**을 세션마다 확인했다.
- `Skill` 도구 호출을 역할별로 세고, 직전 프롬프트로 맥락을 확인했다. 슬래시 명령 실행은 0건이었다.
- `.claude-logs/{역할}.jsonl`은 `Skill` 호출 입력이 `{}`로 저장돼 스킬 이름을 알 수 없어 판정에 쓰지 않았다.

### 노출 확인

- 요청한 스킬이 누락된 세션은 없었다.
- 제한이 실패해 전역 스킬 전부(498~543개)가 노출된 세션이 8개 있었다.
  6개는 역할별 제한 도입 이전(09-20 15:40 이전)이다.
  lead의 2026-09-21 14:02 세션은 도입 이후인데도 531개가 노출됐다. 파인 기동이 아닌 경로로 뜬 것으로 보이며 원인은 미확인이다.
- architect는 09-23 이후 43개가 노출됐다. `8f18768`에서 `superpowers`가 architect에 `enabledPlugins`로
  통째로 켜졌기 때문이다(주석은 "빈 값"이라고 설명해 코드와 어긋나 있었다). `46ce17c`에서 되돌렸다.

## 3. 역할별 사용 결과

| 역할 | 사용된 스킬 | 한 번도 안 쓴 스킬 | 판정 |
|---|---|---|---|
| lead | `finishing-a-development-branch` 3, `caveman-commit` 4 | ponytail | 사용은 적절. 커밋 47회 중 `caveman-commit`은 4회뿐 |
| architect | `writing-plans` 2 | spec, diagram, document-generate, health, plan-eng-review, brainstorming | 지침에 "brainstorming·writing-plans만 쓴다"가 있어 gstack 스킬을 사실상 막고 있었다 |
| developer | `systematic-debugging` 1, `caveman-commit` 2 | health, learn, test-driven-development, receiving-code-review | 09-22 이후 developer가 Codex로 바뀌어 Claude 배분은 효과 없음 |
| reviewer | 없음 | review, qa, health, verification-before-completion | `verification-before-completion`의 규칙은 지침 문장만으로 지켜졌다(직접 실행 검증 138회) |

미사용 원인은 세 가지로 나뉜다.

1. **지침에 사용 조건이 없다.** gstack 스킬 전부가 여기에 해당한다.
2. **역할 구조와 맞지 않는다.** `brainstorming`, `spec`, `plan-eng-review`는 사용자에게 직접 묻는 스킬인데,
   architect는 `say`로 lead와만 소통한다. 설계 탐색은 사용자가 팀 밖 단독 세션에서 `brainstorming`으로 했다.
3. **대상이 없다.** `qa`는 웹 앱 브라우저 QA인데 프로젝트는 데이터 파이프라인이다.
   `learn`은 gstack learnings를 조회하는데 `~/.gstack/projects`가 비어 있다(기록 0건).

### 리뷰 경로 확인

지침상 코드 품질 수정요청은 reviewer가 developer에게 직접 보내고 lead 사본은 보내지 않는다.
reviewer의 `say` 호출을 세면 lead 승인 28, developer 수정요청 6(+ 옛 pane 주소 1),
architect 수정요청 6이었다. 09-18 새벽의 lead 사본 3건은 같은 날 지침 개정 전이다.

## 4. 결정한 재배분

### Claude 파인

| 역할 | gstack | superpowers |
|---|---|---|
| lead | `spec` `plan-eng-review` | `finishing-a-development-branch` |
| architect | `diagram` | `writing-plans` |
| researcher | `scrape` `browse` | — |
| reviewer | `review` | — |

플러그인: `serena`·`caveman`은 전 파인, `ponytail`은 developer, `frontend-design`은 designer,
`superpowers`는 설치만 한다(스킬은 링크로만 건다).

- **`spec` → lead**: 모호한 요청을 스펙으로 확정한다. 흐름은
  lead `spec` → architect `writing-plans` → lead `plan-eng-review` → developer.
  `gh`가 없으므로 GitHub issue 등록과 에이전트 spawn은 하지 않는다.
  사용자가 단독 세션에서 `brainstorming`을 계속 쓰면 `spec`은 중복이 된다.
- **`plan-eng-review` → lead**: 본문이 729줄이라 phase 단위 계획서에만 쓴다.
- **`diagram`**: architect에 남긴다. 이미지 파일로 따로 남길 때만 쓰고, md 안의 도식은 mermaid로 직접 쓴다.
- **`review`**: base 브랜치 대비 diff를 보는 스킬이라 main 위에서는 "Nothing to review"로 멈춘다.
  feature 브랜치의 착지 전 리뷰에만 쓴다.
- **제거**: `document-generate`, `health`(architect·reviewer), `qa`, `learn`, `brainstorming`,
  `test-driven-development`, `verification-before-completion`, ponytail(lead).
  `test-driven-development`와 `verification-before-completion`의 규칙은 각각
  `developer.md`의 "테스트 원칙", `reviewer.md`의 "승인 전 검증"에 문장으로 남겼다.

### 문서 작성 역할

researcher(Sonnet)를 문서 담당으로 두는 안을 검토했으나 채택하지 않았다.
developer가 쓴 문서(runbooks 25, benchmarks 25, phases 20, troubleshooting 11)는 작업한 사람만 아는 맥락이라,
다른 역할이 쓰면 코드와 로그를 다시 읽어야 하고 `say` 왕복이 늘어난다. architect가 쓴 문서는
계획서·판정·ADR뿐이라 떼어낼 비판단 문서가 없었다. 작성자가 계속 쓰는 현재 구조를 유지한다.

## 5. Codex 파인

Codex 파인(designer·developer)은 `.team/{역할}/.claude/skills`와 `enabledPlugins`를 읽지 않는다.
`config.claude.sh`의 designer·developer 항목은 그 역할을 Claude로 돌릴 때만 효과가 있고, 토큰 비용은 없다.

확인한 문제:

- **gstack**: `setup-team.sh`는 gstack을 `./setup`(claude host)으로만 설치한다. codex 렌더링은
  이름이 `gstack-<name>`이라 `find_codex_skill_source`가 찾지 못한다. `CODEX_SKILL_SETS`는 경고 후 건너뛰기만
  했으므로 비웠다.
- **카탈로그**: 현재 Codex 카탈로그의 marketplace는 `openai-curated-remote` 하나이고, 원격 플러그인이라
  source 경로가 없다. `bin/resolve-codex-plugin`이 이 이름을 허용하지 않아 `superpowers@openai-curated`
  해석이 실패하고 있었다. 이름을 허용하고, superpowers 스킬 링크는 source가 없으면 공식 marketplace
  snapshot(`~/.codex/.tmp/plugins/plugins/superpowers/skills`)에서 가져오게 했다.
  원격 플러그인은 snapshot 없이 설치되므로 snapshot 부재를 설치 중단 조건에서 뺐다.

결정한 배분:

| 역할 | 받는 것 |
|---|---|
| developer | superpowers `systematic-debugging` `receiving-code-review` (스킬 링크) |
| designer | `product-design@openai-curated` (플러그인 전체 설치, 스킬 10개) |

- reviewer의 수정요청이 Codex developer에게 7건 갔지만 리뷰 수용 지침이 적용되지 않았던 것이
  developer에 superpowers 2개를 준 이유다.
- `product-design`은 임시 `CODEX_HOME`에서 설치되는 것을 확인했다. `designer.md`에 브리프 질문은 lead로 보내고
  `share`(배포)는 쓰지 않는다는 규칙을 두었다.
- superpowers를 `CODEX_PLUGIN_ROLES`에 넣지 않는 이유: 넣으면 격리된 `CODEX_HOME`에 전체가 설치·활성화돼
  선별이 무의미해지고, 링크할 원본은 snapshot에 이미 있다.

## 6. 설정 파일 형식 통일

두 공급자 설정의 형식과 이름 규칙을 맞췄다.

| 역할 | Claude | Codex |
|---|---|---|
| 마켓플레이스 | `CLAUDE_PLUGIN_MARKETPLACES` | (공식 카탈로그만 사용) |
| 플러그인 → 역할 | `CLAUDE_PLUGIN_ROLES` | `CODEX_PLUGIN_ROLES` |
| standalone/gstack 스킬 | `CLAUDE_GSTACK_SKILL_SETS` | `CODEX_SKILL_SETS` |
| superpowers 스킬 | `CLAUDE_SUPERPOWERS_SKILL_SETS` | `CODEX_SUPERPOWERS_SKILL_SETS` |
| frontend-design 스킬 | `CLAUDE_FRONTEND_DESIGN_SKILL_SETS` | — |

옛 이름(`PLUGIN_ROLES`, `GSTACK_SKILL_SETS`, `CODEX_PLUGIN_SETS` 등)을 쓰는 프로젝트 오버라이드는
조용히 기본값으로 떨어지므로, `setup-team.sh`가 로딩 직후 옛 이름을 감지해 경고한다.

## 7. 남은 일

- `~/projects/docs-mcp`, `~/projects/log-etlm`의 `team/config.claude.sh`가 옛 이름을 쓴다(원래도
  폐기된 `MEMBER_MODELS`를 선언하는 낡은 파일이다). 새 이름으로 고치거나 지워야 오버라이드가 적용된다.
- 실제 파인 기동 검증이 남았다. setup 출력에서 `designer: 전체 플러그인 product-design@openai-curated`와
  `developer: superpowers:systematic-debugging superpowers:receiving-code-review`를 확인한다.
- lead 2026-09-21 14:02 세션이 제한 없이 뜬 경로는 원인 미확인이다.
- 새 배분이 실제로 호출되는지는 다음 실측에서 다시 확인한다. 특히 lead의 `spec`·`plan-eng-review`,
  reviewer의 `review`, architect의 `diagram`.
