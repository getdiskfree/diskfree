# Contributing to DiskFree

Thanks for your interest in contributing! DiskFree is a simple tool and we want to keep the contribution process simple too.

## How to Contribute

1. **Fork** the repository
2. **Create a branch** from `main` with a descriptive name:
   - `fix/spotlight-detection` for bug fixes
   - `feat/multiple-eject` for new features
   - `docs/install-instructions` for documentation
3. **Make your changes** and test on macOS
4. **Open a pull request** back to `main` with a clear description of what you changed and why

## Development Guidelines

### Keep it simple

DiskFree is a single bash script with zero dependencies beyond standard macOS tools. Let's keep it that way. If a feature requires installing Homebrew packages or pulling in external binaries, it probably doesn't belong here.

### Test on macOS

This tool uses macOS-specific commands (`diskutil`, macOS `lsof` output format, BSD `head`/`tail`). Always test your changes on a real Mac. Common gotchas:

- `head -n -1` doesn't work on macOS (it's a GNU extension) — use `sed` or rethink the approach
- `lsof` output format can vary between macOS versions
- Paths and volume mounting behavior differ from Linux

### Script conventions

- Use `set -euo pipefail` (already set)
- Quote all variables: `"$var"` not `$var`
- Use `local` for function variables
- Keep colored output using the existing helper functions (`info`, `warn`, `error`, `step`)
- Add new system process names to `SYSTEM_PROCS` if you discover processes that auto-release on unmount

### Commit messages

Write clear, concise commit messages. No specific format required — just make it obvious what changed:

```
Fix: handle volume names with spaces in path
Add: support for ejecting multiple volumes at once
Docs: clarify one-liner install permissions
```

## Reporting Bugs

Open an issue with:

- Your macOS version
- The error or unexpected behavior you saw
- The terminal output (copy/paste the full session if possible)
- What disk/volume type you were trying to eject

## Feature Requests

Open an issue describing what you'd like and why. Keep in mind the project philosophy: DiskFree should stay a single, dependency-free bash script that does one thing well.

## Code of Conduct

Be kind, be constructive. We're all here because we got frustrated by a stubborn disk at some point.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
