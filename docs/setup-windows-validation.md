# Windows 설치·팀 기동 검증 기록

`setup-windows.ps1` → `wsl.exe` → `setup-wsl.sh` → `setup-team.sh` 경로를 실제 Windows(PowerShell 5.1)와 WSL2(Ubuntu)에서 확인한 결과다.
원본 로그는 `/tmp/ai-setup-windows-real-test/`에 있다(임시 위치라 보존되지 않을 수 있음). 신규 설치용 임시 HOME(약 1.1GB)은 검증 후 삭제했고 `fresh-install.log`만 남아 있다. 시험용 tmux 서버는 종료했다.

## 범위 구분

- **CLI 설치**: claude·codex·rtk·bun·tmux는 WSL 배포판(Linux) 안에만 설치한다. Windows용 네이티브 CLI는 설치도 사용도 하지 않는다.
- **팀 실행**: tmux와 Bash 4+가 필요하므로 `setup-team.sh`와 `tmux attach`는 WSL에서 실행한다. 네이티브 PowerShell/cmd, Git Bash, MSYS2, Cygwin은 지원하지 않는다.

## 발견하고 고친 문제

| 문제 | 원인 | 수정 |
| --- | --- | --- |
| UNC 경로 변환 실패 (`\\wsl.localhostUbuntu...`) | `wsl.exe wslpath`가 기본 셸을 거쳐 역슬래시가 사라짐 | `wsl.exe -e wslpath -a` |
| 한글·공백 경로 깨짐 | PS 5.1이 `wsl.exe` 출력을 기본 인코딩으로 해석 | 콘솔·`$OutputEncoding`을 UTF-8로 두고 종료 시 복원 |
| `-Project` 생략 시 저장소가 프로젝트가 됨 | 현재 폴더를 넘기지 않음 | `(Get-Location).ProviderPath`를 기본값으로 전달 |
| WSL 실패 종료 코드가 1로 바뀜 | `bash -l`이 읽는 `~/.bash_logout`(`clear_console`)이 종료 코드를 덮어씀 | 로그인 셸을 쓰지 않고 `bash ./setup-wsl.sh` |
| Windows용 npm 선택, NVM의 codex 미발견 | 비로그인 셸 PATH에 `/mnt/c/...`가 있고 NVM 경로는 없음 | `setup_prepare_linux_path`: `/mnt/*` 제거, 최신 NVM·`~/.local/bin`·`~/.bun/bin`을 앞에 둠 |

## 통과한 검증

| 항목 | 내용 | 근거 |
| --- | --- | --- |
| 셸 테스트 | `tests/*_test.sh` 7개 | 로컬 실행 |
| 래퍼 실제 호출 | PS 5.1 → WSL → Bash 7개 시나리오: 명시 프로젝트, 끝 역슬래시, 현재 폴더 기본값, 에이전트 기본값, 잘못된 에이전트, 없는 프로젝트, 실패 코드 전달. 공백·한글·작은따옴표·대괄호 경로 | `/tmp/ai-setup-windows-interop-test.py` |
| 기존 환경 의존성 확인 | 프로젝트 `실제 프로젝트 [1]`에서 `setup-wsl.sh`가 설치된 도구를 재설치 없이 확인 (claude, rtk, bun, codex, 혼합 팀) | `actual-setup.log` |
| 임시 HOME 신규 설치 | 빈 HOME에서 claude(npm)·codex(npm)·rtk·bun 설치. 모두 임시 HOME 아래 경로로 선택됨(호스트 도구 아님) | `fresh-install.log` |
| CLI 모델 응답 | Windows PowerShell → WSL에서 Claude `-p`(모델 `claude-opus-5-5`)가 정확히 `WINDOWS_CLAUDE_OK`, Codex `exec`(모델 `gpt-6.1-sol`)가 정확히 `WINDOWS_CODEX_OK`를 반환, 둘 다 종료 코드 0, 요청하지 않은 도구 사용·파일 변경 없음 | 테스트 루트의 `claude-response.json`, `codex-response.txt` |
| 키 수정 후 전체 재기동 | 기본 4파인 팀을 Windows에서 다시 기동해 종료 코드 0. 경고 0건이고 `lead: superpowers:finishing-a-development-branch`, `architect: superpowers:writing-plans`가 링크됨(`SKILL.md` 확인). 수정 전 경고 로그는 `team-start-before-skill-fix.log`로 보존 | `team-start.log`, `pane-status.txt` |
| 4파인 팀 기동 | 한글·공백·`[1]` 경로에서 `setup-team.sh` 실행, lead·architect·reviewer(Claude)와 developer(Codex) 4파인 기동, 두 공급자 로그인 확인 | `team-start.log`, `pane-status.txt`, `pane-*.txt` |

## 검증하지 못한 항목

- **새 OS 이미지**: 새로 설치한 WSL 배포판 첫 실행은 하지 않았다. 신규 설치 검증은 기존 배포판에서 HOME만 비운 것이다.
- **apt 경로**: tmux·git·curl·unzip·python3·locales 설치, `locale-gen`, nodesource 기반 Node 설치는 실행하지 못했다(필요 도구가 이미 설치돼 있었다). `sudo` 비밀번호 요구와 네트워크 실패 처리도 확인하지 않았다.
- **로그인 셸 환경**: `bash -l`을 쓰지 않으므로 `~/.profile`·`~/.bashrc`로만 잡히는 PATH(NVM 외 도구)는 보이지 않을 수 있다. NVM, `~/.local/bin`, `~/.bun/bin`만 직접 보강한다.
- **`/mnt` 필터**: `/mnt/*` 아래에 둔 Linux 도구도 가린다.
- **PowerShell 7**: 검증하지 않았다. PS 5.1 구문 검사는 WSL에서 `powershell.exe`를 호출하는 브리지로 실행했다. 셸 테스트의 `pwsh` 구문 검사는 이 환경에 `pwsh`가 없어 실행되지 않는다.
- **Codex 경고**: 신규 설치 검증에서 `codex --version`이 `/tmp` 아래 임시 HOME 때문에 PATH 별칭을 만들지 못했다는 경고를 냈다. 버전 출력은 정상이었다.
- **macOS**: 실제 Mac에서는 실행하지 않았다.
- **superpowers 스킬 경고(원인 규명·수정)**: 팀 기동 로그의 `finishing-a-development-branch`, `writing-plans` 경고 2건은 설정 키 불일치였다. 현재 Claude CLI는 superpowers를 내장 마켓플레이스로 `superpowers@anthropic-plugin-directory`(설치 명세 `installed_plugins.json`) 아래에 등록하는데, `team/config.claude.sh`는 `superpowers@claude-plugins-official`을 찾았다. 후자는 설치 명세에 없고 캐시(6.4.1, 7.0.0)는 둘 다 `.orphaned_at` 표시가 있다. 그래서 `claude_plugin_dir`가 실패해 스킬 루트가 비었고 매 실행마다 "새로 설치됨"과 스킬 없음 경고가 함께 나왔다. 설정 키를 `superpowers@anthropic-plugin-directory`로 바꿨다. `claude_plugin_dir`가 새 키로 설치 경로를 찾고 4개 스킬(`finishing-a-development-branch`, `writing-plans`, `systematic-debugging`, `receiving-code-review`)의 `SKILL.md`가 있음을 확인했다. 이후 실제 Windows에서 전체 재기동으로 경고가 사라진 것을 확인했다(위 표). 새 머신에서 내장 마켓플레이스 설치가 되는지는 시험하지 않았다.
- **파인 UI 대화**: 모델 응답은 CLI(`-p`/`exec`)로만 확인했다. tmux 파인 안에서 사람이 대화하는 흐름은 시험하지 않았다. 파인은 기동과 로그인 확인까지만 확인했다.
