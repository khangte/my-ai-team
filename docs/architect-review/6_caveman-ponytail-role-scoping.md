# caveman·ponytail 역할별 선별 제외 판정

- 작성: architect
- 대상: `setup-team.sh`의 `PLUGIN_ROLES` — 현재 `ponytail@ponytail`·`caveman@caveman` 모두 `"*"` (전 파인)
- 선행 문서: `1_multi-agent-audit-verification.md`(상수 오버헤드 2.9% 실측), `2_token-optimization-tasks.md`(T7, 사용자 확인 대기로 보류)
- 이번 판정 범위: 전체 제외가 아니라 **역할별 선별 제외**. 코드 변경 없음, 권고만.

## 결론

| 역할 | caveman | ponytail |
|---|---|---|
| lead | 제외 | 제외 |
| architect | 제외 | 제외 (YAGNI 한 줄로 대체) |
| researcher | 제외 | 제외 |
| developer | 제외 | **유지** |
| reviewer | 제외 | 제외 (한 줄로 대체) |

**caveman은 역할을 가리지 않고 전부 제외**, **ponytail은 developer 하나만 유지**한다.

권고 반영 시 `PLUGIN_ROLES`는 이렇게 된다(실행하지 않음, 참고용):

```bash
declare -A PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
    ["serena@claude-plugins-official"]="developer reviewer"
    ["ponytail@ponytail"]="developer"
    ["caveman@caveman"]=""
)
```

`caveman`을 목록에서 아예 지우지 않고 값만 비우는 이유는, `[3/7]`의 설치 루프가 `PLUGIN_ROLES`를 돌기 때문이다.
값이 `""`면 설치는 하되 파인의 `enabledPlugins`에는 넣지 않는다 — 사용자 개인 세션(전역 `~/.claude/settings.json`으로
켜져 있음)은 그대로 유지된다.

## 근거 1 — caveman: 압축할 산문 자체가 파인에 없다

파인 트랜스크립트(`~/.claude/projects/-home-kang-ai-setup--team-*/`) 전체를 집계했다.
caveman이 실제로 압축하는 대상은 어시스턴트의 **화면 출력 텍스트**인데, 그 총량이 프로젝트 전 기간 합쳐 이 정도다.

| 역할 | 텍스트 블록 수 | 중앙값(자) | 전 기간 합계(자) |
|---|---|---|---|
| lead | 89 | 68 | 13,552 |
| architect | 17 | 67 | 1,528 |
| researcher | 10 | 22 | 496 |
| developer | 36 | 57 | 3,189 |
| reviewer | 32 | 169 | 6,614 |

합계 약 25KB ≈ **8K 토큰**. 이미 역할 지침이 "응답은 실행한 `say` 한 줄로 끝낸다"를 강제하고 있어,
caveman이 들어오기 전부터 파인의 산문은 사실상 0에 수렴한 상태다. 압축할 것이 없는 자리에 압축기를 놓은 셈이다.

`say` 트래픽도 마찬가지다. `.claude-logs/*.jsonl`의 `say` 호출을 전부 더하면 81KB ≈ **25K 토큰**(전 기간),
lead가 받은 프롬프트 총량은 16,497자 ≈ **5K 토큰**이다. 현재 주석이 근거로 든
"파인 5개가 보고를 압축하면 그게 전부 lead 입력으로 들어간다"는 구조 설명으로는 맞지만, 규모가 틀렸다 —
lead 입력 총 17.1M 토큰 중 수신 보고는 **0.03%**다. caveman 고정비 3.9K/호출은 lead 수신 보고 전 기간 총량을
**1.3 API 호출 만에** 넘어선다.

게다가 caveman 규칙 자체가 `Persisted outside chat: write normal prose — code, comments, commits, docs, ...`로
문서·커밋을 압축 대상에서 빼둔다. architect의 주 산출물은 설계 문서이므로 적용 표면이 한 번 더 깎인다.

## 근거 2 — ponytail: 코드를 안 쓰는 역할에서는 사다리 7단 중 1단만 남는다

ponytail의 사다리는 2~7단이 전부 코드 대상이다(기존 헬퍼 재사용, 표준 라이브러리, 네이티브 기능,
설치된 의존성, 한 줄 구현). architect·researcher·reviewer는 코드를 직접 쓰지 않으므로 이 여섯 단이 통째로 죽는다.

실질적으로 남는 것은 1단 YAGNI("이게 존재할 필요가 있나") 하나다. 이 한 줄은 역할 지침에 직접 넣으면
20토큰 남짓이고, 플러그인으로 받으면 2.2K/호출이다. **100배 비싼 경로로 같은 규칙 하나를 산다.**

- **researcher**: 코드도 설계도 없다. 순수 사표(死票). haiku라 단가는 싸지만 얻는 것이 0이다.
- **architect**: 설계 단계의 과설계가 가장 비싼 과설계인 것은 맞다. 다만 Opus라 파인 중 토큰 단가가 가장 높고,
  적용되는 규칙은 YAGNI 한 줄뿐이다. 지침에 문장으로 넣는 쪽이 같은 효과에 1/100 비용이다.
- **reviewer**: 판단이 가장 미묘한 자리다. 다만 developer가 ponytail을 켠 상태로 코드를 쓰므로 1차 필터가
  이미 걸려 있고, 리뷰 기준은 `rules/ecc/common/code-review.md`가 이미 상수로 붙는다. 제외하되
  지침에 "불필요한 추상화·투기적 일반화를 지적할 것" 한 줄을 넣어 보완한다.
- **developer**: 유일하게 사다리 2~7단이 전부 살아 있는 역할이다. 회피한 추상화 하나가 작성·리뷰·디버깅에서
  아끼는 토큰이 고정비 2.2K/호출을 넘길 여지가 충분하다. **유지**.

## 근거 3 — 스킬·에이전트 목록은 전 기간 사용 0회

caveman 스킬 26 + 에이전트 12, ponytail 스킬 6이 매 턴 목록으로 붙는다(약 0.85K/턴).
파인 트랜스크립트 전체에서 `cavecrew-*`·`ponytail-*`·`caveman-*` 호출을 검색한 결과 **모든 역할에서 0건**이다.
파인은 역할 지침이 지정한 `superpowers:*`만 쓴다. 이 항목은 회수 가능성이 있는 비용이 아니라 순손실이다.

## 절감 규모

파인 5개 전 기간 실측: API 호출 898회, 총 입력 61.6M 토큰(캐시 읽기 포함).

| 항목 | 토큰 | 총 입력 대비 |
|---|---|---|
| caveman 전 파인 고정비 | 3.50M | 5.7% |
| ponytail 전 파인 고정비 | 1.98M | 3.2% |
| ponytail developer만 유지 시 잔존 | 0.53M | 0.9% |
| **권고안 절감 (caveman 전면 + ponytail 4역할)** | **4.95M** | **8.0%** |

호출당 3.9K(caveman)·2.2K(ponytail)는 선행 문서 실측치를 그대로 썼다.
`1_multi-agent-audit-verification.md`의 2.9%와 수치가 다른 것은 분모 차이다 — 그쪽은 사용자 개인 세션까지 포함한
전체 15,422턴, 여기는 파인 5개 898호출로 한정했다. 파인만 놓고 보면 비중이 더 크다.

회수 측 상한은 산문 8K + `say` 25K ≈ **33K 토큰**(전 기간). 비용 대비 **150:1**로 밑진다.
developer의 ponytail을 남기며 포기하는 몫은 0.9%p이고, 이건 토큰이 아니라 코드량으로 회수하는 항목이다.

## 부수 효과 / 확인할 것

1. **비용 이외의 손실은 출력 스타일 하나다.** 파인 응답이 caveman 문체를 잃는다. 다만 파인의 화면 출력은
   중앙값 22~169자이고 사용자가 실제로 읽는 것은 lead 화면과 문서다. lead까지 제외 대상이므로,
   문체를 유지하고 싶다면 lead만 되살리는 선택지가 남는다(비용 3.9K/호출, 총 1.0M ≈ 1.6%).
2. **사용자 개인 세션은 영향 없다.** 이 변경은 파인의 `--settings` 주입에만 적용된다. 전역 설정은 건드리지 않는다.
3. **적용 후 1턴 검증 필요.** ponytail은 SessionStart 훅(`hooks/claude-codex-hooks.json`)으로 규칙을 주입한다.
   `enabledPlugins`에서 빠지면 훅도 함께 등록되지 않아야 한다. 파인 재기동 후 첫 턴 컨텍스트 크기를
   변경 전후로 비교해 실제로 빠졌는지 확인한다 — `2_token-optimization-tasks.md`의 T1/T3 검증과 같은 방식.
4. **지침 보완 2줄이 이 권고의 일부다.** 플러그인만 빼고 지침을 안 고치면 YAGNI 기준이 사라진다.
   - `team/architect.md`: 설계 시 투기적 일반화·미리 만든 추상화를 넣지 않는다(YAGNI)
   - `team/reviewer.md`: 불필요한 추상화·투기적 일반화를 지적 대상에 포함한다
