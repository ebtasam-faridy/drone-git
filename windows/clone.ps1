$ErrorActionPreference = 'Stop';

# Debug output enabled by default (for troubleshooting)
$DebugMode = $true  # Always enabled for troubleshooting

function Write-Debug {
    param([string]$Message)
    if ($DebugMode) {
        Write-Host $Message
    }
}

# Debug: Show environment information
Write-Host "🐛 DEBUG: Drone Git Clone Script Starting (Debug Mode Enabled)"
Write-Debug "🖥️  DEBUG: PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Debug "🖥️  DEBUG: OS Version: $([System.Environment]::OSVersion)"
Write-Debug "👤 DEBUG: Current User: $([System.Environment]::UserName)"
Write-Debug "📁 DEBUG: Working Directory: $(Get-Location)"
Write-Debug "📁 DEBUG: User Profile: $($Env:USERPROFILE)"

# Debug: Show Drone environment variables
Write-Debug "🔧 DEBUG: Key Drone Environment Variables:"
@('DRONE_WORKSPACE', 'DRONE_REMOTE_URL', 'DRONE_BUILD_EVENT', 'DRONE_COMMIT_SHA', 'DRONE_COMMIT_REF', 'DRONE_COMMIT_BRANCH') | ForEach-Object {
    $value = [System.Environment]::GetEnvironmentVariable($_)
    if ($value) {
        if ($_ -eq 'DRONE_SSH_KEY') {
            Write-Debug "🔐 DEBUG: $_ = [REDACTED - Length: $($value.Length)]"
        } else {
            Write-Debug "🔧 DEBUG: $_ = $value"
        }
    } else {
        Write-Debug "❌ DEBUG: $_ = [NOT SET]"
    }
}

# Check if SSH key is provided
if ($Env:DRONE_SSH_KEY) {
    Write-Debug "🔑 DEBUG: SSH Key provided (will use SSH authentication)"
} else {
    Write-Debug "🌐 DEBUG: No SSH Key provided (will use HTTPS authentication)"
}

# HACK: no clue how to set the PATH inside the Dockerfile,
# so am setting it here instead. This is not idea.
# Support both portable OpenSSH and Windows native OpenSSH
Write-Debug "🔍 DEBUG: Setting up PATH with Git and SSH locations"
$sshPaths = @('C:\Windows\System32\OpenSSH', 'C:\openssh')
$sshPath = $sshPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($sshPath) {
    Write-Debug "✅ DEBUG: Found SSH directory: $sshPath"
} else {
    Write-Debug "⚠️  DEBUG: No SSH directory found in expected locations"
}
$Env:PATH += ";C:\git\cmd;C:\git\mingw64\bin;C:\git\usr\bin;$sshPath"
Write-Debug "🔧 DEBUG: Updated PATH: $($Env:PATH)"

# Debug: Test Git installation
Write-Debug "🔍 DEBUG: Testing Git installation"
try {
    $gitVersion = & git --version 2>&1
    Write-Debug "✅ DEBUG: Git version: $gitVersion"
} catch {
    Write-Debug "❌ DEBUG: Git not found or failed: $_"
}

# if the workspace is set we should create it and make sure it is the current working directory.
if ($Env:DRONE_WORKSPACE) {
    md -Force $Env:DRONE_WORKSPACE
    cd $Env:DRONE_WORKSPACE
}

# if the netrc enviornment variables exist, write
# the netrc file.

if ($Env:DRONE_NETRC_MACHINE) {
@"
machine $Env:DRONE_NETRC_MACHINE
login $Env:DRONE_NETRC_USERNAME
password $Env:DRONE_NETRC_PASSWORD
"@ > (Join-Path $Env:USERPROFILE '_netrc');
}

# Windows-specific: Persist Git credentials by mounting _netrc from the shared path
# so that subsequent steps in the pipeline can use them for authenticated Git operations.
if ($Env:DRONE_PERSIST_CREDS) {
        $sourcePath = Join-Path $Env:USERPROFILE '_netrc';
    $destinationPath = 'C:\addon\shared\_netrc';
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) -Force;
    if (Test-Path -Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force;
    }
}

if ($Env:DRONE_SSH_KEY) {
    Write-Debug "🔐 DEBUG: Setting up SSH key authentication"
    
    # Create .ssh directory in user profile (Windows standard location)
    $sshDir = Join-Path $Env:USERPROFILE '.ssh'
    Write-Debug "📁 DEBUG: Creating SSH directory: $sshDir"
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    
    # Write SSH key with proper line endings and format
    $keyPath = Join-Path $sshDir 'id_rsa'
    Write-Debug "🔑 DEBUG: Writing SSH key to: $keyPath"
    
    # Debug: Show SSH key format (first and last few chars only for security)
    $keyPreview = $Env:DRONE_SSH_KEY.Substring(0, [Math]::Min(50, $Env:DRONE_SSH_KEY.Length))
    $keyEnd = if ($Env:DRONE_SSH_KEY.Length > 50) { "..." + $Env:DRONE_SSH_KEY.Substring($Env:DRONE_SSH_KEY.Length - 20) } else { "" }
    Write-Debug "🔍 DEBUG: SSH key preview: $keyPreview$keyEnd"
    Write-Debug "📏 DEBUG: SSH key length: $($Env:DRONE_SSH_KEY.Length) characters"
    
    # Ensure proper SSH key format with line breaks
    $sshKeyContent = $Env:DRONE_SSH_KEY -replace '\s+', "`n"
    $sshKeyContent | Out-File -FilePath $keyPath -Encoding ascii
    
    # Debug: Verify key file was created
    if (Test-Path $keyPath) {
        $keyFileSize = (Get-Item $keyPath).Length
        Write-Debug "✅ DEBUG: SSH key file created successfully ($keyFileSize bytes)"
    } else {
        Write-Debug "❌ DEBUG: SSH key file creation failed!"
    }
    
    # Set proper permissions for SSH key (Windows equivalent of chmod 600)
    Write-Debug "🔒 DEBUG: Setting SSH key permissions"
    try {
        $acl = Get-Acl $keyPath
        $acl.SetAccessRuleProtection($true, $false)  # Remove inheritance
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
            'FullControl',
            'Allow'
        )
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $keyPath -AclObject $acl
        Write-Debug "✅ DEBUG: SSH key permissions set successfully"
    } catch {
        Write-Debug "⚠️  DEBUG: Failed to set SSH key permissions: $_"
    }
    
    # Test SSH client availability
    Write-Debug "🔍 DEBUG: Testing SSH client availability"
    $sshExe = $null
    $sshPaths = @('C:\Windows\System32\OpenSSH\ssh.exe', 'C:\openssh\ssh.exe')
    foreach ($path in $sshPaths) {
        if (Test-Path $path) {
            $sshExe = $path
            Write-Debug "✅ DEBUG: Found SSH client at: $path"
            try {
                $sshVersion = & $path -V 2>&1
                Write-Debug "📋 DEBUG: SSH version: $sshVersion"
            } catch {
                Write-Debug "⚠️  DEBUG: Could not get SSH version: $_"
            }
            break
        } else {
            Write-Debug "❌ DEBUG: SSH client not found at: $path"
        }
    }
    
    if (-not $sshExe) {
        Write-Debug "🚨 DEBUG: No SSH client found in any expected location!"
        Write-Debug "🔍 DEBUG: Current PATH: $($Env:PATH)"
        Write-Debug "🔍 DEBUG: Searching for ssh.exe in PATH..."
        try {
            $pathSsh = Get-Command ssh -ErrorAction SilentlyContinue
            if ($pathSsh) {
                Write-Debug "✅ DEBUG: Found SSH in PATH: $($pathSsh.Source)"
                $sshExe = $pathSsh.Source
            }
        } catch {
            Write-Debug "❌ DEBUG: SSH not found in PATH either"
        }
    }
    
    # Set GIT_SSH_COMMAND with proper Windows path format
    $Env:GIT_SSH_COMMAND="ssh -i `"$keyPath`" -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -v"
    Write-Debug "🔧 DEBUG: Set GIT_SSH_COMMAND: $($Env:GIT_SSH_COMMAND)"
    
    # Test SSH connectivity if we can extract hostname from DRONE_REMOTE_URL
    if ($Env:DRONE_REMOTE_URL -match 'git@([^:]+):') {
        $hostname = $matches[1]
        Write-Debug "🌐 DEBUG: Testing SSH connectivity to $hostname"
        try {
            if ($sshExe) {
                Write-Debug "🔍 DEBUG: Running SSH test: $sshExe -i `"$keyPath`" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -T git@$hostname"
                $sshTest = & $sshExe -i $keyPath -o StrictHostKeyChecking=no -o ConnectTimeout=10 -T git@$hostname 2>&1
                Write-Debug "📡 DEBUG: SSH test result: $sshTest"
            } else {
                Write-Debug "⚠️  DEBUG: Cannot test SSH connectivity - no SSH client available"
            }
        } catch {
            Write-Debug "⚠️  DEBUG: SSH connectivity test failed: $_"
        }
    }
}

# configure git global behavior and parameters via the
# following environment variables:

if ($Env:PLUGIN_SKIP_VERIFY) {
    $Env:GIT_SSL_NO_VERIFY = "true"
}

if ($Env:DRONE_COMMIT_AUTHOR_NAME -eq '' -or $Env:DRONE_COMMIT_AUTHOR_NAME -eq $null) {
    $Env:GIT_AUTHOR_NAME = "drone"
} else {
    $Env:GIT_AUTHOR_NAME = $Env:DRONE_COMMIT_AUTHOR_NAME
}

if ($Env:DRONE_COMMIT_AUTHOR_EMAIL -eq '' -or $Env:DRONE_COMMIT_AUTHOR_EMAIL -eq $null) {
    $Env:GIT_AUTHOR_EMAIL = 'drone@localhost'
} else {
    $Env:GIT_AUTHOR_EMAIL = $Env:DRONE_COMMIT_AUTHOR_EMAIL
}

$Env:GIT_COMMITTER_NAME  = $Env:GIT_AUTHOR_NAME
$Env:GIT_COMMITTER_EMAIL = $Env:GIT_AUTHOR_EMAIL

# invoke the sub-script based on the drone event type.
# TODO we should ultimately look at the ref, since
# we need something compatible with deployment events.

Set-Variable -Name "CLONE_TYPE" -Value "$Env:DRONE_BUILD_EVENT"
switch -regex ($Env:DRONE_COMMIT_REF)
{
    'refs/tags/*' {
        Set-Variable -Name "CLONE_TYPE" -Value "tag"
        break
    }

    'refs/pull/*' {
        Set-Variable -Name "CLONE_TYPE" -Value "pull_request"
        break
    }

    'refs/pull-request/*' {
        Set-Variable -Name "CLONE_TYPE" -Value "pull_request"
        break
    }

    'refs/merge-requests/*' {
        Set-Variable -Name "CLONE_TYPE" -Value "pull_request"
        break
    }

}

Invoke-Expression "${PSScriptRoot}\common.ps1"

switch ($CLONE_TYPE) {
    "pull_request" {
        Invoke-Expression "${PSScriptRoot}\clone-pull-request.ps1"
        break
    }
    "tag" {
        Invoke-Expression "${PSScriptRoot}\clone-tag.ps1"
        break
    }
    default {
        Invoke-Expression "${PSScriptRoot}\clone-commit.ps1"
        break
    }
}

Invoke-Expression "${PSScriptRoot}\post-fetch.ps1"