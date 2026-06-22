param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptPath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs
)

$ErrorActionPreference = "Stop"

# PowerShell과 Python 사이에서 한글 파일명·시트명이 깨지지 않도록 콘솔 입출력을 UTF-8로 고정한다.
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Python 내부 기본 인코딩과 표준 입출력을 UTF-8로 고정한다.
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

# Codex 번들 Python을 우선 사용한다. 없으면 시스템 Python으로 후퇴한다.
$bundledPython = "C:\Users\shfmq\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if (Test-Path -LiteralPath $bundledPython) {
    $python = $bundledPython
}
else {
    $python = "python"
}

& $python $ScriptPath @ScriptArgs
exit $LASTEXITCODE
