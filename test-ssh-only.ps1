Write-Host "🔍 MINIMAL SSH TEST"

# Test basic SSH functionality without git
if ($Env:DRONE_SSH_KEY) {
    Write-Host "🔑 SSH Key provided - Setting up basic test"
    
    # Create SSH key
    $sshDir = Join-Path $Env:USERPROFILE '.ssh'
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    $keyPath = Join-Path $sshDir 'id_rsa'
    
    # Write SSH key (simple approach)
    $Env:DRONE_SSH_KEY | Out-File -FilePath $keyPath -Encoding ascii
    Write-Host "✅ SSH key written to: $keyPath"
    
    # Try to find SSH
    $sshExe = $null
    if (Test-Path 'C:\Windows\System32\OpenSSH\ssh.exe') {
        $sshExe = 'C:\Windows\System32\OpenSSH\ssh.exe'
        Write-Host "✅ Using Windows OpenSSH: $sshExe"
    } elseif (Test-Path 'C:\openssh\ssh.exe') {
        $sshExe = 'C:\openssh\ssh.exe'
        Write-Host "✅ Using Portable OpenSSH: $sshExe"
    } else {
        try {
            $pathSsh = Get-Command ssh -ErrorAction SilentlyContinue
            if ($pathSsh) {
                $sshExe = $pathSsh.Source
                Write-Host "✅ Using SSH from PATH: $sshExe"
            }
        } catch {
            Write-Host "❌ No SSH client found anywhere!"
            exit 1
        }
    }
    
    if ($sshExe) {
        Write-Host "🧪 Testing SSH connection directly..."
        
        # Extract hostname from DRONE_REMOTE_URL
        if ($Env:DRONE_REMOTE_URL -match 'git@([^:]+):') {
            $hostname = $matches[1]
            Write-Host "🌐 Testing SSH to: $hostname"
            
            # Test SSH connection
            $cmd = "$sshExe -i `"$keyPath`" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -T git@$hostname"
            Write-Host "🔍 Running: $cmd"
            
            try {
                $result = Invoke-Expression $cmd 2>&1
                Write-Host "📡 SSH Result: $result"
                Write-Host "✅ SSH test completed"
            } catch {
                Write-Host "❌ SSH test failed: $_"
            }
        } else {
            Write-Host "⚠️  Could not extract hostname from DRONE_REMOTE_URL: $($Env:DRONE_REMOTE_URL)"
        }
    }
} else {
    Write-Host "❌ No SSH key provided - cannot test SSH"
}

Write-Host "🎯 MINIMAL SSH TEST COMPLETED"