Write-Host "🔍 SSH DEBUG TEST STARTING"
Write-Host "🖥️  DEBUG: PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "👤 DEBUG: Current User: $([System.Environment]::UserName)"
Write-Host "📁 DEBUG: Working Directory: $(Get-Location)"

# Test environment variables
Write-Host "🔧 DEBUG: Environment Variables:"
@('DRONE_SSH_KEY', 'DRONE_REMOTE_URL', 'DRONE_DEBUG') | ForEach-Object {
    $value = [System.Environment]::GetEnvironmentVariable($_)
    if ($value) {
        if ($_ -eq 'DRONE_SSH_KEY') {
            Write-Host "🔐 DEBUG: $_ = [PROVIDED - Length: $($value.Length)]"
        } else {
            Write-Host "🔧 DEBUG: $_ = $value"
        }
    } else {
        Write-Host "❌ DEBUG: $_ = [NOT SET]"
    }
}

# Test SSH client availability
Write-Host "🔍 DEBUG: Testing SSH client availability"
$sshPaths = @('C:\openssh\ssh.exe', 'C:\Windows\System32\OpenSSH\ssh.exe')
$sshFound = $false

foreach ($path in $sshPaths) {
    Write-Host "🔍 DEBUG: Checking: $path"
    if (Test-Path $path) {
        Write-Host "✅ DEBUG: Found SSH client at: $path"
        try {
            $sshVersion = & $path -V 2>&1
            Write-Host "📋 DEBUG: SSH version: $sshVersion"
            $sshFound = $true
        } catch {
            Write-Host "⚠️  DEBUG: Could not get SSH version: $_"
        }
        break
    } else {
        Write-Host "❌ DEBUG: SSH client not found at: $path"
    }
}

if (-not $sshFound) {
    Write-Host "🚨 DEBUG: No SSH client found in expected locations!"
    Write-Host "🔍 DEBUG: Checking PATH..."
    try {
        $pathSsh = Get-Command ssh -ErrorAction SilentlyContinue
        if ($pathSsh) {
            Write-Host "✅ DEBUG: Found SSH in PATH: $($pathSsh.Source)"
            $sshVersion = & ssh -V 2>&1
            Write-Host "📋 DEBUG: SSH version: $sshVersion"
            $sshFound = $true
        } else {
            Write-Host "❌ DEBUG: SSH not found in PATH either"
        }
    } catch {
        Write-Host "❌ DEBUG: SSH search failed: $_"
    }
}

# Test Git availability
Write-Host "🔍 DEBUG: Testing Git availability"
try {
    $gitVersion = & git --version 2>&1
    Write-Host "✅ DEBUG: Git version: $gitVersion"
} catch {
    Write-Host "❌ DEBUG: Git not found: $_"
}

# Check current PATH
Write-Host "🔧 DEBUG: Current PATH: $($Env:PATH)"

Write-Host "🎯 SSH DEBUG TEST COMPLETED"