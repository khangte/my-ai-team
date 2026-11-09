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

팀에서 사용하는 공급자의 로그인이 필요합니다. 실행 시 인증 상태를 확인하며,
미로그인 상태라면 Claude는 `/login`, Codex는 `codex login`을 안내합니다.
프로젝트 경로를 생략하면 `$PROJECT_DIR`, 없으면 현재 디렉터리를 사용합니다.

### 다른 환경에서 실행

**macOS** — Homebrew를 먼저 설치하고, 기본 bash 3.2 대신 Homebrew bash로 실행합니다.

```bash
./install/mac.sh /path/to/project
"$(brew --prefix)/bin/bash" ./setup-team.sh /path/to/project
```

**Windows** — WSL2 배포판이 필요합니다. PowerShell에서 의존성을 설치합니다.

```powershell
.\install\windows.ps1 -Project C:\path\to\project
```

Git Bash에서는 `bash ./install/windows.sh /c/path/to/project`로 설치할 수 있습니다.
설치 후 팀 실행과 `tmux attach`는 WSL 터미널에서 합니다.
프로젝트는 WSL 홈(`~/`) 아래 두는 편이 `/mnt/c`보다 빠릅니다.

**Docker** — Docker가 설치된 환경에서 이미지 빌드부터 팀 실행까지 진행합니다.

```bash
./install/docker.sh /path/to/project
docker exec -it claude-env-<프로젝트이름>-<경로체크섬> bash -lc "tmux attach -t team1"
```

기본 실행은 Claude의 `--dangerously-skip-permissions`와 Codex의
`--dangerously-bypass-approvals-and-sandbox`를 사용합니다.
파일 수정·삭제에 별도 승인을 받지 않으므로 git으로 관리하는 프로젝트나 격리 환경에서 사용하세요.
Codex를 `workspace-write`로 제한하려면 `CODEX_FULL_ACCESS=0`으로 실행합니다.
이 경우 `.git` 쓰기가 제한되어 `git add`·`git commit`을 할 수 없습니다.

## 팀 구성

현재 기본 팀은 **lead·architect·frontend·backend·reviewer 5인**이며, frontend는 Codex,
나머지는 Claude를 사용합니다. UI/UX 설계가 필요하면 uiux를 추가합니다.
독립 researcher 역할은 두지 않고 기술 조사는 architect, UX·레퍼런스 조사는 uiux,
구현용 API·라이브러리 조사는 frontend·backend가 담당합니다.

| 역할 | 한글 표시 이름 | 담당 |
| --- | --- | --- |
| lead | 팀장 | 작업 배분·결과 수합·git 커밋 |
| architect | 설계 | 기획·설계 — 스펙·설계·구현 계획, 완료조건 판정·설계 이탈 승인 |
| uiux (선택) | UI/UX | UX·레퍼런스 조사, UI/UX 명세, 구현 화면 검수 |
| frontend | 프론트엔드 | 프론트엔드 구현·API 연동·반응형·브라우저 검증 |
| backend | 백엔드 | 백엔드 구현·API·DB·테스트·빌드 |
| reviewer | 리뷰어 | 코드 리뷰·QA·커버리지 판정 |

화면 작업은 `architect → uiux 명세 → frontend 구현 → uiux 화면 검수`로 진행합니다.
코드 품질은 reviewer가 별도로 검증합니다. uiux가 없는 경우 frontend는 기존 디자인 기준 안에서
사소한 수정을 처리하고, 새 사용자 흐름·디자인 기준이 필요하면 uiux 활성화를 요청합니다.

### 프로젝트별 설정

대상 프로젝트의 `team/config.sh`로 기본 구성을 덮어씁니다.
저장소의 [team/config.sh](team/config.sh)를 복사해 수정할 수 있습니다.

```bash
# /path/to/project/team/config.sh
SESSION="team1"
declare -a MEMBERS=(
    "lead|팀장|claude-sonnet-5-5|medium"
    "architect|설계|claude-sonnet-5-5|high"
    "uiux|UI/UX|gpt-6.1-terra|medium"
    "frontend|프론트엔드|gpt-6.1-terra|medium"
    "backend|백엔드|claude-sonnet-5-5|medium"
    "reviewer|리뷰어|gpt-6.1-sol|medium"
)
```

항목 형식은 `role|표시이름|model|effort`이며, 배열 순서대로 패널이 배치됩니다.
네 필드와 `SESSION`은 모두 필수이고, 비어 있거나 형식이 틀리면 경고를 출력하고 실행을 멈춥니다.
역할을 추가하거나 제거해 인원을 조절합니다.

- `model`: 전체 모델 ID를 씁니다. 접두사로 공급자를 정합니다(`claude-*`는 Claude, `gpt-*`는 Codex).
- `effort`: `low`·`medium`·`high`·`xhigh`·`max` 중 모델이 지원하는 값을 지정합니다.

팀 전체를 Codex로 실행하려면 각 역할의 `model`을 `gpt-*`로 지정하세요.
설치 스크립트도 같은 팀 구성을 읽어 필요한 공급자의 CLI를 설치합니다.

### 지침과 스킬

| 설정 파일 | 적용 방식 |
| --- | --- |
| `CLAUDE.md`·`AGENTS.md` | 저장소의 공통 규칙을 대상 프로젝트의 같은 이름 파일에 마커 블록으로 병합 |
| `team/{역할}.md` | 프로젝트 파일을 우선 사용하고, 없으면 저장소 기본 지침 사용 |
| `team/config.claude.sh`·`team/config.codex.sh` | 역할별 스킬·플러그인 배분. 프로젝트 파일이 있으면 기본 배분표를 통째로 대체 |

역할 지침은 Claude에 `--append-system-prompt`로 전달하고, Codex에는
`.team/{역할}/AGENTS.md`로 생성합니다. 새 역할을 만들 때는 대응하는 지침 파일도 추가하세요.
공급자별 배분표를 재정의할 때는 필요한 배열을 모두 선언해야 합니다.
상세 배분은 [스킬·플러그인 가이드](docs/guides/skill-allocation.md)를 참고하세요.

## 운영

### 세션 관리

```bash
tmux attach -t team1                          # 접속
tmux capture-pane -t team1:0.2 -p | tail -5    # 특정 패널 진행 확인
tmux kill-session -t team1                    # 종료
```

세션 이름은 `SESSION`으로 바꿉니다. `setup-team.sh`를 다시 실행하면
같은 이름의 기존 세션을 종료하고 팀을 새로 구성합니다.

### 패널 간 메시지

각 패널에서는 PATH에 등록된 `say`로 역할이나 패널 번호를 지정해 메시지를 보냅니다.
메시지 본문은 영어로 간결하게 작성합니다.

```bash
say lead "[backend] Implementation complete."
say :0.0 "[backend] Tests passed."
```

상대가 작업 중이면 메시지는 큐에 쌓였다가 유휴 시 전달됩니다.
작업 중단이 필요할 때는 `SAY_NOWAIT=1 say backend "Stop the current task."`를 사용합니다.
팀 밖 셸에서는 저장소의 `./bin/say team1:0.0 "..."`처럼 세션명까지 지정합니다.

- 일반 작업은 lead에 완료 보고합니다.
- phase 계획에 따른 구현은 architect가 완료조건을 대조한 뒤 lead에 보고합니다.
- 코드 품질 수정요청은 작성자에게, 설계 판단은 architect에게 직접 전달합니다.
- 다음 담당자에게 넘긴 중간 상태는 lead에 중복 보고하지 않고, 사안이 종결되면 최종 결과만 보고합니다.

메시징과 보고 누락 방지 훅의 동작은 [패널 메시징 가이드](docs/guides/pane-messaging.md)에 정리되어 있습니다.

### 로그 확인

프롬프트와 툴 사용 기록은 대상 프로젝트의 `.team-logs/{역할}.jsonl`에 자동 저장됩니다.
Claude·Codex 모두 같은 위치와 형식을 사용하며, 로그 디렉터리는 자체 `.gitignore`로 커밋에서 제외됩니다.
런타임 지침·스킬 링크 등 실행 중 생성되는 파일은 `.team/`에 있습니다.

## 참고 문서

- [패널 메시징과 장애 대응](docs/guides/pane-messaging.md)
- [토큰 비용과 절감 근거](docs/guides/token-cost.md)
- [역할별 스킬·플러그인 배분](docs/guides/skill-allocation.md)
- [기능별 설계·구현 계획](docs/plans/)
- [설계 리뷰 판정](docs/architect-review/)
