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

### The installer's options

| Option | What it does | Where to find the value |
|---|---|---|
| **FR / EN** | Language of the installer, of the messages on the key and of Claude's procedure | Your choice. Can be changed later on the key with `claude-recovery lang en` |
| **Personal / Business** | Which image is written | Personal: you recover your own files. Business: a technician works for customers and every command is logged |
| **Select the USB key** | The disk that will be erased | Only USB disks are listed. A disk over 130 GB is flagged in red: check it is not a backup drive |
| **Use a local file…** | Writes an `.iso` you already have instead of downloading the latest release | An image downloaded from the [releases](https://github.com/Miinja/claude-recovery/releases), or built with `build/build-iso.sh` |
| **Online help** | Opens this page | |

Business edition settings (the "Fill in the settings…" link under the edition):

| Field | Required | Where to find the value |
|---|---|---|
| **Company name** | No | Your workshop or company name. It only identifies who the key belongs to |
| **Name of this key** | Yes | A name you choose, e.g. `key01`. Use the name written on this key's line in `tokens.txt` on your server |
| **Log server** | No | `https://` followed by the `LOGS_DOMAIN` value of `server/.env` on your server (see [server/README.md](server/README.md)). Empty: logs stay on the key |
| **Key token** | With a log server | The token on this key's line in `server/tokens.txt` (`name token`). Create one on the server with `openssl rand -hex 32`, add the line, no restart needed |
| **Update repository** | No | Leave empty to follow this GitHub repository. Only fill in the `https` address of your own copy if the company hosts one |

**Test the server** checks, from your PC, that the log server answers and accepts the
token. It writes nothing on the server. With Caddy's internal certificate the test reports
an untrusted certificate: that is expected on a PC that does not have the certificate;
the key accepts it if the image was built with it (see [server/README.md](server/README.md)).

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
- [x] Image build — both editions build in a `debian:trixie` container, and the release workflow has run on GitHub
- [x] First boot — tested in a virtual machine (QEMU): BIOS and UEFI boot, plain and encrypted persistence, installer settings applied (business edition), second boot with persistence active
- [ ] First boot on a real USB key — **never tried**
- [x] Windows mode — launcher tested on a PC for both editions with a stand-in for Claude (isolated config, log, report, cleanup)
- [ ] Windows mode — a real Claude session on a customer PC has **never been tried**
- [ ] Log server and Forgejo — files ready in `server/`, to be deployed

### Recovery scenarios tested

Each scenario runs on a fake disk (an image file) holding 15 files: 12 JPEG photos, a PNG,
a PDF and a Word document. The disk is attached read-only, cloned with `ddrescue`, and the
work is done on the clone. A file counts as recovered only if its SHA-256 matches the
original.

| Scenario | Tool used on the clone | Recovered intact | Names and folders |
|---|---|---|---|
| FAT32 card formatted by mistake | `photorec` | 15 / 15 | Lost (expected with PhotoRec) |
| Files deleted on NTFS, recycle bin emptied | `ntfsundelete --truncate` | 15 / 15 | Names kept, folders lost |
| Partition table erased, disk shown as "not initialised" | `testdisk` to locate the partition, read-only mount | 15 / 15 | Kept |
| Disk with bad sectors (2 unreadable areas, 192 sectors) | `ddrescue`, then read-only mount of the clone | 14 / 15 | Kept |

In every scenario the source disk's checksum is identical before and after. In the last
one, `ddrescue` rescued 99.96 % of the disk; the photo that sat on an unreadable area
comes back damaged.

These are favourable cases: small disks, unfragmented files, a quick format. They show
that the tools shipped on the key work on the classic failures; real disks will do worse.
The commands were run by hand following the procedure, not by a Claude session.

## License

Copyright (C) 2026 Miinja

This program is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation, version 3.
It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY. See
[LICENSE](LICENSE) for the full text.

Data recovery carries risk. This software is provided as is; you remain responsible for
the disks you work on.
