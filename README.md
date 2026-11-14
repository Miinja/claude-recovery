# Claude Recovery

**English** · [Français](README.fr.md)

A bootable USB data-recovery key driven by **Claude Code**.

Boot any PC from the key; Claude Code diagnoses the disk, clones it, then recovers the
files (ddrescue, testdisk, photorec, smartctl…) without ever writing to the original disk.

> Independent project, not affiliated with or endorsed by Anthropic. "Claude" and
> "Claude Code" are trademarks of Anthropic. A Claude account is required to use the key.

## Two editions

| | **Personal** | **Business** |
|---|---|---|
| For | Someone recovering their own files | A technician working for a customer |
| Claude's tone | Explains every step in plain words; says when it is better to stop and see a professional | Short and factual |
| Command log | On the key only | On the key **and** sent to the company's server |
| End-of-job report | In the recovery folder | Same, and sent to the server |
| Settings at creation | Language | Language, key name, log server and token, update repository (optional) |
| Windows mode (diagnosing a software problem) | Yes, procedure for a non-specialist | Yes, technician procedure |
| Updates | The project's GitHub repository | GitHub, or the company's own repository |

The edition is fixed in the image (`particulier` = personal, `entreprise` = business).
Both images are published in the
[releases](https://github.com/Miinja/claude-recovery/releases).

## Languages

Everything exists in **English and French**: the installer, the messages on the key, and
the procedures Claude follows.

- The language is chosen in the installer and written to the key.
- It can be changed at any time on the key:

```
claude-recovery lang en
claude-recovery lang fr
```

## Creating a key

### On Windows: the installer

Download `ClaudeRecoveryInstaller.exe` from the latest release, run it, then:

1. choose the language and the edition;
2. choose the USB key (it is completely erased);
3. business edition: fill in the settings;
4. **Write the key**. The installer downloads the image, checks its checksum, writes it,
   then reads the key back to verify it.

### On Linux

```
sudo scripts/make-key.sh particulier /dev/sdX en
sudo scripts/make-key.sh entreprise  /dev/sdX en
```

### First boot

Boot a PC from the key and type `claude-recovery`. The first time, the key offers to
create its persistence space (encrypted with a passphrase if you wish): it is what keeps
the Claude account sign-in, the settings and the logs from one boot to the next. One
reboot later, the key is operational.

## Usage

```
claude-recovery
```

The command updates the key (`git pull`), prepares the working folder on the destination
drive, then starts Claude Code in it. In the business edition it asks for the technician
and the job reference; on exit, pending logs and `report.md` are sent to the server.
Offline, everything stays on the key and is sent at the next connected session.

### Windows mode

From the `CR-WINDOWS` partition of the key, in PowerShell:

```
powershell -ExecutionPolicy Bypass -File .\windows\start-claude.ps1
```

The script follows the procedure of the key's edition and language (`-Lang en|fr` to
override). You sign in to the Claude account at every session. On exit: sign-out, report
copied to the key, and everything the session added to the PC is removed.

## Publishing a release

```
git tag v0.1.0
git push origin v0.1.0
```

The `.github/workflows/release.yml` workflow builds both images and the installer, then
creates the release. File names are fixed (`claude-recovery-particulier.iso`,
`claude-recovery-entreprise.iso`, `ClaudeRecoveryInstaller.exe`): the installer and
`make-key.sh` always fetch the latest release.

## Repository layout

```
config/
  entreprise/            Business edition: procedure (CLAUDE.<lang>.md), permissions, settings template
  particulier/           Personal edition: procedure and permissions
  windows/               Windows mode: one procedure per edition and language, permissions
hooks/
  log-command.sh         Logs every command Claude runs, with an offline queue
scripts/
  session.sh             Session launcher (the `claude-recovery` command)
  firstboot.sh           First boot: installer settings, persistence
  update.sh              git pull + config install (the `claude-recovery-update` command)
  lib.sh                 Shared functions (edition, language, settings block)
  make-key.sh            Creating a key from Linux
  update-keys.sh         Updates keys plugged into a workstation, without booting them
build/
  build-iso.sh           Builds one edition (Debian live-build)
  packages.txt           Packages of the image
  hooks/                 live-build hook: installs Claude Code into the image
installer/
  src/                   Windows installer (C#, .NET Framework shipped with Windows)
  build.ps1              Build script, no SDK to install
windows/
  start-claude.ps1       Windows mode: temporary install, session, cleanup
  log-command.ps1        Command logging in Windows mode
server/
  docker-compose.yml     Log receiver + Forgejo, behind Caddy
  log-receiver/          HTTP service receiving logs and reports
.github/workflows/
  release.yml            Builds the images and the installer, publishes them
```

### How the settings reach the key

Windows cannot create a Linux partition. The installer therefore writes the image, then
drops the settings in a small raw block right after it (format described in
`scripts/lib.sh`). On first boot, the key reads that block, creates its persistence
partition, stores the settings there, then erases the block.

## Safety rules

1. The source disk is **never** written to: ddrescue clone first, work on the image.
2. Claude works on **metadata** and does not open file contents without a reason.
3. Destructive commands are blocked in `settings.json` and repeated as managed settings
   (`/etc/claude-code/managed-settings.json`) so that no local setting can lift them.
   These rules are a guard rail, not a hard security boundary.
4. No customer data and no token in this repository (see `.gitignore`).
5. A key updates itself from this repository at every session: whoever can push to `main`
   can change the procedure of every key. Protect the branch.
6. A lost business key is revoked in three places: the log-server token, the
   update-repository token, and the Claude account session. Hence the value of an
   encrypted persistence.

## Status

- [x] Procedures for both editions and Windows mode, in English and French
- [x] Logging and sending to the server — tested end to end locally
- [x] Settings block installer → key — tested (written on Windows, read back on Linux)
- [x] Windows installer — builds; copy, settings block and read-back tested on a file
- [ ] Windows installer — writing to a real USB key has **never been tried**
- [ ] Image build — scripts and workflow written, **never run**
- [ ] First boot (persistence creation) — **never tried** on a key
- [ ] Windows mode — to be validated on a test PC
- [ ] Log server and Forgejo — files ready in `server/`, to be deployed

## License

Copyright (C) 2026 Miinja

This program is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation, version 3.
It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY. See
[LICENSE](LICENSE) for the full text.

Data recovery carries risk. This software is provided as is; you remain responsible for
the disks you work on.
