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
setup-team.sh      tmux 세션 구성 + 각 파인에서 claude 실행 (핵심 스크립트)
setup-native.sh    WSL 등 호스트에 직접 의존성 설치 (Docker 없이 실행할 때)
Dockerfile         팀 환경용 컨테이너 이미지 정의 (격리 실행할 때)
setup-docker.sh    Docker로 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행
```

이 저장소 자체는 개발 대상이 아니라 **팀 오케스트레이션 엔진**이다. 실제로
개발할 프로젝트는 별도 폴더에 있고, `setup-team.sh`가 그 폴더를 인자로 받아
그 안에서 claude 인스턴스들을 실행한다.

## 실행 방식 및 사용법

|               | WSL 네이티브                        | Docker                                           |
| ------------- | ----------------------------------- | ------------------------------------------------ |
| 격리          | 없음 (호스트에 직접 설치)           | 컨테이너로 격리                                  |
| 적합한 경우   | 혼자 개발, 빠른 반복                | 팀 배포, 환경 재현성 필요                        |
| 진입 스크립트 | `setup-native.sh` → `setup-team.sh` | `setup-docker.sh` (내부에서 `setup-team.sh` 실행) |

### 진입

먼저 이 저장소를 clone한다(아래 예시는 `~/ai-setup` 기준):

```bash
git clone https://github.com/khangte/my-ai-team.git ~/ai-setup
```

모든 스크립트가 프로젝트 경로를 `realpath`로 해석하므로, `ai-setup/` 안에서
상대경로로 실행하든 대상 프로젝트(작업 디렉터리)에서 `ai-setup/` 스크립트를
가리켜 실행하든 동작은 같다.

**WSL 네이티브**

```bash
# ai-setup/ 안에서 실행
./setup-native.sh                       # 최초 1회: tmux/claude/rtk/bun 등 의존성 설치
./setup-team.sh /path/to/project        # 지정한 프로젝트로 팀 세션 실행

# 작업 디렉터리(프로젝트 루트)에서 실행
~/ai-setup/setup-native.sh              # 최초 1회
~/ai-setup/setup-team.sh .              # 현재 디렉터리를 프로젝트로 지정
```

**Docker**

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
3. tmux 세션을 열고 팀 인원 수만큼 파인 분할, 파인 타이틀은 대문자로 표시(예: `LEAD`, `ARCHITECT`)
4. 각 파인에서 지정된 모델로 `claude --dangerously-skip-permissions` 실행
5. 완료 후 `tmux attach -t [세션명]`으로 접속 안내

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
