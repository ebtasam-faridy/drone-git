# Fix for Windows Git Fetch Hanging Issue

## Problem Analysis

### Issue Description
The Windows execution of drone-git is hanging during `git fetch` operations with the following symptoms:
- Command stuck at: `git fetch --depth=10 origin +refs/heads/main:`
- No timeout or error handling for long-running fetch operations
- User recommendation: "Please Check the timeout configuration on the step to extend the duration of the step"

### Root Causes Identified

1. **No timeout mechanism in git fetch operations**
   - The `Invoke-Utility` function in `windows/utility.ps1` executes git commands without any timeout
   - Git fetch can hang indefinitely on network issues or authentication problems

2. **Missing git configuration for network timeouts**
   - No `http.lowSpeedLimit` or `http.lowSpeedTime` git configurations
   - No retry mechanism for failed fetches

3. **Potential authentication issues**
   - The netrc file configuration might not be properly set up for Windows
   - HTTPS credentials may not be properly configured

## Implementation Plan

### Task 1: Add Git Network Timeout Configuration
**File**: `windows/clone.ps1`
**Changes**:
- Add git config settings for network timeouts before clone operations
- Configure `http.lowSpeedLimit` and `http.lowSpeedTime` to detect stalled connections
- Add `http.postBuffer` for large repositories

```powershell
# Configure git network settings
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 600
git config --global http.postBuffer 524288000
```

### Task 2: Implement Timeout Wrapper for Git Commands
**File**: `windows/utility.ps1`
**Changes**:
- Create new function `Invoke-UtilityWithTimeout` that wraps git commands with timeout
- Use PowerShell jobs or Start-Process with timeout capability
- Provide clear error messages when timeout occurs

```powershell
function Invoke-UtilityWithTimeout {
    param(
        [int]$TimeoutSeconds = 600,
        [string[]]$Arguments
    )
    # Implementation with timeout logic
}
```

### Task 3: Add Retry Logic for Failed Fetches
**File**: `windows/git-utility.ps1`
**Changes**:
- Modify `Start-Fetch` function to include retry logic
- Implement exponential backoff for retries
- Add logging for debugging fetch issues

### Task 4: Improve Error Diagnostics
**Files**: All Windows PowerShell scripts
**Changes**:
- Add verbose logging before and after git operations
- Include timestamp in log messages
- Add network connectivity check before fetch

### Task 5: Add Progress Indication
**File**: `windows/git-utility.ps1`
**Changes**:
- Add progress messages during long operations
- Implement periodic "still working" messages for long-running fetches

## Testing Strategy

1. Test with repositories that have:
   - Large history (depth > 1000)
   - Slow network connections
   - Authentication requirements

2. Verify timeout behavior:
   - Simulate network interruption
   - Test with unreachable repositories
   - Verify proper error messages

## Rollback Plan

If issues occur:
1. Keep original functions alongside new ones initially
2. Use environment variable to toggle between old and new behavior
3. Gradual rollout with feature flag

## MVP Approach

For immediate fix (MVP):
1. Add basic git config timeout settings (Task 1)
2. Add simple timeout wrapper with 10-minute default (simplified Task 2)
3. Add basic error logging (simplified Task 4)

Full implementation can follow after MVP validation.