param(
    [string]$Message = "chore: update code for iPadOS build"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

git add -A
$status = git status --porcelain
if ($status) {
    git commit -m $Message
    git push
} else {
    Write-Host "Khong co thay doi moi, kiem tra build cho commit hien tai..."
}

$sha = (git rev-parse HEAD).Trim()
Write-Host "Dang cho GitHub Actions khoi tao cho commit $sha..."

$runId = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 3
    $runs = gh run list --branch main --limit 5 --json databaseId,headSha | ConvertFrom-Json
    $match = $runs | Where-Object { $_.headSha -eq $sha } | Select-Object -First 1
    if ($match) {
        $runId = $match.databaseId
        break
    }
}

if (-not $runId) {
    Write-Error "Khong tim thay workflow run cho commit $sha sau 90 giay."
    exit 1
}

Write-Host "Da tim thay Run ID: $runId. Dang theo doi Xcode build..."
$elapsed = 0
$conclusion = $null
while ($true) {
    $info = gh run view $runId --json status,conclusion | ConvertFrom-Json
    if ($info.status -eq "completed") {
        $conclusion = $info.conclusion
        break
    }
    Write-Host "[${elapsed}s] Trang thai: $($info.status)..."
    Start-Sleep -Seconds 10
    $elapsed += 10
}

if ($conclusion -eq "success") {
    Write-Host "BUILD THANH CONG! Dang tai MyArtAgent.ipa ve thu muc dist/..."
    New-Item -ItemType Directory -Force -Path "dist" | Out-Null
    Remove-Item -Path "dist\*" -Recurse -Force -ErrorAction SilentlyContinue
    gh run download $runId -n MyArtAgent-IPA -D dist
    Write-Host "HOAN TAT! File IPA da san sang tai: dist\MyArtAgent.ipa"
    exit 0
} else {
    Write-Host "BUILD THAT BAI ($conclusion)! Dang tai va loc log loi..."
    $ErrorActionPreference = "Continue"
    $rawLog = gh run view $runId --log-failed 2>&1
    $rawLog | Out-File -FilePath "last_build_error.log" -Encoding utf8

    Write-Host "=== TOM TAT LOI BIEN DICH ==="
    $errors = $rawLog | Select-String -Pattern "error:|fatal error:|\*\* BUILD FAILED \*\*|The following build commands failed" -Context 1,2
    if ($errors) {
        $errors | Select-Object -First 40 | Out-String | Write-Host
    } else {
        $rawLog | Select-Object -Last 60 | Out-String | Write-Host
    }
    Write-Host "=== Log day du da luu tai last_build_error.log ==="
    exit 1
}