# Windows에서 WSL2 안의 setup-wsl.sh를 호출하는 진입 스크립트.
# 사용: .\setup-windows.ps1 [-Agent claude|codex] [-Project <경로>]
#
# 범위 구분:
#   - CLI 설치: claude/codex/rtk/tmux는 WSL 배포판(Linux) 안에만 설치한다. Windows용
#     claude.exe·codex.exe 등 네이티브 CLI는 설치하지도 사용하지도 않는다.
#   - 팀 실행: tmux와 Bash 4+에 의존하는데 tmux는 네이티브 Windows(PowerShell/cmd)에서
#     동작하지 않는다. Git Bash는 setup-windows.sh로 설치를 시작한다. setup-team.sh와
#     tmux attach는 WSL 터미널에서 실행한다.
param(
    [ValidateSet('claude', 'codex')][string]$Agent,
    [string]$Project
)

$ErrorActionPreference = 'Stop'

# wsl.exe 출력(wslpath 결과, 한글·공백 경로 포함)을 UTF-8로 해석한다. 종료 시 원래 인코딩으로 되돌린다.
$prevConsoleEncoding = [Console]::OutputEncoding
$prevOutputEncoding = $OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Stop-Setup([string]$Message) {
    # 실패 사유를 출력하고 종료한다.
    [Console]::Error.WriteLine($Message)
    exit 1
}

function ConvertTo-WslPath([string]$WindowsPath) {
    # Windows 경로를 WSL 경로로 바꾼다. 끝의 \는 인용을 깨므로 떼고, 변환 실패는 한국어 오류로 종료한다.
    $p = $WindowsPath
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\') }
    $out = @(& wsl.exe -e wslpath -a $p 2>$null)
    if ($LASTEXITCODE -ne 0 -or $out.Count -eq 0 -or -not ([string]$out[0]).Trim()) {
        Stop-Setup "WSL 경로로 변환하지 못했습니다: $WindowsPath"
    }
    ([string]$out[0]).Trim()
}

try {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Stop-Setup 'wsl.exe가 없습니다. 관리자 PowerShell에서 "wsl --install" 후 재부팅하고 다시 실행하세요. (tmux는 네이티브 Windows에서 동작하지 않아 WSL2가 필요합니다)'
    }
    & wsl.exe -e bash -c 'exit 0' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Stop-Setup 'bash가 동작하는 WSL 배포판이 없습니다. "wsl --install -d Ubuntu"로 배포판을 설치한 뒤 다시 실행하세요.'
    }

    $repo = ConvertTo-WslPath $PSScriptRoot
    # 로그인 셸(bash -l)은 쓰지 않는다: 일부 배포판의 ~/.bash_logout이 종료 코드를 덮어쓴다.
    # 셸 문자열을 조립하지 않고 인자 배열로 넘겨 공백·따옴표 경로를 그대로 보존한다.
    $setupArgs = @()
    if ($Agent) { $setupArgs += '--agent', $Agent }
    # -Project를 생략하면 호출한 현재 폴더를 프로젝트로 넘긴다(생략하면 WSL에서 저장소가 프로젝트가 된다).
    if (-not $Project) { $Project = (Get-Location).ProviderPath }
    if (-not (Test-Path -LiteralPath $Project)) { Stop-Setup "프로젝트 경로가 없습니다: $Project" }
    $setupArgs += (ConvertTo-WslPath (Resolve-Path -LiteralPath $Project).ProviderPath)

    Write-Host "WSL에서 실행: cd $repo && ./setup-wsl.sh $($setupArgs -join ' ')"
    & wsl.exe --cd $repo -e bash ./setup-wsl.sh @setupArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host '완료. 팀 실행(setup-team.sh, tmux attach)은 WSL 터미널에서 하세요. README의 "Windows" 참고.'
} finally {
    [Console]::OutputEncoding = $prevConsoleEncoding
    $OutputEncoding = $prevOutputEncoding
}
