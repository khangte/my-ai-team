# My AI team

- Claude Code 인스턴스 여러 개를 tmux 파인에 띄우는 오케스트레이션 셋업
- 구성: 팀장 1명 + 팀원 5명의 멀티에이전트 팀

## 구조

```
CLAUDE.md          모든 파인 공통 규칙 요약 + 상세 문서 포인터 (팀 구성·통신·로깅·rtk — 역할 무관)
team/              파인별 역할 지시서 + 팀 구성 (--append-system-prompt로 주입, 프로젝트별 오버라이드 가능)
  ├ config.sh        팀 구성 기본값 템플릿 (세션명/인원/모델)
  ├ say              파인 간 메시지 전송 래퍼 (setup-team.sh가 각 파인 PATH에 등록)
  ├ log-hook         프롬프트·툴 사용을 .claude-logs/{역할}.jsonl에 기록하는 훅
  └ {역할}.md         역할별 지침 (lead/architect/researcher/designer/developer/reviewer)
docs/              설계 배경·실측 분석 문서
Dockerfile         팀 환경용 컨테이너 이미지 정의 (격리 실행할 때)
setup-docker.sh    Docker로 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행
setup-native.sh    WSL 등 호스트에 직접 의존성 설치 (Docker 없이 실행할 때)
setup-team.sh      tmux 세션 구성 + 각 파인에서 claude 실행 (핵심 스크립트)
```

### 런타임 산출물

- `setup-team.sh`는 실행할 때마다 **대상 프로젝트 루트**에 `.team/`을 새로 생성
  - 내용: 역할별 스킬 심볼릭 링크 + `_runtime/`의 조립된 역할 지침·훅 설정
  - 매 실행마다 지워지고 다시 만들어짐 → 대상 프로젝트 `.gitignore`에 `.team/` 추가 권장
- 프롬프트·툴 로그(`.claude-logs/`)도 같은 이유로 `.gitignore`에 추가 권장
  - 로그 디렉터리가 자기 자신을 무시하는 `.gitignore`를 내부에 생성하므로 필수는 아님
  - 다만 프로젝트 `.gitignore`에 한 줄 적어두면 제외 의도가 명시됨
  - 상세는 아래 "프롬프트·툴 로깅" 참고

### 이 저장소의 위치

- 이 저장소 자체는 개발 대상이 아니라 **팀 오케스트레이션 엔진**
- 실제 개발할 프로젝트는 별도 폴더에 존재
- `setup-team.sh`가 그 폴더를 인자로 받아 그 안에서 claude 인스턴스를 실행
- 실제 **하네스** = 만들어진 tmux 세션 + 그 안의 claude 프로세스들

## 실행 방식 및 사용법

|               | WSL 네이티브                        | Docker                                            |
| ------------- | ----------------------------------- | ------------------------------------------------- |
| 격리          | 없음 (호스트에 직접 설치)           | 컨테이너로 격리                                   |
| 적합한 경우   | 혼자 개발, 빠른 반복                | 팀 배포, 환경 재현성 필요                         |
| 진입 스크립트 | `setup-native.sh` → `setup-team.sh` | `setup-docker.sh` (내부에서 `setup-team.sh` 실행) |

### 진입

먼저 이 저장소를 clone(아래 예시는 `~/ai-setup` 기준).

```bash
git clone https://github.com/khangte/my-ai-team.git ~/ai-setup
```

- 모든 스크립트가 프로젝트 경로를 `realpath`로 해석
- 따라서 아래 두 방식의 동작이 동일
  - `ai-setup/` 안에서 상대경로로 실행
  - 대상 프로젝트(작업 디렉터리)에서 `ai-setup/` 스크립트를 가리켜 실행

#### WSL 네이티브

```bash
# ai-setup/ 안에서 실행
./setup-native.sh                       # 최초 1회: tmux/claude/rtk/bun 등 의존성 설치
./setup-team.sh /path/to/project        # 지정한 프로젝트로 팀 세션 실행

# 작업 디렉터리(프로젝트 루트)에서 실행
~/ai-setup/setup-native.sh              # 최초 1회
~/ai-setup/setup-team.sh .              # 현재 디렉터리를 프로젝트로 지정
```

#### Docker

```bash
# ai-setup/ 안에서 실행
./setup-docker.sh /path/to/project      # 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행

# 작업 디렉터리(프로젝트 루트)에서 실행
~/ai-setup/setup-docker.sh .            # 현재 디렉터리를 프로젝트로 지정
```

> `setup-team.sh` 인자 규칙
>
> - 인자 생략 시 환경변수 `$PROJECT_DIR`, 그것도 없으면 **현재 디렉터리** 사용
> - 상대·절대 경로 모두 허용
> - 세션 이름 기본값은 `team1`, `team/config.sh`의 `SESSION=` 값으로 변경 가능
>   (아래 "프로젝트별 팀 구성 커스터마이징" 참고)

Docker 환경의 특이점:

- `Dockerfile`은 npm/rtk/bun을 `/opt` 하위에 설치
  - 이유: 컨테이너 재생성 시 `/home/user`가 named volume(`claude-home`)으로 덮어써짐
  - WSL 네이티브는 이 제약이 없어 기본 경로 사용
- 컨테이너 이름은 `claude-env`로 고정, `sleep infinity`로 상주
  - 세션에서 빠져나온 뒤 재접속할 때 `setup-docker.sh` 재실행 불필요(재접속 방법은 아래)

### setup-team.sh 실행되면

1. 의존성·인증 확인
   - tmux/claude/rtk/bun 설치 여부 확인
   - `claude auth status`로 로그인 여부 확인 (미로그인 시 `/login` 안내 후 대기)
2. 도구 준비
   - rtk 훅 초기화
   - gstack 스킬(`/office-hours`, `/review` 등 슬래시 커맨드) 설치
3. 필수 마켓플레이스 플러그인(superpowers/serena/ponytail/caveman) 설치 — 역할별 활성화는 5번이 담당
4. 역할별 스킬 제한 — `.team/{역할}/.claude/skills`에 그 역할이 쓸 스킬만 링크
5. tmux 세션 구성
   - 팀 인원 수만큼 파인 분할
   - 파인 타이틀은 대문자로 표시 (예: `LEAD`, `ARCHITECT`)
6. 각 파인에서 지정 모델로 `claude --dangerously-skip-permissions` 실행 — 역할 지침·훅 설정·플러그인 활성화 주입
7. 완료 후 `tmux attach -t [세션명]` 접속 안내

### 세션 확인 및 종료

```bash
# team1: 세션명 예시
tmux attach -t team1                          # 접속 (WSL 네이티브)
docker exec -it claude-env bash -lc "tmux attach -t team1"   # 접속 (Docker — 컨테이너 재진입 후 attach)
tmux capture-pane -t team1:0.N -p | tail -5   # N번 파인 진행 상황만 확인
tmux kill-session -t team1                    # 세션 종료
```

### `--dangerously-skip-permissions`를 쓰는 이유

- 각 파인이 이 플래그로 실행됨 — 툴 사용마다 사람 승인이 필요하면 멀티에이전트 자동 진행이 불가능해서
- 대가: 파인이 확인 없이 파일을 수정·삭제 → **git으로 관리되는 프로젝트**에서 쓰거나 Docker로 격리 권장
- 파급효과: 권한 우회 세션은 cross-session messaging도 기본 승인 대기로 보류되는데, 사람이 안 붙어 있어
  `dialogExpiry`(기본 5분) 후 그대로 폐기됨 → `setup-team.sh`가 각 파인에 `crossSessionInbound: accept`를
  함께 주입 (아래 "팀 밖 세션에서 파인 호출" 참고)

## CLAUDE.md와 team/ — 지침이 파인에 로딩되는 방식

파인 지침은 두 층으로 구성된다.

1. **공통 규칙 — 대상 프로젝트의 `CLAUDE.md`**
   - `setup-team.sh`가 연 프로젝트 폴더(`$PROJECT_DIR`)의 `CLAUDE.md`
   - Claude Code가 세션 시작 시 자동으로 읽고, 모든 파인에 동일 적용
   - 이 저장소의 `CLAUDE.md`는 gstack skill routing 같은 역할 무관 공통 규칙만 포함
   - 역할별 지시(팀원 배분, "하지 말 것" 등)는 여기에 넣지 않음
     — architect·developer 등 다른 파인도 같은 내용을 받아버리기 때문

2. **역할별 지침 — `team/{역할}.md`**
   - 각 파인에서 `claude` 실행 시, `MEMBER_NAMES`의 이름에 대응하는
     `team/{이름}.md`를 읽어 `--append-system-prompt`로 주입
     - 예: lead 파인 → `team/lead.md`, architect 파인 → `team/architect.md`
   - 대응 파일이 없으면 시스템 프롬프트 추가 없이 그냥 실행
     — 커스텀 `team/config.sh`로 낯선 이름을 쓸 때의 안전한 기본 동작
   - 오버라이드 규칙은 `team/config.sh`와 동일
     - **대상 프로젝트 루트**(`$PROJECT_DIR/team/{이름}.md`)에 파일이 있으면 우선 사용
     - 없으면 **이 저장소**(`team/{이름}.md`)의 기본값으로 폴백
   - 결과: 대부분의 프로젝트는 기본 지침을 그대로 사용하고,
     특정 역할만 바꾸려면 그 프로젝트 루트에 `team/{역할}.md` 한 파일만 두면 됨

## 프로젝트별 팀 구성 커스터마이징

- 기본 팀 구성은 `setup-team.sh`에 내장 — lead/architect/researcher/designer/developer/reviewer 6인
- 인원 수·모델 배정을 프로젝트마다 다르게 하려면 **대상 프로젝트 루트**에 `team/config.sh` 배치
- 해당 파일이 있으면 자동 로드되어 기본값을 덮어씀

```bash
# <프로젝트_경로>/team/config.sh — 3인 팀으로 축소하는 예시
SESSION="team1"                                    # tmux 세션 이름
declare -a MEMBER_NAMES=("lead" "developer" "reviewer")
declare -a MEMBER_MODELS=(
    "claude-sonnet-5"
    "claude-sonnet-5"
    "claude-sonnet-5"
)
```

- `MEMBER_NAMES`와 `MEMBER_MODELS`는 배열 길이가 같아야 함
- 파인 개수는 배열 길이로 자동 계산
- 이 저장소의 `team/config.sh`는 기본값(6인)과 동일한 내용의 템플릿 — 복사해서 수정하면 됨
- 이름을 바꾸면 대응하는 `team/{이름}.md`도 필요(없으면 역할 지침 없이 실행 — 위 "CLAUDE.md와 team/" 참고)

## 파인 간 통신 — `team/say`

- 파인끼리는 `say`로만 메시지를 주고받음
- `setup-team.sh`가 `team/`을 각 파인 PATH에 등록 → 경로 없이 바로 호출

```bash
say :0.0 "[developer] 로그인 기능 구현 완료"   # 파인 번호로 지정
say lead  "[developer] 로그인 기능 구현 완료"   # 파인 타이틀(역할 이름)로도 가능
```

`tmux send-keys`를 직접 쓰지 않는 이유: `Enter`가 별개 인자라 누락되기 쉽고, 누락 시 메시지가
상대 입력창에 텍스트로만 남고 전송되지 않음. `say`는 Enter를 항상 부착해 이를 방지.

파인 밖(호스트 셸)에서 호출:

- PATH에 없으므로 경로와 세션명을 함께 지정 — `./team/say team1:0.4 "..."`

### 팀 밖 세션에서 파인 호출 — `SendMessage`

`say`와 별개로, Claude Code 자체의 cross-session messaging도 파인마다 켜져 있어
팀 밖에서 도는 일반 Claude 세션이 파인에 직접 지시하는 것도 가능은 하다.
다만 실제로는 lead 파인에 `tmux attach`로 붙어 명령하는 경우가 대부분이고,
이 경로는 lead를 거치지 않고 특정 파인 하나를 바로 찔러야 할 때 정도에 쓴다.

- 각 파인이 자기 인박스 소켓을 바인딩하므로 `/list-agents`에 6개가 그대로 보임
- 이름은 cwd 기반 자동 생성 — `lead-1f`, `developer-a7` 형태 (tmux 파인 번호도 함께 표시됨)
- 사용자는 자연어로 지시하면 됨 — `lead에게 "..." 전해줘`
- 이름이 겹치면 `to`에 `lead-1f [bba91f]`처럼 ref를 붙여야 함

`say`와의 차이:

|                       | `say`                        | `SendMessage`                                            |
| --------------------- | ---------------------------- | -------------------------------------------------------- |
| 전달 방식             | tmux 입력창에 타이핑         | 세션 간 소켓                                             |
| 수신 파인이 보는 형태 | 사람이 친 것과 **구분 불가** | `<cross-session-message from=...>` 태그 + 신뢰 안내 동반 |
| 유휴 대기 큐          | 있음                         | 없음 (도구 호출 사이 삽입)                               |
| 훅에서 발신           | 가능 (셸 스크립트)           | 불가 (도구 호출)                                         |

제약:

- **Docker 실행 시 호스트에서는 파인이 보이지 않음** — 컨테이너가 자체 파일시스템을 가져 서로를 찾지 못함. 네이티브 실행에서만 유효
- 발신 측(파인) 화면에 "held for approval" 중간 알림이 먼저 뜰 수 있음(팀 밖 세션이 권한을 묻는 모드라서) — 이후 정상 전달됨
- 파인끼리는 여전히 `say`를 쓴다 — 유휴 대기 큐·전송 검증·`SAY_NOWAIT` 인터럽트·Stop 훅 발신이 `SendMessage`에는 없다

상대가 작업 중이면 큐에 쌓았다가 유휴가 되면 자동 전송(발신 파인은 대기하지 않음).
`SAY_NOWAIT=1`이면 큐를 건너뛰고 즉시 전송 — 긴급 중단 지시용.

Enter 누락부터 큐 도입까지, 통신이 깨졌던 유형과 각각의 대응은 [docs/pane-messaging.md](docs/pane-messaging.md) 참조.

### 보고 경로

- 평상시 1홉 — 각 파인 → lead
- 설계 판단이 필요한 건만 architect 경유

| 상황                           | 경로                        |
| ------------------------------ | --------------------------- |
| 일반 완료 보고                 | 각 파인 → lead              |
| 설계 이탈 (developer/designer) | 파인 → architect → lead     |
| 리뷰 승인                      | reviewer → lead             |
| 리뷰 — 코드 품질 수정요청      | reviewer → developer (직행) |
| 리뷰 — 설계 판단 필요          | reviewer → architect → lead |

### Stop 훅 — 보고 누락 방지

- 파인이 `say` 실행을 잊어도 lead가 완료를 알 수 있도록, `setup-team.sh`가 lead를 뺀 각 파인에 Stop 훅을 주입해 응답 종료 시 완료 신호를 자동 전달 (폴링 불필요)
- 예외: 방금 `say`로 보고했으면 생략 / lead 자신은 대상 제외 (무한루프 방지)

## 프롬프트·툴 로깅 — 재현성과 추적

배경:

- 입력한 질문 / 실행한 명령 / 참조한 파일이 남아 있어야 결과 재현과 원인 추적이 가능

구현:

- `setup-team.sh`가 모든 파인에 `UserPromptSubmit`·`PreToolUse` 훅(`team/log-hook`)을 주입해 자동 기록

```
$PROJECT_DIR/.claude-logs/
├── .gitignore        내용은 "*" — 디렉터리가 스스로를 커밋에서 제외
├── lead.jsonl
├── developer.jsonl
└── ...               역할당 하나씩 (그 파인이 처음 동작할 때 생성)
```

형식:

- 한 줄이 JSON 하나인 JSONL
- 프롬프트·툴 두 종류가 시간순으로 섞여 기록

```json
{"ts":"...","role":"developer","event":"UserPromptSubmit","session":"s1","prompt":"로그인 기능 구현해줘"}
{"ts":"...","role":"developer","event":"PreToolUse","session":"s1","tool":"Write","input":{"file_path":"/a/b.py","content_len":500}}
```

복원 방법:

- `session`으로 같은 세션의 프롬프트와 툴 호출을 묶음
- `ts`로 순서를 정렬
- 결과: "어떤 지시에서 시작해 어떤 명령으로 이어졌는지"가 복원됨

### 설계상의 선택

- **역할별로 파일을 나눈다** — 파인 6개가 병렬로 도는 구조라 한 파일에 쓰면 경합·귀속 불명 발생
- **`.team/` 바깥에 둔다** — `.team/`은 매 실행 `rm -rf` 대상이라 거기 두면 세션 재시작 시 소실
- **작업 대상 리포의 `.gitignore`를 건드리지 않는다** — 대신 로그 디렉터리 안에 `.gitignore`(`*`)를 둬서 스스로를 제외, 남의 리포에 흔적 없이 커밋 제외 달성
- **파인이 자기 로그를 읽을 수 있다** — cwd는 `.team/{역할}/`지만 역할 지침에 실제 프로젝트 루트가 안내됨
- **본문은 길이만 남긴다** — Write/Edit 전문을 남기면 로그가 빠르게 비대해지고 시크릿 노출 표면도 커짐. 재현에 필요한 건 "무엇을 건드렸나"지 전문이 아님

### 시크릿 처리

- 마스킹 범위: 알려진 패턴(`sk-`, `ghp_`, `AKIA`, `xox*-`, `API_KEY=` 등), `.env`를 건드리는 명령(통째로 가림), Read 계열(경로만 기록)
- 한계: 임의 형식의 키를 프롬프트에 직접 붙여넣으면 패턴에 안 걸림 — 보완으로 로그 파일을 `600` 권한 생성. 훅 실패 시 로그만 포기, 파인 작업은 막지 않음

### 단독 실행에서는 쌓이지 않는다

- 로깅 훅은 `setup-team.sh`가 `--settings`로 주입하는데, `--settings`는 전역 `~/.claude/settings.json`을
  병합이 아니라 **대체**함 → 그 스크립트를 거치지 않고 `claude`를 단독 실행하면 **로그가 남지 않음**

| 실행 방식            | 훅 소스                        | 로깅    |
| -------------------- | ------------------------------ | ------- |
| `setup-team.sh` (팀) | `--settings`로 주입            | 쌓임    |
| `claude` 단독 실행   | 전역 `~/.claude/settings.json` | 안 쌓임 |

단독 실행에도 로그를 남기려면:

- `~/.claude/settings.json`에 같은 훅 추가 — `team/log-hook <역할> "$CLAUDE_PROJECT_DIR"`
- 단, 어떤 프로젝트에서 claude를 띄우든 전부 로그가 쌓인다는 점 감안

## 역할별 스킬 제한

- 문제: gstack setup은 스킬 수십 개를 `~/.claude/skills/`에 전부 설치하고, 그 frontmatter가 파인이 뜰 때마다
  시스템 프롬프트에 포함됨 → 파인 6개 × 매 턴이라 고정비가 큰데, 대부분은 역할과 무관한 스킬
- 해결: `~/.claude/skills`는 유저 전역이라 파인별 구성이 불가하므로, `setup-team.sh`가 파인마다
  `.team/{역할}/.claude/skills`에 **필요한 스킬만 심볼릭 링크**하고 그 디렉터리를 cwd로 실행,
  `--setting-sources project`로 유저 전역·플러그인 스킬은 차단

| 역할       | 허용 스킬                                                       |
| ---------- | --------------------------------------------------------------- |
| lead       | (없음 — 배분·수합·git 커밋만 하므로 gstack 스킬 불필요)         |
| architect  | `spec` `diagram` `document-generate` `health` `plan-eng-review` |
| researcher | `scrape` `browse` `investigate`                                 |
| designer   | `design-consultation` `design-review` `design-html` `diagram`   |
| developer  | `investigate` `health` `codex` `learn`                          |
| reviewer   | `review` `qa` `health` `investigate`                            |

### superpowers 스킬

[superpowers](https://github.com/obra/superpowers)는 gstack과 달리 **플러그인**이라
`--setting-sources project`에 통째로 차단된다. 그래서 gstack과 같은 방식으로
역할별 필요한 것만 `.team/{역할}/.claude/skills`에 링크해 되살린다
(`setup-team.sh`의 `SUPERPOWERS_SETS`).

| 역할      | 배정 스킬                                                                |
| --------- | ------------------------------------------------------------------------ |
| lead      | `finishing-a-development-branch`                                         |
| architect | `brainstorming` `writing-plans`                                          |
| designer  | `brainstorming`                                                          |
| developer | `test-driven-development` `systematic-debugging` `receiving-code-review` |
| reviewer  | `verification-before-completion`                                         |

- researcher는 배정 없음 — 14개 중 조사 업무에 대응하는 스킬이 없다
- gstack은 래퍼의 `SKILL.md`만 링크하지만, superpowers는 `references/` 등 하위 파일을
  런타임에 읽으므로 **스킬 디렉터리를 통째로** 링크한다
- 플러그인 설치 경로에 버전 디렉터리가 끼므로(`.../superpowers/6.2.0/skills`)
  경로를 고정하지 않고 최신 버전을 골라 쓴다. 미설치면 경고만 내고 넘어간다

배정에서 뺀 것과 그 이유:

| 스킬                                                        | 제외 이유                                                        |
| ----------------------------------------------------------- | ---------------------------------------------------------------- |
| `dispatching-parallel-agents` `subagent-driven-development` | 파인 6개가 이미 병렬 실행 단위 — 파인 대신 서브에이전트를 띄운다 |
| `requesting-code-review`                                    | 리뷰어 서브에이전트를 띄우게 되어 reviewer 파인이 논다           |
| `using-git-worktrees`                                       | 파인 6개가 같은 워킹트리를 공유하는 구조와 충돌                  |
| `using-superpowers`                                         | "1%라도 해당되면 무조건 스킬 호출" — 전 파인 고정비만 늘어남     |
| `executing-plans` `writing-skills`                          | 각각 별도 세션 실행 전제 / 팀 업무 아님                          |

이 스킬들은 단독 실행을 전제로 쓰여 있어(사용자에게 직접 승인 요청, 서브에이전트 dispatch 등)
그대로 두면 팀 구조와 어긋난다. 그래서 각 `team/{역할}.md`의 "## 스킬" 절에서 팀 규칙으로
바꿔 읽도록 명시했다 — 예로 `brainstorming`의 "유저 승인" 게이트는 lead(`:0.0`) 승인으로 치환.

`test-driven-development`를 developer에 배정하며 역할 경계도 조정: 기존 "테스트는 reviewer가"
방침과 TDD가 충돌해, 현재는 **TDD 사이클(red→구현→green)까지 developer**,
**커버리지·품질 최종 판정은 reviewer**로 나눴다.

제한 대상이 아닌 것:

- claude 빌트인 스킬
- `$PROJECT_DIR/.claude/skills`의 공용 스킬
- 위 둘은 모든 파인이 그대로 사용, 자세한 근거와 예외는 `setup-team.sh`의 `[4/7]` 섹션 주석 참조

스킬 제한 절감량은 [docs/token-cost.md](docs/token-cost.md) 참조.

## 역할별 플러그인 활성화

- 문제: caveman·ponytail·serena는 유저 전역 `~/.claude/settings.json`의 `enabledPlugins`로 켜지는데,
  파인은 `--setting-sources project`로 뜨는 탓에 이 전역 설정을 못 읽음 → 방치하면 **세 플러그인이
  파인에서 전혀 걸리지 않음**(실측 확인)
- 해결: `setup-team.sh`의 `[3/7]`이 플러그인을 설치하고, `start_claude_in_pane()`이 `--settings`에
  `enabledPlugins`·`extraKnownMarketplaces`를 역할별로 명시 주입(`PLUGIN_ROLES` 배열이 배분을 결정)

| 플러그인    | 배분                          | 이유                                                                                                                                                       |
| ----------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| caveman     | 전 파인                       | 고정비가 작고, 파인 5개가 응답을 압축한 만큼 lead가 입력에서 이득을 회수하는 구조라 일부만 켜면 그 효과가 샘                                               |
| ponytail    | 전 파인                       | 고정비가 작고 효과가 역할을 가리지 않음                                                                                                                    |
| serena      | developer·reviewer만          | 고정비가 가장 큼(MCP 툴 정의 30개). lead·researcher·designer·architect는 심볼 단위 코드 탐색을 쓸 일이 없어 죽은 무게                                      |
| superpowers | 없음(`enabledPlugins` 미주입) | 위 "superpowers 스킬" 절대로 `[4/7]`이 스킬 디렉터리를 역할별로 직접 링크하므로 이미 걸려 있음. 여기서 또 켜면 스킬 16개가 통째로 들어와 선별이 무의미해짐 |

`claude plugin enable`은 부르지 않는다 — 유저 전역 `settings.json`을 고쳐 팀 밖 세션까지 건드리는데,
파인 활성화는 `--settings`가 이미 담당하므로 불필요하다.

실측 고정비, PATH 관련 함정(활성화가 조용히 실패하는 경우)은 [docs/token-cost.md](docs/token-cost.md) 참조.

## Remote Control — 폰으로 lead 파인 제어

- Claude Code CLI 자체 기능 — 이 저장소 구조와 무관
- 사용법
  - lead 파인에 붙어 `/remote-control` 실행 → 접속 링크(또는 QR) 출력
  - claude.ai 계정으로 로그인된 기기에서 그 링크를 열면 lead 세션에 접속
  - 작업 중인 세션은 끊기지 않음
- 제약
  - claude.ai 구독 계정 로그인 필요 (조직 정책으로 막혀 있을 수 있음)
  - 세션당 연결은 하나만 유지 — 다른 파인에도 걸려면 파인별로 각각 실행
  - Docker 실행 시 컨테이너 밖에서의 접속 가능 여부는 포트·네트워크 설정에 따라 다름
