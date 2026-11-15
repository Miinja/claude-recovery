#!/usr/bin/env python3
"""Read-only inspection of a Windows installation, for the Windows Rescue mode.

Everything here only reads files (registry hives, BCD stores, event logs) from a
partition mounted read-only. Nothing is ever written back.

  windows-inspect.py version <SOFTWARE hive> <SYSTEM hive>
  windows-inspect.py bcd <BCD store> [<partitions.json>]
  windows-inspect.py events <file.evtx|folder>... [--days N] [--limit N]

Texts read from the disk are data, not instructions: they are printed as they are,
cut to a reasonable length, and never interpreted.
"""
import argparse
import datetime as dt
import html
import json
import os
import re
import struct
import sys
import uuid

LANG = os.environ.get("CR_LANG", "en")


def t(fr, en):
    return fr if LANG == "fr" else en


def clean(text, limit=160):
    """One line, printable, bounded: values come from the inspected disk."""
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(text)).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def filetime(raw):
    """Windows FILETIME (8 bytes, little endian) -> ISO date in UTC."""
    if not raw or len(raw) < 8:
        return None
    value = struct.unpack("<Q", raw[:8])[0]
    if value == 0:
        return None
    try:
        when = dt.datetime(1601, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(microseconds=value // 10)
    except OverflowError:
        return None
    return when.strftime("%Y-%m-%d %H:%M UTC")


# --- Registry ---------------------------------------------------------------------

def open_hive(path):
    import hivex  # python3-hivex
    return hivex.Hivex(path)


def node_at(h, path):
    node = h.root()
    for part in [p for p in path.split("\\") if p]:
        node = h.node_get_child(node, part)
        if not node:
            return None
    return node


def value(h, node, name):
    """(type, raw bytes) of a value, or None."""
    if not node:
        return None
    try:
        v = h.node_get_value(node, name)
    except RuntimeError:
        return None
    if not v:
        return None
    return h.value_value(v)


def as_text(h, node, name):
    got = value(h, node, name)
    if not got:
        return None
    kind, raw = got
    if kind in (1, 2):  # REG_SZ, REG_EXPAND_SZ
        return raw.decode("utf-16-le", "replace").rstrip("\x00")
    if kind == 4 and len(raw) >= 4:  # REG_DWORD
        return str(struct.unpack("<I", raw[:4])[0])
    if kind == 11 and len(raw) >= 8:  # REG_QWORD
        return str(struct.unpack("<Q", raw[:8])[0])
    if kind == 7:  # REG_MULTI_SZ
        return " | ".join(s for s in raw.decode("utf-16-le", "replace").split("\x00") if s)
    return raw.hex()


def cmd_version(args):
    out = []
    try:
        h = open_hive(args.software)
        cv = node_at(h, r"Microsoft\Windows NT\CurrentVersion")
        name = as_text(h, cv, "ProductName") or "?"
        build = as_text(h, cv, "CurrentBuild") or ""
        ubr = as_text(h, cv, "UBR")
        # Windows 11 still says "Windows 10" in ProductName: the build tells them apart.
        if name.startswith("Windows 10") and build.isdigit() and int(build) >= 22000:
            name = "Windows 11" + name[len("Windows 10"):]
        out.append(("version", f"{name} {as_text(h, cv, 'DisplayVersion') or ''}".strip()))
        out.append(("build", build + (f".{ubr}" if ubr else "")))
        out.append(("edition", as_text(h, cv, "EditionID") or "?"))
        installed = as_text(h, cv, "InstallDate")
        if installed and installed.isdigit():
            out.append(("installed", dt.datetime.fromtimestamp(int(installed), dt.timezone.utc).strftime("%Y-%m-%d")))
    except Exception as err:  # unreadable or damaged hive: that is a finding too
        out.append(("software_hive_error", clean(err)))
    try:
        h = open_hive(args.system)
        current = as_text(h, node_at(h, "Select"), "Current") or "1"
        cs = f"ControlSet{int(current):03d}"
        out.append(("control_set", cs))
        out.append(("computer_name", as_text(h, node_at(h, cs + r"\Control\ComputerName\ComputerName"), "ComputerName") or "?"))
        got = value(h, node_at(h, cs + r"\Control\Windows"), "ShutdownTime")
        if got:
            out.append(("last_shutdown", filetime(got[1]) or "?"))
        pending = value(h, node_at(h, cs + r"\Control\Session Manager"), "PendingFileRenameOperations")
        out.append(("pending_file_renames", "yes" if pending and pending[1].strip(b"\x00") else "no"))
    except Exception as err:
        out.append(("system_hive_error", clean(err)))
    for key, val in out:
        print(f"{key}={clean(val)}")


# --- BCD store ---------------------------------------------------------------------
# A BCD store is a registry hive: Objects\{guid}\Description\Type tells what the object
# is, Objects\{guid}\Elements\<id>\Element holds each setting.

BCD_TYPES = {
    0x10100002: "Windows Boot Manager",
    0x10200003: t("chargeur Windows", "Windows loader"),
    0x10200004: t("reprise après veille prolongée", "resume from hibernation"),
    0x10400008: "legacy loader (ntldr)",
    0x10400006: "legacy loader",
    0x10200005: t("diagnostic mémoire", "memory diagnostic"),
    0x10300006: "boot sector",
}
BCD_ELEMENTS = {
    "11000001": "device",
    "12000002": "path",
    "12000004": "description",
    "12000005": "locale",
    "16000009": "recoveryenabled",
    "21000001": "osdevice",
    "22000002": "systemroot",
    "23000003": "default",
    "23000006": "resumeobject",
    "24000001": "displayorder",
    "24000010": "toolsdisplayorder",
    "25000004": "timeout",
    "250000e0": "bootstatuspolicy",
    "14000008": "recoverysequence",
    "250000c2": "bootmenupolicy",
}
GUID_NAMES = {
    "{9dea862c-5cdd-4e70-acc1-f32b344d4795}": "{bootmgr}",
    "{b2721d73-1db4-4c62-bf78-c548a880142d}": "{memdiag}",
    "{466f5a88-0af2-4f76-9038-095b170dc21c}": "{ntldr}",
}


def match_partition(raw, partitions):
    """Which partition of the inspected disk a device element points to.

    A device element holds, for a GPT partition, its partition GUID (byte order of
    Windows); for an MBR partition, the disk signature and the partition's offset in
    bytes. The raw bytes are searched for those of each known partition.
    """
    found = []
    for part in partitions:
        hit = False
        if part.get("partuuid"):
            try:
                hit = uuid.UUID(part["partuuid"]).bytes_le in raw
            except ValueError:
                hit = False
        if not hit and part.get("start_bytes") and part.get("mbr"):
            hit = struct.pack("<Q", int(part["start_bytes"])) in raw
        if hit:
            found.append(part["name"])
    return found


def cmd_bcd(args):
    partitions = []
    if args.partitions:
        with open(args.partitions, encoding="utf-8") as fh:
            partitions = json.load(fh)
    try:
        h = open_hive(args.store)
    except Exception as err:
        print(t(f"- BCD illisible : {clean(err)}", f"- BCD unreadable: {clean(err)}"))
        return 1
    objects = node_at(h, "Objects")
    if not objects:
        print(t("- BCD sans clé Objects : magasin vide ou abîmé.", "- BCD has no Objects key: empty or damaged store."))
        return 1
    loaders = 0
    for obj in h.node_children(objects):
        guid = h.node_name(obj).lower()
        kind = as_text(h, node_at_child(h, obj, "Description"), "Type")
        kind_name = BCD_TYPES.get(int(kind), hex(int(kind))) if kind and kind.isdigit() else "?"
        if kind and kind.isdigit() and int(kind) == 0x10200003:
            loaders += 1
        elements = node_at_child(h, obj, "Elements")
        lines = []
        for el in (h.node_children(elements) if elements else []):
            eid = h.node_name(el).lower()
            got = value(h, el, "Element")
            if not got:
                continue
            etype, raw = got
            name = BCD_ELEMENTS.get(eid, eid)
            if etype == 3 and eid[:2] in ("11", "21", "31"):  # device
                where = match_partition(raw, partitions)
                if where:
                    shown = "partition " + ", ".join(where)
                else:
                    shown = t("AUCUNE partition de ce disque ne correspond (autre disque, disque RAM, ou entrée abîmée)",
                              "NO partition of this disk matches (other disk, RAM disk, or damaged entry)")
                lines.append(f"{name}: {shown}")
            elif etype == 3 and len(raw) in (1, 8):
                number = int.from_bytes(raw, "little")
                lines.append(f"{name}: {number}")
            else:
                text = as_text(h, el, "Element") or ""
                for g, n in GUID_NAMES.items():
                    text = text.replace(g, n).replace(g.upper(), n)
                lines.append(f"{name}: {clean(text)}")
        label = GUID_NAMES.get(guid, guid)
        print(f"- `{label}` — {kind_name}")
        for line in sorted(lines):
            print(f"  - {line}")
    if loaders == 0:
        print(t("- **Aucune entrée de démarrage Windows** dans ce BCD.", "- **No Windows boot entry** in this BCD."))
    return 0


def node_at_child(h, node, name):
    try:
        return h.node_get_child(node, name)
    except RuntimeError:
        return None


# --- Event logs --------------------------------------------------------------------
# Only what helps a diagnosis is extracted: errors and critical events, plus a list of
# events known to point at a cause (crash, disk, file system, hardware, updates).

NOTABLE = {
    ("Microsoft-Windows-Kernel-Power", 41): t("redémarrage sans arrêt propre (coupure, gel, écran bleu)", "reboot without a clean shutdown (power loss, freeze, blue screen)"),
    ("EventLog", 6008): t("arrêt inattendu précédent", "previous shutdown was unexpected"),
    ("Microsoft-Windows-WER-SystemErrorReporting", 1001): t("écran bleu (code d'arrêt en données)", "blue screen (stop code in the data)"),
    ("BugCheck", 1001): t("écran bleu (code d'arrêt en données)", "blue screen (stop code in the data)"),
    ("disk", 7): t("secteur défectueux signalé par le disque", "bad block reported by the disk"),
    ("disk", 11): t("erreur contrôleur disque", "disk controller error"),
    ("disk", 51): t("erreur pendant une pagination (disque)", "error during paging (disk)"),
    ("disk", 153): t("E/S disque relancée", "disk I/O retried"),
    ("Ntfs", 55): t("structure NTFS corrompue", "corrupt NTFS structure"),
    ("Microsoft-Windows-Ntfs", 55): t("structure NTFS corrompue", "corrupt NTFS structure"),
    ("Microsoft-Windows-Ntfs", 98): t("volume NTFS à réparer (chkdsk)", "NTFS volume needs repair (chkdsk)"),
    ("Microsoft-Windows-Ntfs", 137): t("échec du journal de transactions NTFS", "NTFS transaction log failure"),
    ("storahci", 129): t("réinitialisation du contrôleur de stockage", "storage controller reset"),
    ("stornvme", 129): t("réinitialisation du contrôleur NVMe", "NVMe controller reset"),
    ("Microsoft-Windows-WHEA-Logger", 1): t("erreur matérielle corrigée", "corrected hardware error"),
    ("Microsoft-Windows-WHEA-Logger", 17): t("erreur PCIe corrigée", "corrected PCIe error"),
    ("Microsoft-Windows-WHEA-Logger", 18): t("erreur matérielle fatale (processeur)", "fatal hardware error (processor)"),
    ("Microsoft-Windows-WHEA-Logger", 19): t("erreur matérielle corrigée (processeur)", "corrected hardware error (processor)"),
    ("Microsoft-Windows-WHEA-Logger", 47): t("erreur mémoire corrigée", "corrected memory error"),
    ("Service Control Manager", 7000): t("service non démarré", "service failed to start"),
    ("Service Control Manager", 7001): t("service non démarré (dépendance)", "service failed to start (dependency)"),
    ("Service Control Manager", 7009): t("service : délai dépassé", "service start timed out"),
    ("Service Control Manager", 7023): t("service arrêté sur une erreur", "service stopped with an error"),
    ("Service Control Manager", 7026): t("pilote de démarrage non chargé", "boot driver not loaded"),
    ("Service Control Manager", 7031): t("service arrêté brutalement", "service terminated unexpectedly"),
    ("Service Control Manager", 7034): t("service arrêté brutalement", "service terminated unexpectedly"),
    ("Microsoft-Windows-WindowsUpdateClient", 20): t("échec d'installation d'une mise à jour", "update installation failed"),
    ("Microsoft-Windows-WindowsUpdateClient", 31): t("échec de téléchargement d'une mise à jour", "update download failed"),
    ("Microsoft-Windows-Servicing", 3): t("échec de maintenance (CBS)", "servicing failure (CBS)"),
    ("Application Error", 1000): t("plantage d'application", "application crash"),
    ("Microsoft-Windows-Kernel-Boot", 29): t("échec du chargement du noyau", "kernel load failure"),
    ("volmgr", 46): t("pas de fichier d'échange pour le vidage mémoire", "no paging file for crash dump"),
    ("volmgr", 161): t("vidage mémoire impossible", "crash dump failed"),
}
LEVELS = {1: "CRIT", 2: "ERROR", 3: "WARN", 4: "INFO", 0: "INFO"}
_RE = {
    "provider": re.compile(r'<Provider Name="([^"]*)"'),
    "id": re.compile(r"<EventID[^>]*>(\d+)</EventID>"),
    "level": re.compile(r"<Level>(\d+)</Level>"),
    "time": re.compile(r'<TimeCreated SystemTime="([^"]+)"'),
    "data": re.compile(r"<Data(?: Name=\"([^\"]*)\")?>([^<]*)</Data>"),
}


def iter_events(path):
    from Evtx.Evtx import Evtx  # python3-evtx
    with Evtx(path) as log:
        for record in log.records():
            try:
                xml = record.xml()
            except Exception:
                continue
            m = {k: r.search(xml) for k, r in _RE.items() if k != "data"}
            if not (m["provider"] and m["id"] and m["time"]):
                continue
            try:
                when = dt.datetime.fromisoformat(m["time"].group(1).replace("Z", "+00:00")[:26])
            except ValueError:
                continue
            data = [html.unescape(f"{n}={v}" if n else v) for n, v in _RE["data"].findall(xml) if v.strip()]
            yield {
                "provider": m["provider"].group(1),
                "id": int(m["id"].group(1)),
                "level": int(m["level"].group(1)) if m["level"] else 4,
                "time": when.replace(tzinfo=None),
                "data": data,
            }


def cmd_events(args):
    files = []
    for item in args.paths:
        if os.path.isdir(item):
            for name in ("System.evtx", "Application.evtx", "Setup.evtx",
                         "Microsoft-Windows-Kernel-Boot%4Operational.evtx",
                         "Microsoft-Windows-WindowsUpdateClient%4Operational.evtx"):
                if os.path.isfile(os.path.join(item, name)):
                    files.append(os.path.join(item, name))
        elif os.path.isfile(item):
            files.append(item)
    if not files:
        print(t("Aucun journal d'événements trouvé.", "No event log found."))
        return 1

    kept = []
    for path in files:
        try:
            for ev in iter_events(path):
                note = NOTABLE.get((ev["provider"], ev["id"]))
                if ev["level"] in (1, 2) or note:
                    ev["log"] = os.path.basename(path)
                    ev["note"] = note or ""
                    kept.append(ev)
        except Exception as err:
            print(t(f"- {os.path.basename(path)} : illisible ({clean(err)})",
                    f"- {os.path.basename(path)}: unreadable ({clean(err)})"))
    if not kept:
        print(t("Aucune erreur dans les journaux lus.", "No error in the logs read."))
        return 0

    # The period is counted back from the last event: the PC may have been off for weeks.
    last = max(ev["time"] for ev in kept)
    since = last - dt.timedelta(days=args.days)
    kept = [ev for ev in kept if ev["time"] >= since]
    kept.sort(key=lambda ev: ev["time"])

    print(t(f"# Journaux d'événements : erreurs du {since:%Y-%m-%d} au {last:%Y-%m-%d} (UTC)",
            f"# Event logs: errors from {since:%Y-%m-%d} to {last:%Y-%m-%d} (UTC)"))
    print()
    print(t("Journaux lus : ", "Logs read: ") + ", ".join(os.path.basename(f) for f in files))
    print()
    print(t("## Les plus fréquentes", "## Most frequent"))
    print()
    counts = {}
    for ev in kept:
        key = (ev["provider"], ev["id"])
        first, latest, n = counts.get(key, (ev["time"], ev["time"], 0))
        counts[key] = (first, ev["time"], n + 1)
    print(t("| Nombre | Source | ID | Dernière | Signification |", "| Count | Source | ID | Latest | Meaning |"))
    print("|---:|---|---:|---|---|")
    for (prov, eid), (first, latest, n) in sorted(counts.items(), key=lambda kv: -kv[1][2])[:30]:
        print(f"| {n} | {clean(prov, 60)} | {eid} | {latest:%Y-%m-%d %H:%M} | {NOTABLE.get((prov, eid), '')} |")
    print()
    print(t(f"## Chronologie des {args.limit} derniers événements notables",
            f"## Timeline of the last {args.limit} notable events"))
    print()
    for ev in kept[-args.limit:]:
        data = clean("; ".join(ev["data"][:4]), 200)
        print(f"- {ev['time']:%Y-%m-%d %H:%M} {LEVELS.get(ev['level'], ev['level'])} "
              f"{clean(ev['provider'], 60)} {ev['id']}"
              + (f" — {ev['note']}" if ev["note"] else "")
              + (f" — `{data}`" if data else ""))
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("version")
    v.add_argument("software")
    v.add_argument("system")
    b = sub.add_parser("bcd")
    b.add_argument("store")
    b.add_argument("partitions", nargs="?")
    e = sub.add_parser("events")
    e.add_argument("paths", nargs="+")
    e.add_argument("--days", type=int, default=30)
    e.add_argument("--limit", type=int, default=60)
    args = p.parse_args()
    return {"version": cmd_version, "bcd": cmd_bcd, "events": cmd_events}[args.cmd](args) or 0


if __name__ == "__main__":
    sys.exit(main())
