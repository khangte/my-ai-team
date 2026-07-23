# my-ai-team

Claude Code 인스턴스 여러 개를 tmux 파인에 띄워, 팀장 1명 + 팀원 5명 구성의
멀티에이전트 팀으로 다른 프로젝트를 개발하는 오케스트레이션 셋업.

## 구조

```
CLAUDE.md          팀장(쭌) 역할 정의 + gstack 스킬 라우팅 규칙
setup-team.sh      tmux 세션 구성 + 각 파인에서 claude 실행 (핵심 스크립트)
team.config.sh     팀 구성 기본값 템플릿 (인원/모델)
setup-native.sh    WSL 등 호스트에 직접 의존성 설치 (Docker 없이 실행할 때)
Dockerfile         팀 환경용 컨테이너 이미지 정의 (격리 실행할 때)
docker-team.sh     Docker로 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행
workflows/         보조 워크플로 스크립트
```

이 저장소 자체는 개발 대상이 아니라 **팀 오케스트레이션 엔진**이다. 실제로
개발할 프로젝트는 별도 폴더에 있고, `setup-team.sh`가 그 폴더를 인자로 받아
그 안에서 claude 인스턴스들을 실행한다.

## 실행 방식 두 가지

| | WSL 네이티브 | Docker |
|---|---|---|
| 격리 | 없음 (호스트에 직접 설치) | 컨테이너로 격리 |
| 적합한 경우 | 혼자 개발, 빠른 반복 | 팀 배포, 환경 재현성 필요 |
| 진입 스크립트 | `setup-native.sh` → `setup-team.sh` | `docker-team.sh` (내부에서 `setup-team.sh` 실행) |

### WSL 네이티브

```bash
./setup-native.sh                       # 최초 1회: tmux/claude/rtk/bun 등 의존성 설치
./setup-team.sh /path/to/project        # 지정한 프로젝트로 팀 세션 실행
```

### Docker

```bash
PROJECT_DIR=/path/to/project ./docker-team.sh
```

`Dockerfile`은 컨테이너 재생성 시 `/home/user`가 named volume(`claude-home`)으로
덮어써지는 것을 고려해 npm/rtk/bun을 `/opt` 하위 경로에 설치한다. WSL
네이티브는 이 제약이 없어 기본 경로를 그대로 쓴다.

## 사용법

```bash
./setup-team.sh                         # 인자 없으면 $PROJECT_DIR 또는 ~/project 사용
./setup-team.sh ../projects/PROJECT     # 상대/절대 경로 모두 가능
```

실행되면:
1. tmux/claude/rtk/bun 설치 여부 확인, claude 로그인 여부 확인(미로그인 시 안내)
2. rtk 훅 초기화, gstack 스킬(`/office-hours`, `/review` 등 슬래시 커맨드) 설치
3. `team1` tmux 세션을 열고 팀 인원 수만큼 파인 분할
4. 각 파인에서 지정된 모델로 `claude --dangerously-skip-permissions` 실행
5. 완료 후 `tmux attach -t team1`으로 접속 안내

세션 확인 및 종료:
```bash
tmux attach -t team1              # 접속
tmux capture-pane -t team1:0.N -p | tail -5   # N번 파인 진행 상황만 확인
tmux kill-session -t team1        # 세션 종료
```

## 프로젝트별 팀 구성 커스터마이징

기본 팀 구성(쭌/민준/지훈/수아/서연/태양, 6인)은 `setup-team.sh`에 내장되어
있다. 프로젝트마다 인원 수나 모델 배정을 다르게 하고 싶으면, **대상
프로젝트 루트**에 `team.config.sh`를 두면 자동으로 로드되어 기본값을
덮어쓴다.

```bash
# <프로젝트_경로>/team.config.sh
declare -a MEMBER_NAMES=("팀장" "백엔드" "프론트")
declare -a MEMBER_MODELS=(
    "claude-opus-4-8"
    "claude-sonnet-5"
    "claude-sonnet-5"
)
```

`MEMBER_NAMES`와 `MEMBER_MODELS`는 배열 길이가 같아야 하며, 파인 개수는
배열 길이로 자동 계산된다. 이 저장소 루트의 `team.config.sh`는 기본값과
동일한 내용의 템플릿이다.

## CLAUDE.md와 팀장 역할

`setup-team.sh`로 연 프로젝트 폴더에 `CLAUDE.md`가 팀장 역할 지시서
(`~/project/CLAUDE.md` 참고: 사용자 지시 수령 → 분석 → tmux
`send-keys`로 팀원 파인에 배분 → 완료 보고 수합)를 포함하고 있어야
0번 파인(팀장)이 그 규칙에 따라 동작한다. 대상 프로젝트에 아직 이런
지시서가 없다면, 각 파인은 독립적인 claude 인스턴스로만 동작하고 팀장의
자동 배분은 일어나지 않는다.
