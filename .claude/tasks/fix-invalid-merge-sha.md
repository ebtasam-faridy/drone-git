# Fix for Invalid Merge SHA in Pull Request Clone

## Problem Statement

When cloning pull requests, the script fails with:
```
+ git merge 33ad12bb43419ee92828710cf7afa9cbd9ea08ff
merge: 33ad12bb43419ee92828710cf7afa9cbd9ea08ff - not something we can merge
```

## Root Cause Analysis

1. The script fetches the PR ref: `git fetch origin refs/pull/978/head:`
2. This fetch operation brings in the PR's HEAD commit
3. But then tries to merge `${DRONE_COMMIT_SHA}` which contains a different, non-existent commit
4. The commit `33ad12bb43419ee92828710cf7afa9cbd9ea08ff` is not in the fetched references

## Why This Happens

In pull request workflows:
- `DRONE_COMMIT_REF` = `refs/pull/978/head` (correct - the PR reference)
- `DRONE_COMMIT_SHA` = `33ad12bb43419ee92828710cf7afa9cbd9ea08ff` (incorrect - should be the PR's HEAD commit)

The `DRONE_COMMIT_SHA` appears to contain either:
- The merge commit SHA that doesn't exist yet
- A commit from a different context
- An incorrectly propagated value from the CI system

## Solution Options

### Option 1: Use FETCH_HEAD (Recommended - Most Reliable)
**Rationale**: After `git fetch origin ${DRONE_COMMIT_REF}:`, Git stores the fetched commit in `FETCH_HEAD`. This is guaranteed to be correct.

**Changes needed**:
- `posix/clone-pull-request` line 38: Change from `git merge ${DRONE_COMMIT_SHA}` to `git merge FETCH_HEAD`
- `windows/clone-pull-request.ps1` line 38: Change from `iu git merge $Env:DRONE_COMMIT_SHA` to `iu git merge FETCH_HEAD`

### Option 2: Validate SHA Before Merge
**Rationale**: Check if the SHA exists before attempting merge, fall back to FETCH_HEAD if not.

**Changes needed**:
```bash
# Check if commit exists
if git rev-parse --verify ${DRONE_COMMIT_SHA}^{commit} >/dev/null 2>&1; then
    git merge ${DRONE_COMMIT_SHA}
else
    echo "Warning: DRONE_COMMIT_SHA not found, using FETCH_HEAD"
    git merge FETCH_HEAD
fi
```

### Option 3: Extract SHA from Fetch Output
**Rationale**: Parse the actual SHA from the fetch operation.

**Changes needed**:
```bash
# Capture the fetched SHA
FETCHED_SHA=$(git fetch origin ${DRONE_COMMIT_REF}: 2>&1 | grep -oE '[0-9a-f]{40}' | head -1)
git merge ${FETCHED_SHA:-FETCH_HEAD}
```

## Implementation Plan (MVP - Option 1)

### Step 1: Update POSIX Script
**File**: `posix/clone-pull-request`
**Line 38**: 
```diff
- git merge ${DRONE_COMMIT_SHA}
+ git merge FETCH_HEAD
```

Also update line 14 for consistency:
```diff
- git checkout ${DRONE_COMMIT_SHA} -b ${DRONE_SOURCE_BRANCH}
+ git checkout FETCH_HEAD -b ${DRONE_SOURCE_BRANCH}
```

### Step 2: Update Windows Script
**File**: `windows/clone-pull-request.ps1`
**Line 38**:
```diff
- iu git merge $Env:DRONE_COMMIT_SHA
+ iu git merge FETCH_HEAD
```

**Line 15**:
```diff
- iu git checkout ${Env:DRONE_COMMIT_SHA} -b ${Env:DRONE_SOURCE_BRANCH}
+ iu git checkout FETCH_HEAD -b ${Env:DRONE_SOURCE_BRANCH}
```

### Step 3: Regenerate Embedded Scripts
Run in project root:
```bash
cd posix && go generate
cd ../windows && go generate
```

### Step 4: Test
Build and test with a pull request scenario to verify the fix.

## Why This Fix Works

1. `FETCH_HEAD` is a Git reference that always points to the last fetched commit
2. After `git fetch origin refs/pull/978/head:`, FETCH_HEAD will contain the exact commit that was fetched
3. This eliminates dependency on potentially incorrect `DRONE_COMMIT_SHA` values
4. This pattern is already used successfully in `clone-tag` script

## Impact Analysis

- **Positive**: Fixes the immediate issue, makes PR cloning more robust
- **Neutral**: Behavior change only affects PR scenarios where SHA was wrong
- **Risk**: Low - using FETCH_HEAD is a standard Git pattern

## Testing Checklist

- [ ] Test with regular PR
- [ ] Test with PR from fork
- [ ] Test with PR that has merge conflicts
- [ ] Test SourceBranch strategy (`PLUGIN_PR_CLONE_STRATEGY=SourceBranch`)
- [ ] Test default merge strategy
- [ ] Verify no regression for regular commits
- [ ] Verify no regression for tags