param(
    [string]$Installer=(Join-Path $PSScriptRoot '..\release\Honakari-Free-Setup-v14.exe'),
    [string]$PreviousInstaller='',
    [ValidateSet('Free','Premium')][string]$Edition='Free',
    [switch]$ConfirmIsolatedTestMachine
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$ConfirmIsolatedTestMachine) { throw 'Run only on a disposable clean Windows VM/user, then pass -ConfirmIsolatedTestMachine.' }
if ($env:OS -ne 'Windows_NT') { throw 'Native Windows is required.' }
$readProductRegistry='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{27B59F6D-FDCB-44A8-91DB-9E6E64869BB8}_is1'
if ($Edition -eq 'Premium') { $readProductRegistry='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{C6C94F28-4924-4A04-9A3B-C1414A0E8E1B}_is1' }
if (Test-Path -LiteralPath $readProductRegistry) { throw 'A Read/PANDA Reads installation already exists. Use a clean Windows test account.' }
$readData=Join-Path $env:LOCALAPPDATA 'ReadApp'
if (Test-Path -LiteralPath $readData) { throw 'A reader library already exists. This test will not touch it; use a clean test account.' }
$readInstallerPath=(Resolve-Path -LiteralPath $Installer).Path
$readTestRoot=Join-Path ([IO.Path]::GetTempPath()) ('PANDA-Release-'+[guid]::NewGuid().ToString('N'))
$readInstall=Join-Path $readTestRoot 'Application'
New-Item -ItemType Directory -Path $readTestRoot,$readData | Out-Null
$readMarker=Join-Path $readData 'release-test-preserve.txt'
[IO.File]::WriteAllText($readMarker,'Disposable release test: keep library data through upgrade and uninstall.')
$readReports=Join-Path $PSScriptRoot '..\build\validation'
New-Item -ItemType Directory -Force -Path $readReports | Out-Null
function Run-Checked([string]$Executable,[string[]]$Arguments) {
    $p=Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru
    if (!$p.WaitForExit(60000)) { $p.Kill(); throw "Test timed out: $Executable" }
    if ($p.ExitCode -ne 0) {
        Get-ChildItem $readTestRoot -Filter '*.json' | ForEach-Object { Get-Content $_.FullName -Raw | Write-Host; Copy-Item $_.FullName (Join-Path $readReports ('installed-'+$_.Name)) -Force }
        Get-ChildItem $readTestRoot -Filter '*.log' | ForEach-Object { Copy-Item $_.FullName (Join-Path $readReports ('installed-'+$_.Name)) -Force }
        throw "Test failed ($($p.ExitCode)): $Executable" }
}
function Install-Test([string]$Path) {
    Run-Checked $Path @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOICONS',('/DIR="'+$readInstall+'"'))
}
function Installed-Uninstaller {
    $readCommand=Get-ItemPropertyValue -LiteralPath $readProductRegistry -Name 'UninstallString'
    if ($readCommand -match '^"([^"]+)"') { $readPath=$Matches[1] }
    elseif ($readCommand -match '^(.*?\.exe)(?:\s|$)') { $readPath=$Matches[1] }
    else { throw 'Installed uninstall command could not be read.' }
    if ((Split-Path -Parent $readPath) -ne $readInstall -or (Split-Path -Leaf $readPath) -notmatch '^unins\d+\.exe$' -or !(Test-Path -LiteralPath $readPath)) { throw 'Registered disposable-test uninstaller is missing or outside its application folder.' }
    return $readPath
}
function Check-InstalledTrial([string]$Phase,[bool]$Seed=$false) {
    $readTrialReport=Join-Path $readReports ('installed-trial-'+$Phase+'.json')
    $readTrialArgs=@('--release-trial-check','--report',('"'+$readTrialReport+'"'))
    if ($Seed) { $readTrialArgs+=@('--seed-expired-trial') }
    $readPreviousConsent=$env:READ_RELEASE_QA_CONSENT
    try {
        $env:READ_RELEASE_QA_CONSENT='disposable-machine'
        Run-Checked (Join-Path $readInstall 'PANDAReads.exe') $readTrialArgs
    } finally { $env:READ_RELEASE_QA_CONSENT=$readPreviousConsent }
    $readTrialResult=Get-Content -Raw -LiteralPath $readTrialReport | ConvertFrom-Json
    if (!$readTrialResult.ok -or !$readTrialResult.restart_blocked -or !$readTrialResult.original_expiry_preserved) { throw "Expired trial changed during $Phase" }
}
if ($PreviousInstaller) {
    Install-Test (Resolve-Path -LiteralPath $PreviousInstaller).Path
    Check-InstalledTrial 'previous-version' $true
}
Install-Test $readInstallerPath
Check-InstalledTrial 'first-install-or-upgrade' (!$PreviousInstaller)
$readExe=Join-Path $readInstall 'PANDAReads.exe'
if (!(Test-Path -LiteralPath $readExe)) { throw 'Installed executable is missing.' }
foreach ($check in @('--self-test','--smoke-test','--native-qa')) {
    $readReport=Join-Path $readReports ($check.TrimStart('-')+'.json')
    # The installed app must run without Python/venv on PATH or Python env vars.
    $readOriginalPath=$env:PATH
    $readOriginalPythonHome=$env:PYTHONHOME
    $readOriginalPythonPath=$env:PYTHONPATH
    try {
        $env:PATH="$env:SystemRoot\System32;$env:SystemRoot"
        Remove-Item Env:PYTHONHOME,Env:PYTHONPATH -ErrorAction SilentlyContinue
        Run-Checked $readExe @($check,'--report',('"'+$readReport+'"'))
    } finally {
        $env:PATH=$readOriginalPath
        $env:PYTHONHOME=$readOriginalPythonHome
        $env:PYTHONPATH=$readOriginalPythonPath
    }
    if (!(Get-Content -Raw -LiteralPath $readReport | ConvertFrom-Json).ok) { throw "Installed app failed $check" }
}
# A same-version reinstall is tested separately from a genuine prior-version upgrade.
Install-Test $readInstallerPath
Check-InstalledTrial 'same-version-reinstall'
if (!(Test-Path -LiteralPath $readMarker)) { throw 'Reinstall/upgrade removed library data.' }
$readUninstaller=Installed-Uninstaller
if (!(Test-Path -LiteralPath $readUninstaller)) { throw 'Uninstaller was not created.' }
Run-Checked $readUninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
if (Test-Path -LiteralPath $readExe) { throw 'Uninstall left the application executable.' }
if (!(Test-Path -LiteralPath $readMarker)) { throw 'Uninstall removed library data.' }
if (!(Test-Path -LiteralPath (Join-Path $readData 'trial.json')) -or !(Test-Path -LiteralPath (Join-Path $readData '.trial-key.json'))) { throw 'Uninstall removed the used-trial record.' }
# Start from an uninstalled app, reinstall the actual package, and exercise its
# frozen trial implementation. Uninstall again to leave the normal final state.
Install-Test $readInstallerPath
Check-InstalledTrial 'after-uninstall-and-reinstall'
Run-Checked (Installed-Uninstaller) @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
if (Test-Path -LiteralPath $readExe) { throw 'Final uninstall left the application executable.' }
$readResult=[ordered]@{edition=$Edition;install=$true;native_smoke=$true;python_removed_from_path=$true;reinstall=$true;prior_version_upgrade=[bool]$PreviousInstaller;uninstall=$true;library_preserved=$true;expired_trial_after_uninstall_reinstall_blocked=$true;original_trial_expiry_preserved=$true;test_root=$readTestRoot}
$readReports=Join-Path $PSScriptRoot '..\build\validation'
New-Item -ItemType Directory -Force -Path $readReports | Out-Null
$readResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $readReports 'release-lifecycle.json')
Write-Host "Passed. Test reports and disposable data were left for inspection at $readTestRoot and $readData."
if (!$PreviousInstaller) { Write-Warning 'A real prior-version upgrade was NOT tested; supply -PreviousInstaller for that gate.' }

