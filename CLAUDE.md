# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Plan & Review
### Before starting work
- Write a plan to .claude/tasks/TASK_NAME. md.
- The plan should be a detailed implementation plan and the reasoning behind them, as well as tasks broken down.
- Don't over plan it, always think MVP.
- Once you write the plan, firstly ask me to review it. Do not continue until I approve the plan.
### While implementing
- You should update the plan as you work.
- After you complete tasks in the plan, you should update and append detailed descriptions of the changes you made, so following tasks can be easily hand over to other

## Project Overview

drone-git is a Drone plugin to clone git repositories. It's a multi-platform (Linux, Windows) Go application that embeds platform-specific shell/PowerShell scripts for git operations. The project heavily emphasizes Docker multi-architecture builds and container image optimization.

## Common Development Commands

### Go Development
```bash
# Build binary for current platform
go build -o drone-git .

# Run tests (requires fixture data)
cd posix && tar -xf fixtures.tar -C / && go test -v

# Build for multiple architectures
./build.sh  # Creates dist/ with Linux/Windows binaries

# Test locally
go run main.go  # Uses current OS-specific scripts
```

### Script Generation (Critical)
```bash
# Regenerate embedded scripts after modifying shell/PowerShell files
cd posix && go generate
cd windows && go generate

# Or manually:
go run scripts/includetext.go --input=posix/clone --input=posix/clone-commit --input=posix/clone-pull-request --input=posix/clone-tag --package=posix --output=posix/posix_gen.go

go run scripts/includetext.go --input=windows/clone.ps1 --input=windows/clone-commit.ps1 --input=windows/clone-pull-request.ps1 --input=windows/clone-tag.ps1 --package=windows --output=windows/windows_gen.go

# Verify generated files are up-to-date
git diff posix/posix_gen.go windows/windows_gen.go
```

### Docker Development
```bash
# Build single-platform image (Linux AMD64)
docker build --rm -f docker/Dockerfile.linux.amd64 -t harness/drone-git .

# Build Windows LTSC 2022
docker build -f docker/Dockerfile.windows.ltsc2022 -t harness/drone-git:windows-ltsc2022 .

# Build Windows LTSC 2025 (newer, optimized)
docker build -f docker/Dockerfile.windows.ltsc2025 -t harness/drone-git:windows-ltsc2025 .

# Test locally with environment variables
docker run --rm \
  -e DRONE_WORKSPACE=/drone \
  -e DRONE_REMOTE_URL=https://github.com/drone/envsubst.git \
  -e DRONE_BUILD_EVENT=push \
  -e DRONE_COMMIT_SHA=15e3f9b7e16332eee3bbdff9ef31f95d23c5da2c \
  -e DRONE_COMMIT_BRANCH=master \
  -w "/home/drone" \
  harness/drone-git
```

### CI/CD Management
```bash
# Regenerate .drone.yml from Starlark (if needed)
drone starlark --format .drone.starlark

# Lint/validate Drone config
drone lint .drone.yml
```

### Debugging Commands
```bash
# Test script extraction without running git operations
DRONE_WORKSPACE=/tmp/test DRONE_REMOTE_URL=https://github.com/example/repo.git go run main.go

# Verify embedded scripts match source files
diff posix/clone <(grep -A 1000 "const Clone =" posix/posix_gen.go | tail -n +2 | head -n -1 | sed 's/^//')

# Check if generated files are outdated
git status posix/posix_gen.go windows/windows_gen.go

# Test specific clone scenarios locally
docker run --rm \
  -e DRONE_WORKSPACE=/test \
  -e DRONE_REMOTE_URL=https://github.com/user/repo.git \
  -e DRONE_BUILD_EVENT=pull_request \
  -e DRONE_COMMIT_REF=refs/pull/123/head \
  -e DRONE_COMMIT_SHA=abc123 \
  -e DRONE_COMMIT_BRANCH=main \
  harness/drone-git

# View extracted scripts during execution (add to main.go for debugging)
# fmt.Printf("Extracted script to: %s\n", tmpDir)
```

## Architecture Overview

### Embedded Script System
The main.go embeds scripts from both `posix/` and `windows/` directories using Go's `embed.FS`. At runtime:
- Creates temporary directory with extracted scripts
- Executes platform-appropriate script (bash for POSIX, PowerShell for Windows)
- Scripts handle git clone operations with Drone-specific environment variables

### Docker Multi-Platform Strategy
**Platform Support**: Linux (amd64, arm64, arm), Windows (multiple LTSC versions)

**Key Optimization Pattern**: Windows images use multi-stage builds:
1. **Build stage**: Downloads and installs Git/Git-LFS
2. **Final stage**: Uses smaller nanoserver base image
3. **Size reduction**: Removes documentation, locale files, temp downloads

**Recent Optimizations**: LTSC 2022/2025 Dockerfiles were optimized from `windowsservercore` to `powershell:nanoserver` base images, reducing size significantly.

### Image Variants
- **Standard**: Full-privilege containers
- **Rootless**: Uses `ContainerUser` for security-focused deployments
- **Multi-arch manifests**: Automated via `docker/manifest.tmpl`

## Key Development Patterns

### Adding New Windows LTSC Support
When adding new Windows versions:
1. Create `Dockerfile.windows.ltsc[VERSION]` and `.rootless` variant
2. Follow optimization pattern from ltsc2022/ltsc2025 (use nanoserver base)
3. Update `docker/manifest.tmpl` to include new platform
4. Update CI pipeline in `.drone.yml` or `.drone.starlark`

### Docker Size Optimization Strategy
For Windows containers specifically:
- Use `powershell:nanoserver-ltsc[VERSION]` as final base (not windowsservercore)
- Combine download/extract/cleanup in single RUN layer
- Remove unnecessary Git components: `/usr/share/{doc,info,man,locale}`
- Use multi-stage builds to avoid intermediate file bloat

### Testing Approach
Tests are located in `posix/posix_test.go` and rely on fixture data in `posix/fixtures.tar`. To run tests:
1. Extract fixtures to root filesystem
2. Tests validate git operations and script behavior

### Script Development
- **POSIX scripts**: Located in `posix/`, entry point is `posix/script`
- **Windows scripts**: Located in `windows/`, entry point is `windows/clone.ps1`
- **Auxiliary Windows scripts**:
  - `windows/utility.ps1` - Error handling utilities (Invoke-Utility function)
  - `windows/git-utility.ps1` - Git fetch wrapper functions (Start-Fetch)
  - `windows/common.ps1` - Shared git configuration and setup
  - `windows/post-fetch.ps1` - Post-clone operations
- Scripts must handle various Drone environment variables (see Environment Variables section)

## Environment Variables

### Core Drone Variables
- `DRONE_WORKSPACE` - Target directory for git operations
- `DRONE_REMOTE_URL` - Git repository URL
- `DRONE_COMMIT_SHA` - Commit hash to checkout/merge
- `DRONE_COMMIT_REF` - Git reference (refs/pull/*, refs/tags/*, refs/heads/*)
- `DRONE_COMMIT_BRANCH` - Target branch name
- `DRONE_BUILD_EVENT` - Event type (push, pull_request, tag)
- `DRONE_TAG` - Tag name for tag events
- `DRONE_SOURCE_BRANCH` - Source branch for pull requests

### Plugin Configuration
- `PLUGIN_DEPTH` - Clone depth for shallow clones (e.g., --depth=50)
- `PLUGIN_PR_CLONE_STRATEGY` - PR strategy: "SourceBranch" or merge commit
- `PLUGIN_SKIP_VERIFY` - Skip SSL verification if set
- `DRONE_PR_MERGE_STRATEGY_BRANCH` - Use branch merge strategy if "true"

### Authentication
- `DRONE_NETRC_MACHINE` - Hostname for .netrc authentication
- `DRONE_NETRC_USERNAME` - Username for .netrc
- `DRONE_NETRC_PASSWORD` - Password/token for .netrc
- `DRONE_SSH_KEY` - SSH private key for git operations

## Important Repository Context

### Recent Changes
The Windows LTSC 2022 and 2025 Dockerfiles were recently optimized for smaller image sizes. This optimization pattern should be followed for any new Windows container variants.

### Git Hooks
The repository includes git-leaks support. Run `./git-hooks/install.sh` to enable leak detection hooks.

### Manifest Management
Multi-platform Docker manifests are managed via templates in `docker/manifest.tmpl` and `docker/manifest.rootless.tmpl`. These automatically generate platform-specific image references based on build tags.

## Known Issues & Fixes

### Pull Request Merge Issues
**Problem**: `merge: <sha> - not something we can merge`
**Location**: `posix/clone-pull-request:38` and `windows/clone-pull-request.ps1:38`
**Cause**: `DRONE_COMMIT_SHA` contains incorrect commit hash not present in fetched refs
**Fix**: Replace `git merge ${DRONE_COMMIT_SHA}` with `git merge FETCH_HEAD`

### Windows Git Fetch Hanging
**Problem**: Git fetch operations hang indefinitely on Windows
**Location**: Windows PowerShell scripts using `Invoke-Utility`
**Cause**: No timeout mechanism for git operations
**Fix**: Add git config timeouts and PowerShell timeout wrappers

### Script Generation Sync
**Problem**: Embedded scripts don't match source files
**Detection**: `git status posix/posix_gen.go windows/windows_gen.go`
**Fix**: Always run `go generate` after modifying shell/PowerShell scripts