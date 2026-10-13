# 역할별 스킬·플러그인 배분 근거

> README의 "역할별 스킬·플러그인" 절 상세. 배분 표와 제외 이유를 모아 둔다.

## 역할별 스킬 제한

공급자마다 방식이 다르다. 아래는 Claude 기준이고, Codex는 아래 "Codex 파인 스킬" 절을 본다.

- 문제: gstack setup은 스킬 수십 개를 `~/.claude/skills/`에 전부 설치하고, 그 frontmatter가 파인이 뜰 때마다
  시스템 프롬프트에 포함됨 → 구성한 모든 파인 × 매 턴이라 고정비가 큰데, 대부분은 역할과 무관한 스킬
- 해결: `~/.claude/skills`는 유저 전역이라 파인별 구성이 불가하므로, `setup-team.sh`가 파인마다
  `.team/{역할}/.claude/skills`에 **필요한 스킬만 심볼릭 링크**하고 그 디렉터리를 cwd로 실행,
  `--setting-sources project`로 유저 전역·플러그인 스킬은 차단

| 역할       | 허용 스킬                   |
| ---------- | --------------------------- |
| lead       | `spec` `plan-eng-review`    |
| architect  | `diagram`                   |
| researcher | `scrape` `browse`           |
| designer   | `design-review` `design-html` |
| developer  | `health`                    |
| reviewer   | `review`                    |

- `spec`·`plan-eng-review`는 사용자에게 직접 묻는 대화형 스킬이라, 사용자와 대화하는 유일한 파인인 lead에 둔다
  (모호한 요청 → lead `spec` → architect `writing-plans` → lead `plan-eng-review` → developer)
- 실측(commerce-data-platform, 11일) 결과 역할 지침의 `## 스킬`에 사용 조건이 없는 스킬은 한 번도 호출되지 않았다.
  그래서 배정한 스킬은 `team/{역할}.md`에 언제 쓰는지 함께 적고, 호출 0회였던 `document-generate`·`qa`·`learn`은 뺐다

gstack `investigate`는 superpowers `systematic-debugging`과 교리·4단계 구성이
문구까지 거의 같은 순수 중복이라 어느 역할에도 주지 않는다. 크기는 6.6배
(62.6KB 대 9.5KB)인데 디버깅 실체는 뒤쪽 ~250줄뿐이고, 본문의 gstack 경로 참조
92곳과 frontmatter의 훅·gbrain 쿼리는 파인에서 동작하지 않는다.
근거: `docs/architect-review/8_ecc-skill-overlap-review.md` §5

designer의 `design-consultation`도 같은 이유로 뺐다 — 아래 `frontend-design`과
"팔레트·타이포·레이아웃을 정한다"는 역할이 겹치는데, 71KB(1,258줄) 중 앞 861줄이
gstack 보일러플레이트라 실제 디자인 지침은 32%뿐이다. 웹 리서치 절차가 빠지지만
그건 researcher 파인이 이미 담당한다.

### superpowers 스킬

[superpowers](https://github.com/obra/superpowers)는 gstack과 달리 **플러그인**이라
`--setting-sources project`에 통째로 차단된다. 그래서 gstack과 같은 방식으로
역할별 필요한 것만 `.team/{역할}/.claude/skills`에 링크해 되살린다
(`team/config.claude.sh`의 `CLAUDE_SUPERPOWERS_SKILL_SETS`).

| 역할      | 배정 스킬                                        |
| --------- | ------------------------------------------------ |
| lead      | `finishing-a-development-branch`                 |
| architect | `writing-plans`                                  |
| developer | `systematic-debugging` `receiving-code-review`   |

- researcher·designer·reviewer는 배정 없음
- gstack은 래퍼의 `SKILL.md`만 링크하지만, superpowers는 `references/` 등 하위 파일을
  런타임에 읽으므로 **스킬 디렉터리를 통째로** 링크한다
- 플러그인 설치 경로에 버전 디렉터리가 끼므로(`.../superpowers/6.2.0/skills`)
  경로를 고정하지 않고 최신 버전을 골라 쓴다. 미설치면 경고만 내고 넘어간다

배정에서 뺀 것과 그 이유:

| 스킬                                                        | 제외 이유                                                           |
| ----------------------------------------------------------- | ------------------------------------------------------------------- |
| `dispatching-parallel-agents` `subagent-driven-development` | 구성한 파인이 이미 병렬 실행 단위 — 파인 대신 서브에이전트를 띄운다 |
| `requesting-code-review`                                    | 리뷰어 서브에이전트를 띄우게 되어 reviewer 파인이 논다              |
| `using-git-worktrees`                                       | 구성한 파인이 같은 워킹트리를 공유하는 구조와 충돌                  |
| `using-superpowers`                                         | "1%라도 해당되면 무조건 스킬 호출" — 전 파인 고정비만 늘어남        |
| `executing-plans` `writing-skills`                          | 각각 별도 세션 실행 전제 / 팀 업무 아님                             |
| `brainstorming`                                             | 사용자와 대화하는 스킬이라 `say`로만 소통하는 파인과 맞지 않음. 모호한 요청 정리는 lead의 gstack `spec`이 맡는다 |
| `test-driven-development`                                   | `writing-plans` 계획서에 테스트 우선 단계가 이미 들어 있음. 규칙은 `team/developer.md`의 "테스트 원칙"에 문장으로 남김 |
| `verification-before-completion`                            | 핵심 규칙이 `team/reviewer.md`의 "승인 전 검증"과 같아 스킬 없이 지켜짐(실측 호출 0회, 직접 실행 검증 138회) |

이 스킬들은 단독 실행을 전제로 쓰여 있어(사용자에게 직접 승인 요청, 서브에이전트 dispatch 등)
그대로 두면 팀 구조와 어긋난다. 그래서 각 `team/{역할}.md`의 "## 스킬" 절에서 팀 규칙으로
바꿔 읽도록 명시했다 — 예로 `writing-plans`의 서브에이전트·worktree 실행 선택지 대신 lead에게 계획을 보고한다.

역할 경계: **테스트 우선 사이클(red→구현→green)까지 developer**,
**커버리지·품질 최종 판정은 reviewer**.

### Codex 파인 스킬

Codex 파인(기본 구성에서 designer·developer)은 앞 절의 Claude용 스킬·플러그인을 읽지 못한다.
`team/config.claude.sh`의 designer·developer 항목은 그 역할을 Claude로 돌릴 때만 적용되고,
Codex 파인의 플러그인·스킬은 `team/config.codex.sh`가 따로 정한다. 형식은 `config.claude.sh`와 같다
(`CODEX_PLUGIN_ROLES`는 플러그인 → 역할, `CODEX_SKILL_SETS`·`CODEX_SUPERPOWERS_SKILL_SETS`는 역할 → 스킬).

| 역할      | Codex에서 받는 것                                                              |
| --------- | ------------------------------------------------------------------------------ |
| developer | `superpowers`의 `systematic-debugging` `receiving-code-review` (스킬 링크) |
| designer  | `product-design@openai-curated-remote` (플러그인 전체 설치)                     |

`CODEX_PLUGIN_ROLES`의 키는 `codex plugin list --available`에 나오는 실제 pluginId를 그대로 적는다
(현재 카탈로그는 `openai-curated-remote`). superpowers 스킬 링크는 공식 marketplace snapshot
(`~/.codex/.tmp/plugins`)에서 가져온다.

gstack 스킬(`CODEX_SKILL_SETS`)은 비워 둔다. `setup-team.sh`는 gstack을 claude host로만
설치하고(`./setup`), gstack의 codex 렌더링은 이름이 `gstack-<name>`이라
`find_codex_skill_source`가 찾지 못한다 — 설정해도 경고만 내고 건너뛴다.

Codex 공식 카탈로그를 기준으로 Claude 기능의 대체재를 다음처럼 사용한다.

| 기존 기능                                   | Codex 네이티브 대체재                                     | 적용 방침                                        |
| ------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------ |
| Superpowers `brainstorming`·`writing-plans` | `superpowers`의 동명 스킬                                 | architect를 Codex로 돌릴 때 `CODEX_SUPERPOWERS_SKILL_SETS`에 선언(기본 배정 없음) |
| gstack `diagram`                            | `figma@openai-curated-remote`의 `figma-generate-diagram`         | FigJam을 쓰는 프로젝트에서만 역할별 전체 설치    |
| 문서 기반 spec → plan/task                  | `notion@openai-curated-remote`의 `notion-spec-to-implementation` | Notion이 source of truth일 때만 역할별 전체 설치 |
| GitHub issue/PR 문맥                        | `github@openai-curated-remote`                                 | 로컬 저장소만 쓰면 불필요                        |
| lifecycle hook                              | Codex 네이티브 hooks                                      | 이 저장소가 `SessionStart`·`Stop`을 자동 생성    |
| Serena·gstack `health`·독립 plan review     | 정확한 공식 대체재 없음                                   | Codex 기본 저장소 도구와 architect 지침으로 수행 |

`CODEX_SUPERPOWERS_SKILL_SETS`에 선언하면 `setup-team.sh`가 superpowers에서 그 스킬만 찾아
`.team/{역할}/.agents/skills`에 링크한다. 전체 플러그인에 포함된 나머지 스킬은 그 역할에 보이지 않는다.
역할 지침(`team/{역할}.md`)의 팀 규칙이 스킬의 단독 세션 지침보다 우선한다.

각 Codex 파인은 `.team/{역할}/.codex-home`을 `CODEX_HOME`으로 사용한다. 인증, Codex 시스템
스킬, 공식 marketplace 카탈로그만 공유하고 plugin 활성화 config·설치 cache는 역할마다
분리하므로, 사용자 전역에 설치된 플러그인이나 다른 파인의 플러그인이 들어오지 않는다.
connector·MCP·hook까지 필요한 전체 플러그인은 프로젝트의 `team/config.codex.sh`에서
역할별로 선언한다.

```bash
# <프로젝트>/team/config.codex.sh
declare -A CODEX_PLUGIN_ROLES=(
    ["figma@openai-curated-remote"]="architect"
    ["notion@openai-curated-remote"]="architect"
)
declare -A CODEX_SUPERPOWERS_SKILL_SETS=(
    [architect]="brainstorming writing-plans"
)
```

전체 플러그인 설치도 해당 역할의 격리된 홈에만 적용된다. 외부 connector를 쓰는 플러그인은
서비스 인증이 별도로 필요할 수 있으며, 미인증·설치 실패는 경고하고 나머지 팀 준비를 계속한다.

### frontend-design 스킬

[frontend-design](https://github.com/anthropics/claude-plugins-official)(공식 마켓플레이스)도
플러그인이라 superpowers와 같은 방식으로 링크한다(`team/config.claude.sh`의
`CLAUDE_FRONTEND_DESIGN_SKILL_SETS`).
스킬이 1개뿐이지만 배열로 둬서 배분 규칙을 나머지와 맞췄다.

| 역할     | 배정 스킬         |
| -------- | ----------------- |
| designer | `frontend-design` |

`design-consultation`을 대체한다. 8.3KB 전량이 지침이라 호출당 **2.1K 토큰**으로
`design-consultation`(17.8K)보다 **8.5배 싸다**. 더 중요한 건 gstack에 없는
**AI 슬롭 캘리브레이션** — 지금 AI 디자인이 수렴하는 세 가지 룩(크림 배경+세리프+테라코타,
니어블랙+애시드그린, 헤어라인 브로드시트)을 명시하고, 브리프가 자유롭게 둔 축을
거기에 쓰지 말라고 못박는다.

`design-review`(브라우저 QA)·`design-html`(코드 생성)은 역할이 달라 유지한다.
단 `design-html`은 Pretext(`@chenglou/pretext`) 참조가 38곳이라 그 스택에 묶인다.

> 버전 디렉터리가 semver가 아니라 `unknown`이지만, 설치본이 하나뿐이라
> superpowers와 같은 `*/skills` glob + `tail -1`로 잡힌다.

제한 대상이 아닌 것:

- claude 빌트인 스킬
- `$PROJECT_DIR/.claude/skills`의 공용 스킬
- 위 둘은 모든 파인이 그대로 사용, 자세한 근거와 예외는 `setup-team.sh`의 `[4/7]` 섹션 주석 참조
- 전역 규칙(`~/.claude/rules/`, `~/.claude/CLAUDE.md`)도 **대상 프로젝트가 홈 아래에 있으면** 차단되지 않고 그대로 로드됨
  — `--setting-sources project`의 규칙 차단은 cwd가 홈 밖일 때만 성립(실측). 즉 `/mnt/c/...` 같은 홈 밖 프로젝트로 팀을
  띄우면 파인이 전역 규칙 없이 뜨므로, 그쪽에 의존하는 지침이 있으면 프로젝트 `CLAUDE.md`로 옮겨야 함

스킬 제한 절감량은 [token-cost.md](token-cost.md) 참조.

## 역할별 플러그인 활성화 (Claude)

Codex의 플러그인 배분은 위 "Codex 파인 스킬" 절의 `CODEX_PLUGIN_ROLES`가 맡는다.

- 문제: caveman·ponytail·serena는 유저 전역 `~/.claude/settings.json`의 `enabledPlugins`로 켜지는데,
  파인은 `--setting-sources project`로 뜨는 탓에 이 전역 설정을 못 읽음 → 방치하면 **세 플러그인이
  파인에서 전혀 걸리지 않음**(실측 확인)
- 해결: `setup-team.sh`의 `[3/7]`이 플러그인을 설치하고, 파인 실행 시 `--settings`에
  `enabledPlugins`·`extraKnownMarketplaces`를 역할별로 명시 주입(`team/config.claude.sh`의
  `CLAUDE_PLUGIN_ROLES` 배열이 배분을 결정)

실측 파인당 고정비 — `ponytail` ~2.2K tok / `caveman` ~3.9K tok / `serena` ~6K tok.
활성 파인 수만큼 매 턴 반복되는 비용이므로, 쓰지 않을 역할에는 주지 않는다.

| 플러그인        | 배분                          | 이유                                                                                                                                                        |
| --------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| caveman         | 전 파인                       | 켠 파인이 아니라 lead가 이득을 회수하는 구조(파인들의 보고가 전부 lead 입력). 출력 문체를 팀 전체에서 통일하는 값이 고정비보다 크다는 사용자 결정           |
| ponytail        | developer만                   | 사다리 7단 중 2~7단이 전부 코드 대상이라 코드를 안 쓰는 역할에는 1단 YAGNI만 남음. 그 한 줄은 역할 지침에 문장으로 넣는 편이 100배 쌈(2.2K 대 ~20토큰)      |
| serena          | 전 파인                       | 심볼 탐색을 전 역할에서 쓰도록 확대. 고정비가 가장 큼(MCP 툴 정의 30개)이라 줄일 때 첫 후보 |
| superpowers     | 없음(`enabledPlugins` 미주입) | 앞의 "superpowers 스킬" 절에 따라 `[4/7]`이 스킬 디렉터리를 역할별로 직접 링크하므로 이미 걸려 있음. 여기서 또 켜면 스킬 14개가 통째로 들어와 선별이 무의미해짐  |
| frontend-design | designer                      | `[4/7]`이 designer에 직접 링크하고 `enabledPlugins`로도 켬 — 스킬이 1개뿐이라 선별 손실이 없음                                                             |

배분 근거 실측은 [architect-review/6_caveman-ponytail-role-scoping.md](architect-review/6_caveman-ponytail-role-scoping.md) 참조.


`claude plugin enable`은 부르지 않는다 — 유저 전역 `settings.json`을 고쳐 팀 밖 세션까지 건드리는데,
파인 활성화는 `--settings`가 이미 담당하므로 불필요하다.
