param(
  [string]$Executable = ".\nimtop.exe"
)

$ErrorActionPreference = 'Stop'
$shellPid = [uint32]$PID
$processName = (Get-Process -Id $shellPid).ProcessName

$output = & $Executable -d -p $shellPid -n $processName -s ID
if ($LASTEXITCODE -ne 0) {
  throw "nimtop -d returned exit code $LASTEXITCODE"
}

$table = $output -join [Environment]::NewLine
$header = "     ID       USER  PRI   CPU%          MEM  THRD       DISK         TIME  PROCESS"
if (-not $table.StartsWith($header)) {
  throw "nimtop -d did not print the expected process table header"
}
if ($table -notmatch "(?m)\b$([regex]::Escape($shellPid.ToString()))\b") {
  throw "The PID-filtered process table did not contain the PowerShell process"
}
if ($table -notmatch [regex]::Escape($processName)) {
  throw "The name-filtered process table did not contain the PowerShell process"
}
