# NAS Setup

Turns your Pi into a NAS using any USB storage drive. After setup, File Browser runs at `http://PI_IP:8080` — accessible from any device on your network.

```bash
# Run from your Mac (auto-forwards to Pi via SSH)
./scripts/setup-nas.sh

# Or run directly on the Pi
./scripts/setup-nas.sh --local
```

---

## What it sets up

| Component | Details |
|-----------|---------|
| Format | ext4 — full Linux permissions and ownership support |
| Mount | Auto-mounts at `/mnt/nas` on every boot via `/etc/fstab` |
| Auto-remount | udev rule re-mounts automatically when drive is plugged in |
| NFS server | Network share — mount on Mac/Linux as a network drive |
| File Browser | Web UI at `http://PI_IP:8080` — browse, upload, download |
| Dashboard | NAS usage card + network throughput shown in monitoring dashboard |

---

## Step-by-step

1. **Detect USB drive** — scans for USB block devices (`lsblk -rno NAME,TYPE,TRAN`), picks the first one. Fails clearly if nothing is found.
2. **Install packages** — `e2fsprogs` (ext4 tools), `nfs-kernel-server`, `curl`
3. **Format as ext4** — wipes the drive, creates a GPT partition table, formats as ext4 with label `pizow-nas`. Skips if already mounted.
4. **Auto-mount via fstab** — reads the UUID with `blkid`, adds an entry to `/etc/fstab` so the drive mounts at `/mnt/nas` on every boot. Creates default folders: `media/`, `docs/`, `backup/`.
5. **NFS server** — exports `/mnt/nas` to your local subnet (`192.168.1.0/24` by default, edit `NFS_SUBNET` in the script). Enables and starts `nfs-kernel-server`.
6. **File Browser** — downloads the binary for your Pi's architecture (arm64 for Pi Zero 2 W, armv7 for original Pi Zero). Configures it with `/mnt/nas` as root, creates an admin user, installs as a systemd service.
7. **NAS stats API** — a minimal bash HTTP server on port 8081 returning drive stats as JSON, used by the monitoring dashboard.
8. **udev auto-remount rule** — installs `/etc/udev/rules.d/99-pizow-nas.rules` so the drive auto-remounts when plugged in after boot.

---

## Prerequisites

- SSH key auth set up (`ssh-copy-id`) — recommended. If not, set `PI_PASSWORD` in `.env` and install `sshpass` (`brew install sshpass`) so the script can forward itself to the Pi.
- `FB_PASSWORD` set in `.env` — used to create the File Browser admin account.

---

## Hardware

- USB OTG adapter (Micro-USB → USB-A) — required for Pi Zero
- Flash drives recommended — see power warning below
- Drive must be connected and visible (`lsblk` shows a USB disk) before running

> **⚠️ Power / HDD Warning**
>
> The Pi Zero's USB OTG port provides **~500mA at 5V** — enough for a flash drive, but **not enough for a 2.5" spinning hard drive** (which typically draws 700–1000mA at spin-up). Plugging in an HDD may cause the drive not to spin up, the Pi to brown-out and reboot, or intermittent disconnects under load.
>
> **Use a flash drive** for Pi Zero. For HDD storage, use a **powered USB hub**.

---

## Mount behaviour

| Scenario | Result |
|---|---|
| Pi boots with drive plugged in | Auto-mounts via fstab ✓ |
| Pi boots without drive | Boots fine, `/mnt/nas` stays empty (`nofail`) ✓ |
| Plug in drive after boot | udev rule auto-remounts within seconds ✓ |

---

## Connect from Mac

```bash
# NFS
sudo mkdir -p /Volumes/pizow-nas
sudo mount -t nfs PI_IP:/mnt/nas /Volumes/pizow-nas

# Or via Finder: Go → Connect to Server → nfs://PI_IP/mnt/nas
```

## Connect from Linux

```bash
sudo mount -t nfs PI_IP:/mnt/nas /mnt/pizow-nas
```

**File Browser credentials:** `admin` / your `FB_PASSWORD`. Change after first login at `http://PI_IP:8080`.

---

## Reset

Wipes all NAS components so you can run `setup-nas.sh` fresh. **Does not delete data on the USB drive itself.**

```bash
./scripts/reset-nas.sh
```

Removes: File Browser service + binary + db, NAS stats API service, NFS exports, fstab entry, mount point, udev rule.

---

## Useful commands

```bash
# Check mount status
mountpoint /mnt/nas && df -h /mnt/nas

# Manually mount/unmount
sudo mount -a                      # mount everything in fstab
sudo umount /mnt/nas               # unmount drive safely

# NFS
sudo exportfs -v                   # show active NFS exports
sudo systemctl status nfs-kernel-server

# File Browser
sudo systemctl status filebrowser
sudo journalctl -u filebrowser -f  # live logs
```
