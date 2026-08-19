# 토큰 최적화 실행 작업 목록

- 근거 문서: `docs/architect-review/1_multi-agent-audit-verification.md`
- 대상: developer
- 원칙: **사용자 전역 설정(`~/.claude/settings.json`, `~/.claude/rules/`)은 건드리지 않는다.** 파인은
  `setup-team.sh`가 만드는 `--settings` 파일(`.team/_runtime/{역할}.settings.json`)로 뜨므로, 파인에만
  적용할 설정은 전부 그 생성부에서 처리한다. 사용자 개인 세션에는 영향이 없다.
- 우선순위는 근거 문서의 P1~P4를 따른다. **T7은 착수 금지 — 사용자 확인 필요 항목이다.**

---

## T1 (P1) — 파인 컨텍스트를 200K에서 자동 압축

절감 여지 최대 32.6%. 200k 초과 턴이 전체 입력의 32.6%를 차지하는데, 실측 최장 세션은 413k까지 자랐다.
`CLAUDE_CODE_DISABLE_1M_CONTEXT=1`은 1M 컨텍스트 모델을 200K에서 자동 compaction으로 누른다.
프롬프트 규칙이 아니라 harness 동작이므로 파인이 지키고 말고 할 여지가 없다.

**파일:** `setup-team.sh` — `start_claude_in_pane()` 안, `inbound_json` 선언(약 205줄) 바로 아래

**변경:**

1. 다음 한 줄을 추가한다. 끝의 콤마를 빠뜨리지 말 것 — 이 문자열들은 JSON으로 이어 붙여진다.

```bash
    # 파인은 1M 컨텍스트 모델로 뜨는데, 200k를 넘긴 턴이 전체 입력의 32.6%를 차지했다.
    # 이 변수를 걸면 harness가 200K에서 자동 compaction으로 눌러 준다(/clear와 달리
    # 세션이 유지되므로 프리픽스 캐시를 다시 사지 않는다).
    local env_json="\"env\":{\"CLAUDE_CODE_DISABLE_1M_CONTEXT\":\"1\"},"
```

2. `lead_settings_json`과 `settings_json` 두 문자열의 `{${plugins_json}` 바로 뒤에 `${env_json}`을 끼워 넣는다.

```
{${plugins_json}${env_json}${inbound_json},"hooks":{...
```

**검증:**

```bash
./setup-team.sh <프로젝트경로>   # 또는 기존 방식대로 파인 기동
python3 -m json.tool < .team/_runtime/developer.settings.json   # JSON 유효성
grep -o 'CLAUDE_CODE_DISABLE_1M_CONTEXT[^,]*' .team/_runtime/lead.settings.json
```

파인 기동 시 "auto-compaction isn't holding the session to 200K" 경고가 뜨지 않으면 정상이다.

---

## T2 (P1 보조) — `/clear` 주기 강제 금지, `/compact`는 자연 경계에서만

T1이 자동으로 눌러 주므로 규칙은 "하지 말 것" 한 줄이면 된다. `/clear`는 세션을 새로 시작해
시스템 프롬프트·룰 체인·스킬 목록을 통째로 `cache_create`로 되돌린다 — 실측 세션당 중앙값 27,547 토큰,
cache_read 대비 12.5배 단가다.

**파일:** `team/lead.md` — `## 하지 말 것` 절

**변경:** 다음 항목 두 개를 추가한다.

```markdown
- 파인에 `/clear`를 주기적으로 지시 — 세션이 새로 시작되면서 시스템 프롬프트·룰·스킬 목록이 전부 캐시에서
  빠져 매번 27.5k 토큰을 새로 산다. 컨텍스트는 200K에서 자동 압축되므로 개입할 필요가 없다
- 컨텍스트를 줄여야 할 때 `/compact`를 작업 도중에 지시 — 쓴다면 기능 구현 완료·리뷰 반영 완료·커밋 직후처럼
  작업 단위가 끝나는 지점에서만 쓴다
```

**주의:** `say {역할} "/compact"`로 슬래시 명령을 밀어 넣는 방식은 검증 전에는 문서에 적지 말 것.
`say`는 텍스트를 입력창에 리터럴로 치고 Enter를 보내는데, `/`를 치면 자동완성 팝업이 열려 Enter가
엉뚱한 명령을 고를 수 있다. 필요하면 파인 하나로 먼저 시험하고, 다른 명령이 선택되면 이 방식은 폐기한다.

---

## T3 (P2-a) — 번들 스킬·내장 슬래시 명령 목록 제거

약 1.6% (턴당 ~2.1K 토큰 × 15,422턴 ≈ 32M). 번들 스킬 15개 내외의 설명문이 매 턴 상수로 붙는다.

**선행 확인 (이미 완료):** 역할 지침이 쓰는 스킬은 전부 플러그인·gstack 쪽이라 영향이 없다.
`superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`,
`superpowers:systematic-debugging`, `superpowers:receiving-code-review`,
`superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch` — 모두 플러그인 스킬.
`team/*.md` 전체를 grep해도 내장 `/code-review`·`/security-review`·`/init`를 쓰는 역할은 없다.

**파일:** `setup-team.sh` — T1에서 만든 `env_json`

**변경:**

```bash
    local env_json="\"env\":{\"CLAUDE_CODE_DISABLE_1M_CONTEXT\":\"1\",\"CLAUDE_CODE_DISABLE_BUNDLED_SKILLS\":\"1\"},"
```

**검증:** 파인에서 스킬 목록을 확인해 `dataviz`·`claude-api`·`artifact-*`·`update-config` 등이 사라지고
`superpowers:*`·gstack 스킬은 남아 있는지 본다. `superpowers:brainstorming`이 사라졌으면 즉시 되돌리고
T3을 폐기한다 — architect 역할 지침이 그 스킬을 전제로 쓰여 있다.

---

## T4 (P2-b) — 룰 체인 격리 가능성 확인 (스파이크)

룰 체인은 턴당 ~6.0K 토큰 × 15,422턴 ≈ 92M (4.6%)로 상수 오버헤드 중 가장 크다.
그런데 `~/.claude/CLAUDE.md` → `RTK.md` + `rules/ecc/common/*.md` 10개는 **사용자 전역 파일**이라
임의로 줄일 수 없다. `setup-team.sh` 주석대로 `--setting-sources project`로도 꺼지지 않고,
파인 cwd가 홈 아래이면 그대로 로드된다.

**작업:** `CLAUDE_CONFIG_DIR`로 파인만 별도 설정 디렉터리를 쓰게 만들 수 있는지 파인 1개로 검증한다.
가능하면 파인용 슬림 룰만 그 디렉터리에 두고, 사용자 개인 세션은 지금 그대로 둔다.

**확인할 것 (하나라도 깨지면 중단하고 결과만 보고):**

1. `CLAUDE_CONFIG_DIR`를 다른 경로로 준 세션이 `~/.claude/CLAUDE.md`와 `rules/`를 정말 안 읽는가
2. 그 상태에서 `--settings`로 주입하는 `enabledPlugins`(superpowers·serena·caveman·ponytail)가 그대로 뜨는가
   — 플러그인 캐시가 `~/.claude/plugins/`에 있으므로 여기서 깨질 가능성이 가장 높다
3. `.claude-logs/` 로깅과 busy 마커 훅이 그대로 도는가

**산출물:** 코드 변경 없이 `docs/architect-review/`에 결과 한 페이지. 1이 안 되면 이 항목은 사용자 확인
항목(T7)으로 넘긴다.

---

## T5 (P3) — 세션 내 재Read 금지 + 큰 파일은 offset/limit

6.4%. 세션 내 중복 Read가 developer 191회(중복 77,841줄), reviewer 27회, architect 29회, lead 11회.
증폭까지 반영하면 developer 역할 입력의 10.3%다. 그리고 Read 1,307회 중 `offset`/`limit` 사용은 **0회**로,
704줄·1,363줄짜리 파일을 매번 통째로 읽었다.

**파일:** `CLAUDE.md` (이 리포의 것 — `setup-team.sh`가 `$PROJECT_DIR/CLAUDE.md`에 마커 블록으로 병합하므로
모든 파인에 한 번에 적용된다. 역할별 `team/*.md`에 중복해서 넣지 말 것)

**변경:** `### 보고 규칙 (모든 역할 공통)` 절 앞에 다음 절을 추가한다.

```markdown
### 파일 읽기 규칙 (모든 역할 공통)

- **같은 세션에서 이미 읽은 파일을 다시 Read하지 않는다** — 컨텍스트에 한 번 들어간 내용은 그 세션의 남은 모든
  턴에서 다시 청구된다. 내용이 기억나지 않으면 다시 읽지 말고 앞선 대화에서 찾는다
- 파일을 수정한 직후 확인용으로 다시 읽지 않는다 — Edit/Write가 실패하면 그 자리에서 에러가 난다
- **300줄이 넘는 파일은 `offset`/`limit`으로 필요한 구간만 읽는다** — 어디를 봐야 할지 모르면 Grep으로 줄 번호를
  먼저 찾고 그 주변만 읽는다
```

**검증:** 문서 변경이라 자동 검증은 없다. 적용 후 며칠간 `.claude-logs/developer.jsonl`에서 세션 내 중복 Read
건수를 다시 세어 191 → 0에 수렴하는지 본다.

---

## T6 (P4) — lead의 화면 폴링·금지 통신 차단

토큰 절감은 작지만 규칙 정합성 문제다. `lead.md`에 이미 "주기적으로 폴링하지 않는다"가 있는데도
`tmux capture-pane` 109회, `tmux send-keys` 24회(CLAUDE.md가 명시적으로 금지), `SendMessage` 2회가 나왔다.
**규칙 문구를 더 넣는 것으로는 해결되지 않는다 — 구조로 막는다.**

**파일:** `setup-team.sh` — `start_claude_in_pane()`의 lead 분기(`lead_settings_json`)

**변경:** lead 파인 설정에만 deny 규칙을 넣는다.

```bash
    local lead_deny_json="\"permissions\":{\"deny\":[\"Bash(tmux send-keys:*)\"]},"
```

`lead_settings_json`의 `{${plugins_json}` 뒤에 끼운다.

**먼저 검증할 것:** 파인은 `--dangerously-skip-permissions`로 뜬다. 이 모드에서 `deny` 규칙이 실제로
차단하는지 확인한다 — 차단되지 않으면 이 방식을 폐기하고, `pretooluse_json`에 `tmux send-keys`를 만나면
비영(non-zero)으로 종료하는 훅을 추가하는 쪽으로 전환한다(`bin/log-hook`과 같은 자리에 붙인다).

**추가 문구 1건 (`team/lead.md`의 `## 하지 말 것`):**

```markdown
- `git diff`·`grep`으로 코드 내용을 직접 읽기 — 커밋(스테이징·메시지 작성·main 반영)은 예외로 직접 하지만,
  변경 내용의 판단은 reviewer·architect의 보고로 받는다. 실측에서 lead의 입력이 architect를 넘어선 원인이다
```

---

## T7 — 착수 금지 / 사용자 확인 필요

**caveman·ponytail 플러그인을 파인에서 제외하는 건.** 약 2.9% (주입 프롬프트 ~9.5KB + 스킬·에이전트 목록 ~2.8KB,
턴당 ~3.75K 토큰).

**변경하면 이렇게 된다 (참고용, 실행하지 말 것):** `setup-team.sh`의 `PLUGIN_ROLES`에서

```bash
    ["ponytail@ponytail"]="*"
    ["caveman@caveman"]="*"
```

값을 `""`로 바꾸거나 특정 역할만 남긴다.

**왜 확인이 필요한가:** 두 플러그인은 사용자가 능동적으로 켠 개인 설정이다. 토큰만 보면 끄는 쪽이 맞지만,
출력 스타일과 구현 판단 기준을 바꾸는 설정이라 비용만으로 결정할 사안이 아니다.

**확인할 때 같이 전할 사실:** 이 변경은 파인 설정(`--settings`)에만 적용되므로 사용자의 개인 Claude Code
세션에는 영향이 없다. 파인에서만 빠지고 평소 쓰던 세션에서는 그대로 동작한다. 역할별로 갈라도 된다
(예: developer·reviewer만 유지, lead·architect는 제외).

---

## 실행 순서

1. **T1 + T3** — 같은 `env_json` 한 줄을 건드리므로 한 번에 처리한다. 효과가 가장 크고 되돌리기도 쉽다
2. **T5** — 문서 한 곳 수정. T1/T3과 독립이라 병행 가능
3. **T6** — deny 규칙 동작 확인이 먼저다
4. **T4** — 스파이크. 결과만 문서로
5. **T2** — T1이 들어간 뒤에 문구를 확정한다
6. **T7** — 사용자 확인 전까지 착수 금지
