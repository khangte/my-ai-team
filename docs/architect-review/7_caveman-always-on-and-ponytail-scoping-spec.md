# caveman 상시 활성화 + ponytail 역할 축소 — 구현 스펙

- 작성: architect (구현은 developer 몫, 이 문서에서는 코드 변경 없음)
- 선행 결정(사용자 최종): **ponytail은 developer에만**, **caveman은 전 역할 유지**
  — `6_caveman-ponytail-role-scoping.md`의 caveman 전면 제외 권고는 채택되지 않았다
- 추가 요구: 파인 세션이 시작될 때마다(최초 기동, `/clear`, `/compact` 등) caveman이 확실히 켜질 것

## 1. 판정 — caveman 활성화용 커스텀 SessionStart 훅은 **불필요**

caveman 플러그인은 자체 SessionStart 훅을 갖고 있고, 그 훅에 matcher가 없다.

```json
// ~/.claude/plugins/cache/caveman/caveman/766dce6b1394/.claude-plugin/plugin.json
"hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/src/hooks/caveman-activate.js\"" } ] } ] }
```

matcher가 없으므로 `startup`·`resume`·`clear`·`compact` **모든 소스에서 발화**한다.
훅 스크립트도 소스별 분기를 명시적으로 구현해 둔다(`src/hooks/caveman-activate.js:167-181`):

- `startup` — `getDefaultMode()`로 모드를 새로 정한다
- 그 외 소스 — 기존 플래그(`~/.claude/.caveman-active`)가 유효하면 그것을 유지한다(세션 중 바꾼 모드를 덮지 않기 위함)
- `off`면 플래그를 지우고 규칙을 주입하지 않는다. 단 다음 `startup`에서 다시 기본값으로 살아난다

**실증 두 건.** lead가 관찰한 `SessionStart:compact hook success: CAVEMAN MODE ACTIVE`는 compact 소스,
그리고 이 architect 파인의 최초 기동 세션 시스템 프롬프트에는
`SessionStart:startup hook success: CAVEMAN MODE ACTIVE — level: full`이 들어와 있다.
즉 plain startup에서도 이미 켜진다 — `setup-team.sh`가 훅을 따로 걸 이유가 없다.

`getDefaultMode()` 우선순위(같은 파일 98-118행): `CAVEMAN_DEFAULT_MODE` 환경변수 →
cwd에서 상위로 올라가며 찾은 `.caveman/config.json`·`.caveman.json` → 사용자 config → 내장 기본값 `full`.
현재 파인은 어느 것도 두지 않았으므로 `full`로 떨어진다.

### 그렇다면 실제 위험은 어디인가

훅이 없어서 안 켜지는 게 아니라, **훅이 조용히 실패해서 안 켜진다.** 훅 커맨드는 `node`를 이름으로만 부르는데
node가 nvm 아래 버전 디렉터리(`~/.nvm/versions/node/v20.20.2/bin`)에 있다. PATH에 없으면 훅은
non-blocking으로 실패하고 파인은 caveman이 안 걸린 채 뜬다 — `docs/token-cost.md` 218-223행에 이미
lead 파인에서 재현된 사고로 기록돼 있다.

`setup-team.sh:42`가 `NVM_BIN`을 PATH에 넣지만 그건 **스크립트 자신의 셸**이다. 파인은 tmux 페인 셸에서
`setup-team.sh:281`의 `export PATH='$BIN_DIR':$PATH`로 뜨므로, node 경로는 tmux 서버가 물려준 환경에
의존한다. 서버가 다른 환경에서 미리 떠 있었다면 그대로 새는 자리다. **"매번 확실히 켜진다"를 보장하려면
고쳐야 할 곳은 여기 하나다.**

## 2. 구현 스펙

### C1. `setup-team.sh:462` — ponytail을 developer로 좁힌다

```bash
    ["ponytail@ponytail"]="developer"     # 이전: "*"
    ["caveman@caveman"]="*"               # 유지 (변경 없음)
```

### C2. `setup-team.sh:445-449` 주석 교체

기존 "ponytail·caveman은 전 파인에 준다 …" 문단을 아래로 바꾼다.

```bash
# caveman은 전 파인에 준다. 켠 파인이 아니라 lead가 이득을 회수하는 구조이고
# (파인들의 보고가 전부 lead 입력이 된다), 출력 문체를 팀 전체에서 통일하는 값이
# 토큰 고정비보다 크다는 사용자 결정이다. 비용·회수 실측은
# docs/architect-review/6_caveman-ponytail-role-scoping.md 참조.
#
# ponytail은 developer에만 준다. 사다리 7단 중 2~7단(기존 헬퍼 재사용, 표준
# 라이브러리, 네이티브 기능, 설치된 의존성, 한 줄 구현)이 전부 코드 대상이라
# 코드를 직접 쓰지 않는 역할에서는 1단 YAGNI만 남는데, 그 한 줄은 역할 지침에
# 문장으로 넣는 편이 100배 싸다(고정비 2.2K/호출 대 ~20토큰).
```

같은 블록 439행의 "파인 6개"는 designer 제외로 5개가 됐다. 한 글자 수정이라 이번에 같이 고친다.

### C3. `setup-team.sh:281` — node 경로를 파인 PATH에 명시한다 (caveman 상시 활성화의 실질 보장)

```bash
    tmux send-keys -t "$pane" \
        "cd '$work_dir' && unset CLAUDECODE && export PATH='$BIN_DIR'${NVM_BIN:+:'$NVM_BIN'}:\$PATH && $claude_bin ..." Enter
```

`NVM_BIN`은 41행에서 이미 구한 값이라 새로 계산하지 않는다. 비어 있으면 아무것도 붙지 않는다
(`${VAR:+...}`). 이렇게 하면 tmux 서버가 어떤 환경에서 떠 있었든 파인 셸에서 `node`가 잡히고,
caveman·ponytail의 SessionStart 훅이 조용히 실패하는 경로가 닫힌다.

### C4. `setup-team.sh:281` — caveman 모드를 파인 범위에서 고정 (선택, 권장)

같은 줄에 `export CAVEMAN_DEFAULT_MODE=full &&`을 추가한다. 사용자 개인 config가 나중에 lite/off로
바뀌어도 파인은 항상 full로 뜬다. 환경변수가 우선순위 1위라 리포·사용자 config를 건드리지 않는다.

**한계를 알고 넣을 것:** 이 핀은 `startup` 소스에만 적용된다. `/clear`·`/compact`에서는 훅이 기존
플래그를 우선하는데, 그 플래그 `~/.claude/.caveman-active`는 **파인 5개와 사용자 개인 세션이 공유하는
파일 하나**다. 누군가 `/caveman lite`를 하면 그 뒤 compact를 겪는 파인이 lite를 물려받는다.
파인별 격리가 필요해지면 그때 파인마다 `CLAUDE_CONFIG_DIR`를 갈라야 하는데, 그건 T4에서 실패로
결론난 접근이다(`3_t4-claude-config-dir-spike.md`). **지금은 격리하지 말고 이 한계를 문서에만 남긴다.**

### C5. `docs/token-cost.md:205-210` 배분 근거 갱신

`- **ponytail·caveman → 전 파인.** …` 항목을 두 항목으로 쪼갠다. 내용은 C2 주석과 같게 쓰고,
"일부 파인만 켜면 lead 압축 효과가 샌다"는 문장은 caveman 항목에만 남긴다(ponytail에는 해당 없음).
198-199행 고정비 표는 그대로 둔다.

### C6. 역할 지침 한 줄씩 — ponytail이 빠진 자리 보완

- `team/architect.md`의 `## 작업 방식`: `- 설계에 투기적 일반화·미리 만든 추상화를 넣지 않는다 (YAGNI)`
- `team/reviewer.md`의 리뷰 항목: `- 불필요한 추상화·투기적 일반화도 지적 대상에 포함한다`

researcher는 코드도 설계도 산출하지 않으므로 보완 문구를 넣지 않는다.

## 3. 검증

`setup-team.sh` 재실행은 tmux 세션을 kill 후 재생성하므로 **팀 전체가 끊긴다.** lead 승인 후 실행한다.

재기동 뒤 파인별 첫 턴에 어떤 모드가 주입됐는지 트랜스크립트로 확인한다.

```bash
for r in lead architect researcher developer reviewer; do
  f=$(ls -t ~/.claude/projects/-home-kang-ai-setup--team-$r/*.jsonl 2>/dev/null | head -1)
  printf '%-11s caveman=%s ponytail=%s\n' "$r" \
    "$(grep -c 'CAVEMAN MODE ACTIVE' "$f")" "$(grep -c 'PONYTAIL MODE ACTIVE' "$f")"
done
cat ~/.claude/.caveman-active
```

**기대값:** caveman은 5개 역할 모두 1 이상, ponytail은 developer만 1 이상이고 나머지 4개는 0,
플래그 파일 내용은 `full`.

0이 나오는 파인이 있으면 원인은 십중팔구 node 미해결이다. 해당 파인에서 `which node`로 확인한다
(C3가 들어갔다면 나오지 않아야 한다).
