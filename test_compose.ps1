$ErrorActionPreference = 'Stop'

$path = "docker-compose.yaml"
if (!(Test-Path -Path $path)) {
    Write-Error "File not found: $path"
    exit 1
}

$content = Get-Content -Raw -Path $path

$patterns = @(
    "version:\s*['\"]?3\.9['\"]?",
    "(?m)^\s*services:\s*$",
    "(?m)^\s*nginx-proxy:\s*$",
    "(?m)^\s*image:\s*jwilder/nginx-proxy\s*$",
    "(?m)^\s*ports:\s*$",
    "443:443",
    "80:80",
    "(?m)^\s*portainer:\s*$",
    "(?m)^\s*image:\s*portainer/portainer-ce:latest\s*$",
    "9000:9000",
    "(?m)^\s*volumes:\s*$",
    "(?m)^\s*portainer_data:\s*$",
    "(?m)^\s*networks:\s*$",
    "(?m)^\s*bme_network:\s*$",
    "(?m)^\s*external:\s*true\s*$"
)

$fail = $false
foreach ($p in $patterns) {
    if ($content -notmatch $p) {
        Write-Host "Missing pattern: $p" -ForegroundColor Red
        $fail = $true
    }
}

if ($fail) {
    Write-Error "docker-compose.yaml does not meet expected structure"
    exit 1
}
else {
    Write-Host "docker-compose.yaml structure validated." -ForegroundColor Green
    exit 0
}
