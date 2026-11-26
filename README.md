# My AI team

Claude Code와 Codex를 역할별로 선택해 tmux 패널에서 함께 실행하는 멀티에이전트 팀 환경입니다.
프로젝트마다 팀 구성·모델·역할 지침을 바꿀 수 있습니다.

## 빠른 시작

```bash
git clone https://github.com/khangte/my-ai-team.git ~/ai-setup
cd ~/ai-setup

# WSL / apt 기반 Linux
./install/wsl.sh /path/to/project    # 최초 1회 의존성 설치
./setup-team.sh /path/to/project    # 팀 실행

tmux attach -t team1               # 팀 세션 접속
```

- 사용하는 공급자 로그인 필요: Claude는 `/login`, Codex는 `codex login` (미로그인 시 실행 중 안내)
- 프로젝트 경로 생략 시: `$PROJECT_DIR` → 현재 디렉터리 순

### macOS

Homebrew 필요, Homebrew bash로 실행(기본 bash 3.2 미지원)

```bash
./install/mac.sh /path/to/project
"$(brew --prefix)/bin/bash" ./setup-team.sh /path/to/project
```

### 팀원과 같은 환경 공유 (Docker)

저장소의 `Dockerfile`로 `claude-team` 이미지를 빌드해, 팀원 모두 같은 OS·도구 구성에서 팀을 실행합니다. Claude Code·Codex는 빌드 시점의 최신 버전이 설치됩니다.

```bash
./install/docker.sh /path/to/project
docker exec -it claude-env-<프로젝트이름>-<경로체크섬> bash -lc "tmux attach -t team1"
```

### 기본 실행 옵션

  - `claude --dangerously-skip-permissions`
  - `codex --dangerously-bypass-approvals-and-sandbox`
  > 파일 수정·삭제에 승인을 받지 않음 → git 관리 프로젝트나 격리 환경에서 사용

## 팀 구성

기본 팀 6인

| 역할 | 한글 표시 이름 | 담당 |
| --- | --- | --- |
| lead | 팀장 | 작업 배분·결과 수합·git 커밋 |
| architect | 기획 | 스펙·설계·구현 계획, 기술 조사, 완료조건 판정·설계 이탈 승인 |
| uiux | UI/UX | UX·레퍼런스 조사, UI/UX 명세, 구현 화면 검수 |
| frontend | 프론트엔드 | 프론트엔드 구현·API 연동·반응형·브라우저 검증 |
| backend | 백엔드 | 백엔드 구현·API·DB·테스트·빌드 |
| reviewer | 리뷰어 | 코드 리뷰·QA·커버리지 판정 |

- 작업 흐름: (architect 계획) → uiux 명세 → frontend 구현 → uiux 화면 검수 → reviewer 리뷰 → lead 커밋
- UI/UX 설계가 필요 없으면 `team/members.conf`에서 uiux 제외

### 프로젝트별 설정

- 대상 프로젝트에 `team/members.conf`가 있으면 저장소 기본값 대신 그 파일만 사용
- 저장소의 [team/members.conf](team/members.conf)를 복사해 수정
- 역할 줄을 추가·삭제해 팀원 구성 조정 (예: 작은 수정은 lead·backend·reviewer 3인)
- 파싱 로직은 `lib/setup-common.sh`에 있어 로직 변경 시 재복사 불필요

```text
# /path/to/project/team/members.conf
# tmux 세션 이름
SESSION=team1
# 팀원 정의
lead|claude-sonnet-5-5|medium
architect|claude-sonnet-5-5|high
uiux|gpt-6.1-terra|medium
frontend|gpt-6.1-terra|medium
backend|claude-sonnet-5-5|medium
reviewer|gpt-6.1-sol|medium
```

- 형식: `role|model|effort`, 줄 순서 = 패널 배치 순서
- 필수: `SESSION`, `role`, `model` (비었거나 형식 오류 시 경고 후 중단)
- `model`: 전체 모델 ID, 접두사로 공급자 결정 (`claude-*` Claude, `gpt-*` Codex)
- `effort`: `low`·`medium`·`high`·`xhigh`·`max` 중 모델 지원 값. 비우면 CLI 기본값(테두리에 `effort 비어 있음` 표시)
- 설치 스크립트도 같은 구성을 읽어 필요한 CLI만 설치

### 지침과 스킬

| 설정 파일 | 적용 방식 |
| --- | --- |
| `CLAUDE.md`·`AGENTS.md` | 저장소의 공통 규칙을 대상 프로젝트의 같은 이름 파일에 마커 블록으로 병합 |
| `team/{역할}.md` | 프로젝트 파일을 우선 사용하고, 없으면 저장소 기본 지침 사용 |
| `team/config.claude.sh`·`team/config.codex.sh` | 역할별 스킬·플러그인 배분. 프로젝트 파일이 있으면 기본 배분표를 통째로 대체 |

- 역할 지침 전달: Claude는 `--append-system-prompt-file`, Codex는 `.team/{역할}/AGENTS.md` 생성
- 새 역할 추가 시 `team/{역할}.md` 작성, 배분표에 스킬 배정
- 상세: [스킬·플러그인 가이드](docs/guides/skill-allocation.md)

## 운영

### 세션 관리

```bash
tmux attach -t team1                          # 접속
tmux capture-pane -t team1:0.2 -p | tail -5    # 특정 패널 진행 확인
tmux kill-session -t team1                    # 종료
```

- `setup-team.sh` 재실행 시 같은 이름의 기존 세션을 종료하고 새로 구성

### 진단과 상태

저장소 루트에서 실행. 다른 프로젝트는 끝에 경로 추가.

```bash
./bin/team doctor            # 팀 구성·필수 도구·공급자 인증 점검 (실행 중이면 파인 상태 포함)
./bin/team status            # 역할별 모델·기동 상태·대기 메시지 수/지연·시작 훅 관측 여부
./bin/team status --watch    # 2초마다 갱신, Ctrl+C로 종료
./bin/team failures          # 전송 실패로 큐에서 빠진 메시지 목록
./bin/team retry <실패_ID>    # 실패 메시지 재제출
```

- 팀 파인 안에서는 `team`이 PATH에 등록됨
- 같은 실패 ID를 다시 `retry`하면 메시지가 중복 제출됨

### 패널 간 메시지

```bash
say lead "[backend] Implementation complete."
say :0.0 "[backend] Tests passed."
SAY_NOWAIT=1 say backend "Stop the current task."   # 작업 중단
./bin/say team1:0.0 "..."                          # 팀 밖 셸에서
```

- 상대가 작업 중이면 큐에 쌓였다가 유휴 시 전달
- 보고 규칙·장애 대응: [패널 메시징 가이드](docs/guides/pane-messaging.md)

### 로그

- 프롬프트·툴 사용 기록: 대상 프로젝트 `.team-logs/{역할}.jsonl` (Claude·Codex 공통 형식, 자체 `.gitignore`로 커밋 제외)
- 런타임 생성 파일(지침·스킬 링크 등): `.team/`

## 프로젝트 구조

```text
ai-setup/
├── setup-team.sh        # 팀 실행 진입점: tmux 세션·패널 구성, 지침·스킬 배치
├── bin/                 # 팀 패널 PATH에 등록되는 실행 파일
│   ├── team             # doctor·status·failures·retry
│   ├── say              # 패널 간 메시지 전송·큐
│   └── log-hook         # 프롬프트·툴 사용 로그 기록 훅
├── lib/                 # 설치·실행 스크립트 공용 모듈 (members.conf 파싱, 전송 실패 기록)
├── install/             # 환경별 의존성 설치 (wsl·mac·docker)
├── team/                # 기본 팀 구성·역할 지침·스킬 배분표
├── CLAUDE.md·AGENTS.md  # 대상 프로젝트에 병합되는 공통 규칙
├── Dockerfile
├── tests/
└── docs/                # 가이드·설계 계획·리뷰 판정
```

## 참고 문서

- [패널 메시징과 장애 대응](docs/guides/pane-messaging.md)
- [토큰 비용과 절감 근거](docs/guides/token-cost.md)
- [역할별 스킬·플러그인 배분](docs/guides/skill-allocation.md)
- [기능별 설계·구현 계획](docs/plans/)
- [설계 리뷰 판정](docs/architect-review/)
