# DiskFree

Eject stubborn macOS disks without logging out. Find what's blocking, close it safely, eject cleanly.

## The Problem

On macOS, external drives frequently refuse to eject with the error: *"The disk couldn't be ejected because the Finder is using it."* The common workaround is to log out, which closes every open app and disrupts your workflow.

The real cause is almost always a background process — Spotlight indexing, Preview holding a file, iCloud sync — that has an open handle on the disk. You have no visibility into what's blocking and no easy way to fix it.

## What DiskFree Does

DiskFree is a single shell script that:

1. Lists all mounted external volumes and lets you pick one
2. Scans for every process holding the disk open using `lsof`
3. Categorizes blockers into **user apps** vs. **system processes** (Spotlight, iCloud, etc.)
4. Shows whether each process is **reading or writing** (critical for data safety)
5. **Warns you** before ejecting if any process is actively writing
6. Gracefully closes blocking user apps, then ejects the disk cleanly
7. Falls back to force unmount only if the normal eject fails

No logout required. No data corruption risk. One command.

## Install

### One-liner

```bash
curl -sL https://raw.githubusercontent.com/getdiskfree/diskfree/main/eject-disk.sh -o /usr/local/bin/eject-disk && chmod +x /usr/local/bin/eject-disk
```

### Manual

```bash
# Download
curl -sL https://raw.githubusercontent.com/getdiskfree/diskfree/main/eject-disk.sh -o eject-disk.sh

# Make executable
chmod +x eject-disk.sh

# (Optional) Move to PATH for global access
sudo mv eject-disk.sh /usr/local/bin/eject-disk
```

## Usage

```bash
# Interactive — lists volumes and lets you pick
eject-disk

# Direct — pass the volume name
eject-disk "Extreme SSD"
```

### Example Session

```
╔══════════════════════════════════════════╗
║  DiskFree  — eject stubborn disks       ║
╚══════════════════════════════════════════╝

→ Scanning for external volumes...

Found 2 volume(s):

  1) Extreme SSD
  2) GoPro SD

→ Select volume to eject [1-2]: 1

→ Checking what's using Extreme SSD...

Blocking processes:

  ● Preview (PID 1847) — reading — user app
  ● mds_stores (PID 312) — reading — system
  ● fseventsd (PID 97) — reading — system

✓ 1 user app(s), 2 system process(es)
  System processes (Spotlight, iCloud, etc.) release automatically on unmount

→ Close blocking apps and eject? (Y/n): y

→ Closing Preview (PID 1847)...
✓ Preview closed

→ Attempting to eject Extreme SSD...

✓ Extreme SSD ejected successfully!
  Safe to remove the disk.
```

## How It Works

DiskFree uses `lsof` to find all processes with open file handles on the target volume, then categorizes them:

**System processes** (`mds`, `mds_stores`, `mdworker`, `fseventsd`, `bird`, `cloudd`, etc.) are flagged but not killed — they release automatically when the volume unmounts.

**User apps** (Preview, Finder, VS Code, etc.) are the actual blockers. DiskFree sends a graceful `SIGTERM` first, waits up to 5 seconds, and only escalates to `SIGKILL` if the process doesn't exit.

**Write detection** checks file descriptor flags from `lsof` output. If any process has a write handle open, DiskFree displays an extra warning and requires explicit confirmation before proceeding.

## Requirements

- macOS (tested on Ventura, Sonoma, Sequoia)
- Bash 3.2+ (ships with macOS)
- No external dependencies — uses only built-in macOS tools (`lsof`, `diskutil`, `ps`, `kill`)

## Who This Is For

- Photographers and videographers working with SD cards and portable SSDs
- Developers with external build drives
- Anyone who's ever seen "The disk couldn't be ejected" and had to log out
- GoPro, Insta360, and action camera users

## Good to Know

DiskFree is a single readable bash file with no dependencies, no network calls, and no telemetry. It uses standard macOS tools (`lsof`, `kill`, `diskutil`) and nothing else. The source is fully open — we recommend reviewing any script before running it on your machine.

If a process is actively writing to your disk, DiskFree will warn you before taking action. Save your work before closing blocking apps.

This software is provided "as is" under the [MIT License](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT — see [LICENSE](LICENSE) for details.

## Origin Story

This tool was born from a real debugging session: an Extreme SSD wouldn't eject because macOS Preview had open file handles on trashed video files, and Spotlight was indexing the drive. The usual fix (logging out) would have closed dozens of open apps and projects. Instead, we used `lsof` to identify the blockers, killed Preview, and ejected cleanly. DiskFree packages that exact workflow into a single command anyone can use.
