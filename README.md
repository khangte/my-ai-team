# My AI team

Claude Code 인스턴스 여러 개를 tmux 파인에 띄워, 팀장 1명 + 팀원 5명 구성의
멀티에이전트 팀으로 다른 프로젝트를 개발하는 오케스트레이션 셋업.

## 구조

```
CLAUDE.md          팀장(lead) 역할 정의 + gstack 스킬 라우팅 규칙
team/              파인별 역할 지시서 + 팀 구성 (--append-system-prompt로 주입, 프로젝트별 오버라이드 가능)
  ├ config.sh        팀 구성 기본값 템플릿 (인원/모델)
  ├ say              파인 간 메시지 전송 래퍼 (setup-team.sh가 각 파인 PATH에 등록)
  └ {역할}.md         역할별 지침 (architect/researcher/designer/developer/reviewer/lead)
Dockerfile         팀 환경용 컨테이너 이미지 정의 (격리 실행할 때)
setup-docker.sh    Docker로 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행
setup-native.sh    WSL 등 호스트에 직접 의존성 설치 (Docker 없이 실행할 때)
setup-team.sh      tmux 세션 구성 + 각 파인에서 claude 실행 (핵심 스크립트)
```

`setup-team.sh`는 실행할 때마다 **대상 프로젝트 루트**에 `.team/`을 새로 만든다
(역할별 스킬 심볼릭 링크 + `_runtime/`의 조립된 역할 지침·훅 설정). 매 실행마다
지워지고 다시 생성되는 산출물이므로, 대상 프로젝트의 `.gitignore`에 `.team/`을
넣어두면 좋다.

이 저장소 자체는 개발 대상이 아니라 **팀 오케스트레이션 엔진**이다. 실제로
개발할 프로젝트는 별도 폴더에 있고, `setup-team.sh`가 그 폴더를 인자로 받아
그 안에서 claude 인스턴스들을 실행한다. `setup-team.sh`가 실행되어 만들어지는
tmux 세션과 그 안의 claude 프로세스들이 실제 **하네스**다.

## 실행 방식 및 사용법

|               | WSL 네이티브                        | Docker                                            |
| ------------- | ----------------------------------- | ------------------------------------------------- |
| 격리          | 없음 (호스트에 직접 설치)           | 컨테이너로 격리                                   |
| 적합한 경우   | 혼자 개발, 빠른 반복                | 팀 배포, 환경 재현성 필요                         |
| 진입 스크립트 | `setup-native.sh` → `setup-team.sh` | `setup-docker.sh` (내부에서 `setup-team.sh` 실행) |

### 진입

먼저 이 저장소를 clone한다(아래 예시는 `~/ai-setup` 기준):

```bash
git clone https://github.com/khangte/my-ai-team.git ~/ai-setup
```

모든 스크립트가 프로젝트 경로를 `realpath`로 해석하므로, `ai-setup/` 안에서
상대경로로 실행하든 대상 프로젝트(작업 디렉터리)에서 `ai-setup/` 스크립트를
가리켜 실행하든 동작은 같다.

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

> `setup-team.sh`는 인자를 생략하면 `$PROJECT_DIR` 또는 `~/project`를 쓰고,
> 상대/절대 경로 모두 받는다. 세션 이름은 기본 `team1`이며 `team/config.sh`의
> `SESSION=` 값으로 바꿀 수 있다(아래 "프로젝트별 팀 구성 커스터마이징" 참고).

`Dockerfile`은 컨테이너 재생성 시 `/home/user`가 named volume(`claude-home`)으로
덮어써지는 것을 고려해 npm/rtk/bun을 `/opt` 하위 경로에 설치한다. WSL
네이티브는 이 제약이 없어 기본 경로를 그대로 쓴다. Docker 컨테이너 이름은
`claude-env`로 고정이며 `sleep infinity`로 계속 떠 있으므로, 세션에서 빠져나온
뒤 재접속할 때 `setup-docker.sh`를 다시 실행할 필요 없다(재접속 방법은 아래).

### setup-team.sh 실행되면

1. tmux/claude/rtk/bun 설치 여부 확인, `claude auth status`로 로그인 여부 확인(미로그인 시 `/login` 안내 후 대기)
2. rtk 훅 초기화, gstack 스킬(`/office-hours`, `/review` 등 슬래시 커맨드) 설치
3. 역할별 스킬 제한 — `.team/{역할}/.claude/skills`에 그 역할이 쓸 스킬만 링크
4. tmux 세션을 열고 팀 인원 수만큼 파인 분할, 파인 타이틀은 대문자로 표시(예: `LEAD`, `ARCHITECT`)
5. 각 파인에서 지정된 모델로 `claude --dangerously-skip-permissions` 실행 (역할 지침·훅 설정 주입)
6. 완료 후 `tmux attach -t [세션명]`으로 접속 안내

### 세션 확인 및 종료

```bash
# team1: 세션명 예시
tmux attach -t team1                          # 접속 (WSL 네이티브)
docker exec -it claude-env bash -lc "tmux attach -t team1"   # 접속 (Docker — 컨테이너 재진입 후 attach)
tmux capture-pane -t team1:0.N -p | tail -5   # N번 파인 진행 상황만 확인
tmux kill-session -t team1                    # 세션 종료
```

## 프로젝트별 팀 구성 커스터마이징

기본 팀 구성(lead/architect/researcher/designer/developer/reviewer, 6인)은 `setup-team.sh`에 내장되어
있다. 프로젝트마다 인원 수나 모델 배정을 다르게 하고 싶으면, **대상
프로젝트 루트**에 `team/config.sh`를 두면 자동으로 로드되어 기본값을
덮어쓴다.

```bash
# <프로젝트_경로>/team/config.sh
declare -a MEMBER_NAMES=("팀장" "백엔드" "프론트")
declare -a MEMBER_MODELS=(
    "claude-opus-4-8"
    "claude-sonnet-5"
    "claude-sonnet-5"
)
```

`MEMBER_NAMES`와 `MEMBER_MODELS`는 배열 길이가 같아야 하며, 파인 개수는
배열 길이로 자동 계산된다. 이 저장소의 `team/config.sh`는 기본값과
동일한 내용의 템플릿이다.

## 파인 간 통신 — `team/say`

파인끼리는 `say`로만 메시지를 주고받는다. `setup-team.sh`가 `team/`을 각 파인의
PATH에 넣어주므로 경로 없이 바로 호출된다.

```bash
say :0.0 "[developer] 로그인 기능 구현 완료"   # 파인 번호로 지정
say lead  "[developer] 로그인 기능 구현 완료"   # 파인 타이틀(역할 이름)로도 가능
```

`tmux send-keys`를 직접 쓰지 않는 이유는 `Enter`가 별개 인자여서다. 하나라도
빠뜨리면 메시지가 상대 파인 입력창에 텍스트로 남은 채 전송되지 않고, 보낸 쪽은
보냈다고 착각한다. `say`는 Enter를 항상 붙이고, 텍스트가 입력창에 반영되기 전에
Enter가 도착해 무시되는 경우도 함께 막는다.

파인 밖(호스트 셸)에서 호출할 때는 PATH에 없으므로 경로와 세션명을 함께 준다 —
`./team/say team1:0.4 "..."`.

### 보고 경로

평상시 1홉(각 파인 → lead)이고, 설계 판단이 필요한 건만 architect를 경유한다.

| 상황                            | 경로                                    |
| ------------------------------- | --------------------------------------- |
| 일반 완료 보고                  | 각 파인 → lead                          |
| 설계 이탈 (developer/designer)  | 파인 → architect → lead                 |
| 리뷰 승인                       | reviewer → lead                         |
| 리뷰 — 코드 품질 수정요청       | reviewer → developer (직행)             |
| 리뷰 — 설계 판단 필요           | reviewer → architect → lead             |

### Stop 훅 — 보고 누락 방지

파인이 `say` 실행을 잊으면 lead는 그 파인이 끝났는지 알 수 없다. 그래서
`setup-team.sh`가 lead를 뺀 각 파인에 Stop 훅을 `--settings`로 주입한다. 파인이
응답을 마치면 harness가 훅을 실행해 "응답 종료" 신호를 lead에 자동 전달하므로,
lead는 주기적 폴링 없이 신호가 온 파인만 확인하면 된다.

방금 `say`로 본 보고를 보낸 경우엔 신호를 생략한다(본 보고에 이미 내용이 있어
lead 턴을 한 번 더 태울 이유가 없다). lead 자신은 훅 대상에서 제외된다 — 신호
수신처가 lead(`:0.0`)라 자기 응답마다 스스로에게 신호를 보내 무한 루프가 된다.

## 역할별 스킬 제한

gstack setup은 스킬 수십 개를 `~/.claude/skills/`에 전부 설치하고, 그 frontmatter는
파인이 뜰 때마다 시스템 프롬프트로 들어간다. 파인 6개 × 매 턴이라 고정비가 크고,
실제로 researcher가 `/ios-qa`를, reviewer가 `/design-shotgun`을 쓸 일은 없다.

`~/.claude/skills`는 유저 전역이라 파인별로 다르게 만들 수 없으므로,
`setup-team.sh`는 파인마다 `.team/{역할}/.claude/skills`에 **필요한 스킬만 심볼릭
링크**하고 그 디렉터리를 cwd로 claude를 띄운다. 이때 `--setting-sources project`로
유저 전역 스킬과 플러그인 스킬을 차단한다.

| 역할       | 허용 스킬                                                 |
| ---------- | --------------------------------------------------------- |
| lead       | (없음 — 배분·수합·git 커밋만 하므로 gstack 스킬 불필요)   |
| architect  | `spec` `diagram` `document-generate` `health` `plan-eng-review` |
| researcher | `scrape` `browse` `investigate`                           |
| designer   | `design-consultation` `design-review` `design-html` `diagram` |
| developer  | `investigate` `health` `codex` `learn`                    |
| reviewer   | `review` `qa` `health` `investigate`                      |

claude 빌트인 스킬과 `$PROJECT_DIR/.claude/skills`의 공용 스킬은 이 방식과
무관하게 모든 파인이 그대로 쓴다. 자세한 근거와 예외는 `setup-team.sh`의
`[1.6/5]` 섹션 주석 참조.

이 제한이 실제로 얼마나 줄이는지, 그리고 토큰 비용이 어디서 발생하는지는
[docs/token-cost.md](docs/token-cost.md) 참조.

## CLAUDE.md와 team/ — 지침이 파인에 로딩되는 방식

파인마다 지침은 두 층으로 구성된다.

1. **공통 규칙 — 대상 프로젝트의 `CLAUDE.md`**
   `setup-team.sh`가 연 프로젝트 폴더(`$PROJECT_DIR`)의 `CLAUDE.md`는
   Claude Code가 세션 시작 시 자동으로 읽으며, 모든 파인에 동일하게
   적용된다(이 저장소의 `CLAUDE.md`는 gstack skill routing 같은 역할
   무관 공통 규칙만 담는다). 역할별 지시(팀원 배분, "하지 말 것" 등)는
   여기에 넣지 않는다 — 그러면 architect·developer 등 다른 파인도 같은
   내용을 받아버린다.

2. **역할별 지침 — `team/{역할}.md`**
   `setup-team.sh`가 각 파인에서 `claude`를 실행할 때, `MEMBER_NAMES`의
   각 이름에 대응하는 `team/{이름}.md`를 읽어 `--append-system-prompt`로
   주입한다. 예: lead 파인은 `team/lead.md`, architect 파인은
   `team/architect.md`. 대응하는 파일이 없으면 시스템 프롬프트 추가 없이
   그냥 실행된다(커스텀 `team/config.sh`로 낯선 이름을 쓸 때의 안전한
   기본 동작).

   `team/config.sh`와 동일한 오버라이드 규칙이 적용된다: **대상 프로젝트
   루트**(`$PROJECT_DIR/team/{이름}.md`)에 파일이 있으면 그쪽을 우선
   사용하고, 없으면 **이 저장소**(`team/{이름}.md`)의 기본값으로
   폴백한다. 즉 대부분의 프로젝트는 기본 지침을 그대로 쓰고, 특정
   프로젝트에서 특정 역할의 지침만 다르게 하고 싶으면 그 프로젝트 루트에
   `team/{역할}.md` 한 파일만 두면 된다.

## Remote Control — 폰으로 lead 파인 제어

Claude Code CLI 자체 기능이라 이 저장소 구조와는 무관하다. lead 파인에 붙어
`/remote-control`을 실행하면 접속 링크(또는 QR)가 뜨고, claude.ai 계정으로
로그인된 기기에서 그 링크를 열면 lead 세션에 붙는다. 작업 중인 세션을 끊지
않는다.

- claude.ai 구독 계정 로그인이 필요하다(조직 정책으로 막혀 있을 수 있음).
- 세션당 연결은 하나만 유지된다 — 다른 파인에도 걸려면 파인별로 각각 실행한다.
- Docker로 띄운 경우 컨테이너 밖에서 접속 가능한지는 포트/네트워크 설정에 따라 다르다.
