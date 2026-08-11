# CLAUDE.md

## 팀 구성

- `setup-team.sh`가 tmux 세션 하나에 파인 여러 개를 띄우고 각각 다른 모델로 `claude` 실행
- 각 파인의 지침 = `team/{역할}.md` (프로젝트 루트에 있으면 그쪽 우선) + 작업 경로 안내
  - 조립 결과는 `.team/_runtime/{역할}.prompt.md`에 남음 — 자기 지침이 의심스러우면 그 파일을 읽는다
- **각 파인의 cwd는 프로젝트 루트가 아니라 `.team/{역할}/`** — 파일·git 작업은 시스템 프롬프트가 알려주는 실제 프로젝트 루트 기준
- 인원 구성·통신 규약·스킬 배정 근거는 [README.md](README.md), 역할별 통신 규칙은 `team/lead.md` 참조

## 팀 밖 세션과의 통신

- 파인끼리는 `say`로만 소통한다.
- 팀 밖 일반 세션(나)에서도 `/list-agents`로 파인을 찾아 `SendMessage`로 지시하는 것이 가능은 하다 — 실제로는 lead 파인(:0.0)에 직접 붙어 명령을 실행하는 경우가 대부분
- 컨테이너로 띄운 경우(`setup-docker.sh`) 이 경로는 컨테이너 안에서만 유효 (호스트 세션과 상호 비가시)
- 상세는 README.md의 "팀 밖 세션에서 파인 호출" 참조

## 프롬프트·툴 로깅

- 훅이 `$PROJECT_DIR/.claude-logs/{역할}.jsonl`에 자동 기록, 원인 추적 시 읽으면 된다 (커밋 대상 아님, 상세는 README)

## rtk

- `git status`·`ls`·`cat` 등은 훅이 `rtk git status` 형태로 재작성 → 직접 `rtk`를 붙이지 않는다 (메타 커맨드는 전역 RTK.md 참조)
