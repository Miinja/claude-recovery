# Ctrl-Z

*Data recovery, powered by Claude Code.*

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

The edition is fixed in the image (`personal` or `business`).
Both images are published in the
[releases](https://github.com/Miinja/ctrl-z/releases).

## Languages

Everything exists in **English and French**: the installer, the messages on the key, and
the procedures Claude follows.

- The language is chosen in the installer and written to the key.
- It can be changed at any time on the key:

```
ctrlz lang en
ctrlz lang fr
```

## Requirements and recommendations

### The USB key

| | Minimum | Recommended |
|---|---|---|
| Capacity | 4 GB | 32 GB |
| Interface | USB 2.0 | USB 3.0 or later |

- The image takes 1.4 GB and the installer refuses a key that does not have 2 GB free
  after it, hence the 4 GB minimum.
- The space left after the image is split in two on first boot: the persistence
  (Claude sign-in, settings, logs; half of the free space, 16 GB at most) and the
  `CTRL-Z` partition used by Windows mode. A 32 GB key gives about 14 GB of
  persistence; from 64 GB up it stays at 16 GB and only `CTRL-Z` grows.
- The whole system is read from the key: on USB 2.0 it boots and runs, but slowly. Prefer
  a USB 3 key from a known brand, and plug it into a USB 3 port.
- Use a key dedicated to this: it is completely erased, and it should not hold anything
  else. The installer flags disks over 130 GB, which are usually external drives.
- Encrypt the persistence (offered on first boot) if the key leaves your home or workshop:
  it holds the Claude account session and, in the business edition, the server token.

### The PC you boot

- 64-bit Intel or AMD processor. BIOS and UEFI boot both work; Secure Boot is supported
  by the image.
- Not the very oldest 64-bit PCs: Claude Code itself needs a reasonably recent processor.
  In tests it crashed ("illegal instruction") on the baseline 64-bit processor model and
  ran on a recent one; the exact limit was not measured. The key still boots on such a
  PC, but Claude does not start.
- 4 GB of RAM is what the key was tested with (in a virtual machine); 8 GB is more
  comfortable.
- An Internet connection, wired if possible: Claude Code needs it for the whole session.
- A Claude account.

### The destination drive

Recovered files never go to the key or to the disk being recovered: you need a third
drive.

- Capacity: at least the size of the disk to recover, since the first step is a full
  clone of it. Twice that size is comfortable, because the recovered files are copied out
  next to the clone.
- A drive in good health, formatted in exFAT or NTFS so the result can be read on Windows.
- Plug it into a different USB port from the key, on a powered hub if the PC has few
  ports.

### Before you start

- Stop using the faulty disk at once: every write can destroy what is still recoverable.
- A disk that clicks, is not detected at all, or was dropped needs a recovery lab, not
  software. Claude says so when the symptoms point that way.
- Create and test the key before you need it, on a PC that works.

## Creating a key

### On Windows: the installer

Download `CtrlZInstaller.exe` from the latest release, run it, then:

1. choose the language and the edition;
2. choose the USB key (it is completely erased);
3. business edition: fill in the settings;
4. **Write the key**. The installer downloads the image, checks its checksum, writes it,
   then reads the key back to verify it.

### The installer's options

| Option | What it does | Where to find the value |
|---|---|---|
| **FR / EN** | Language of the installer, of the messages on the key and of Claude's procedure | Your choice. Can be changed later on the key with `ctrlz lang en` |
| **Personal / Business** | Which image is written | Personal: you recover your own files. Business: a technician works for customers and every command is logged |
| **Select the USB key** | The disk that will be erased | Only USB disks are listed. A disk over 130 GB is flagged in red: check it is not a backup drive |
| **Use a local file…** | Writes an `.iso` you already have instead of downloading the latest release | An image downloaded from the [releases](https://github.com/Miinja/ctrl-z/releases), or built with `build/build-iso.sh` |
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
sudo scripts/make-key.sh personal /dev/sdX en
sudo scripts/make-key.sh business /dev/sdX en
```

### First boot

Boot a PC from the key: the assistant starts by itself. The first time, it offers to
create the key's persistence space (encrypted with a passphrase if you wish): it is what
keeps the Claude account sign-in, the settings and the logs from one boot to the next. One
reboot later, the key is operational.

## Usage

The assistant starts on its own when the key boots; everything is chosen with the arrow
keys and Enter. To start it again after leaving it, type `ctrlz`.

1. **Language and keyboard**, asked once (the installer's language is used if there is
   one).
2. **Network**: a cable is detected automatically; otherwise a menu lists the Wi-Fi
   networks and asks for the password.
3. **Update** of the key (`git pull`).
4. **Goal**: recover files, or diagnose a Windows that no longer starts (see
   [Windows diagnosis](#windows-diagnosis)).
5. **Disk to recover**, picked from a list showing size, model, connection and serial
   number. It is immediately **locked read-only in the kernel**: from then on no command
   can write to it, and mounting it gives a read-only mount.
6. **Destination**, picked from the partitions of the other disks. The key and the disk
   to recover are not offered, and a destination too small for a full clone is flagged.
7. Claude Code starts in the job folder. The choices above are handed to it as facts, in
   a `CLAUDE.md` file written in that folder.

In the business edition the assistant also asks for the technician and the job reference;
on exit, pending logs and `report.md` are sent to the server. Offline, everything stays on
the key and is sent at the next connected session.

### Windows diagnosis

For a PC whose Windows no longer starts, loops on "Automatic Repair", shows blue screens
or keeps crashing. **This first version diagnoses and recommends; it repairs nothing.**
The Windows disk stays locked read-only for the whole session.

1. **BitLocker**: an encrypted partition is reported with its protectors (TPM, password,
   recovery key). The launcher offers to type the 48-digit recovery key to open it
   **read-only**. The key goes from the launcher to `cryptsetup` on its standard input: it
   is never shown to Claude, never stored, and absent from the command line and the logs
   (a recovery key that would appear in a logged command is replaced by
   `[recovery key removed]`).
2. **Inventory** (`scripts/windows-detect.sh`), without Claude, in a few seconds: Windows
   version and build, PC name, last shutdown, UEFI or BIOS boot, EFI partition and
   `bootmgfw.efi`, BCD entries and the partition each one points to (an entry pointing to
   no partition of the disk is flagged), WinRE, hibernation or Fast Startup, pending
   update, Automatic Repair log, blue screen dumps, NTFS volume flagged dirty, SMART health.
   Partitions are mounted read-only under `/mnt/windows/`. The report goes into
   `windows/inventory.md` and its summary into the `CLAUDE.md` given to Claude.
3. **Diagnosis with Claude**: symptoms, disk health, extract of the event logs
   (`ctrlz events <folder>`: errors and known events — unexpected reboots, stop codes,
   disk and NTFS errors, WHEA hardware errors, failed services and updates), read-only
   registry (`hivexget`, `reglookup`), `SrtTrail.txt`, recent drivers.
4. **Conclusion** in `windows/diagnostic.md`: evidence, likely cause and how sure it is,
   repairs ordered from the least risky, each with the exact command to type in the
   Windows recovery environment (`chkdsk`, `sfc /offwindir`, `DISM /Image`, `bcdboot`…).
   The person decides and runs them; a backup comes first if the files have none.

The diagnosis needs no destination drive: it can be kept on the key (persistence).

Running the repairs from the key itself is the next step: through the PC's own WinRE
started in a virtual machine, every command batch approved by the person, after a backup.

### Windows mode

From the `CTRL-Z` partition of the key, in PowerShell:

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
creates the release. File names are fixed (`ctrl-z-personal.iso`,
`ctrl-z-business.iso`, `CtrlZInstaller.exe`): the installer and
`make-key.sh` always fetch the latest release.

## Repository layout

```
config/
  business/              Business edition: procedure (CLAUDE.<lang>.md), permissions, settings template
  personal/              Personal edition: procedure and permissions
  windows/               Windows mode: one procedure per edition and language, permissions
hooks/
  log-command.sh         Logs every command Claude runs, with an offline queue
scripts/
  session.sh             Session launcher (the `ctrlz` command)
  firstboot.sh           First boot: installer settings, persistence
  update.sh              git pull + config install (the `ctrlz-update` command)
  lib.sh                 Shared functions (edition, language, settings block, disks)
  ui.sh                  The assistant's menus (whiptail, plain prompts as a fallback)
  windows-detect.sh      Windows diagnosis: read-only inventory of a disk's Windows installations
  windows-inspect.py     Reads registry hives, BCD stores and event logs (read-only)
  bitlocker-open.sh      Opens a BitLocker partition read-only, key read on standard input
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
3. The disk to recover is locked read-only in the kernel (`blockdev --setro`) as soon as
   it is designated: this holds whatever command is run. The lock is lost if the disk is
   unplugged; the procedure tells Claude to check it and set it again.
4. Destructive commands are also blocked in `settings.json` and repeated as managed
   settings (`/etc/claude-code/managed-settings.json`) so that no local setting can lift
   them. These pattern rules are a guard rail, not a hard security boundary: the kernel
   lock above is the real one.
5. No customer data and no token in this repository (see `.gitignore`).
6. A key updates itself from this repository at every session: whoever can push to `main`
   can change the procedure of every key. Protect the branch.
7. A lost business key is revoked in three places: the log-server token, the
   update-repository token, and the Claude account session. Hence the value of an
   encrypted persistence.

## Status

- [x] Procedures for both editions and Windows mode, in English and French
- [x] Logging and sending to the server — tested end to end locally
- [x] Settings block installer → key — tested (written on Windows, read back on Linux)
- [x] Windows installer — builds; copy, settings block, read-back and download resume tested (on a file, and against a server that cuts connections)
- [ ] Windows installer — writing to a real USB key has **never been tried**
- [x] Image build — both editions build in a `debian:trixie` container, and the release workflow has run on GitHub
- [x] Start-up assistant — tested in a virtual machine: menus, disk selection, read-only lock (a direct write is refused, a mount is forced read-only), free-space warning. The Wi-Fi menu was **not** tested (no Wi-Fi in a virtual machine)
- [x] First boot — tested in a virtual machine (QEMU): BIOS and UEFI boot, plain and encrypted persistence, installer settings applied (business edition), second boot with persistence active
- [ ] First boot on a real USB key — **never tried**
- [x] Windows mode — launcher tested on a PC for both editions with a stand-in for Claude (isolated config, log, report, cleanup)
- [ ] Windows mode — a real Claude session on a customer PC has **never been tried**
- [ ] Log server and Forgejo — files ready in `server/`, to be deployed
- [x] Windows diagnosis — launcher tested in a `debian:trixie` container on a fake GPT disk (EFI, MSR, Windows, WinRE, BitLocker): registry hives and BCD built for the test, event logs exported from a real Windows 11 (about 40,000 events read in 2 min 20 s), BitLocker opened read-only with cryptsetup's reference images (recovery key typed with spaces, wrong key refused, password), key found nowhere on disk afterwards, all devices still locked read-only
- [ ] Windows diagnosis — on a real Windows disk, and with a real Claude session, **never tried**; the image has not been rebuilt with the new packages yet

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
