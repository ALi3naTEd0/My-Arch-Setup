# Swap and hibernation

Two routes depending on the filesystem. The **partition** is what's proven on
the Lenovo (16 G on `/dev/nvme0n1p3`); the **btrfs swapfile** is the alternative
when the disk is fully allocated and you can't repartition.

---

## How much swap

| Case | Size |
|---|---|
| Just a safety net behind zram | 8 GiB |
| Normal use (VMs, builds) | 16 GiB |
| **With hibernation** | ≥ RAM, in practice RAM + 10% |

With zram already running, disk swap is a **second tier**, not the first. Give
it a lower priority so the kernel compresses in RAM before going to disk:

```
/swap/swapfile  none  swap  defaults,pri=10  0 0
```

zram usually sits at `pri=100`. Check with `swapon --show`.

> **Full swap ≠ memory pressure.** Look at `/proc/pressure/memory`: if `some`
> and `full` read 0.00, nothing is stalling — those are cold pages the kernel
> evicted and has no reason to bring back. What *is* dangerous is **having no
> second tier**: once zram fills up, the next spike goes straight to the OOM
> killer.

---

## Option A · Partition (proven on the Lenovo)

1. Create the partition with GParted or Partition Manager, format **linux-swap**
2. Activate it: `sudo swapon /dev/nvme0n1p3`
3. Verify: `swapon --show`
4. Add the `resume` hook to `/etc/mkinitcpio.conf`:

```
HOOKS=(base udev autodetect modconf block filesystems resume keyboard fsck)
```

5. Get the partition UUID: `blkid`
6. Add `resume=UUID=…` to `/boot/loader/entries/*.conf`:

```
options root=PARTUUID=… zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs resume=UUID=78acba64-6959-4382-91ca-773199f00af3
```

7. Regenerate: `sudo mkinitcpio -P`
8. Test: `systemctl hibernate`

> Order matters: `resume` goes **after** `filesystems`. And `zswap.enabled=0`
> keeps zswap and zram from fighting each other.

---

## Option B · btrfs swapfile (when there's no room for a partition)

Titan's case: `nvme0n1p1` (1 G `/boot`) + `nvme0n1p2` (952.9 G btrfs) = the
whole disk. Zero unallocated space, and you cannot shrink a mounted btrfs root
without a live USB. btrfs has supported swapfiles since kernel 5.0.

### Dedicated subvolume

At top level, so Timeshift doesn't pull it into snapshots:

```bash
sudo mkdir -p /mnt/btrfs-top
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-top
sudo btrfs subvolume create /mnt/btrfs-top/@swap
sudo umount /mnt/btrfs-top && sudo rmdir /mnt/btrfs-top
```

### fstab

```
UUID=<p2-uuid>  /swap  btrfs  rw,noatime,subvol=/@swap  0 0
/swap/swapfile  none   swap   defaults,pri=10           0 0
```

### Create and activate

```bash
sudo mkdir -p /swap
sudo systemctl daemon-reload
sudo mount /swap
sudo btrfs filesystem mkswapfile --size 16g --uuid clear /swap/swapfile
sudo swapon /swap/swapfile
```

`btrfs filesystem mkswapfile` (btrfs-progs 6.1+) handles **NODATACOW**,
no-compression and preallocation on its own. Done by hand with `fallocate` +
`mkswap`, the `swapon` fails because of CoW and the `zstd` compression inherited
from the mount.

### Hibernation with a swapfile

On top of `resume=UUID=` you also need `resume_offset`:

```bash
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

That number goes as `resume_offset=` in the bootloader options, alongside the
`resume=UUID=` of the **device**, not the file.

---

## Resume that never resumes

Three separate faults, all found on 2026-09-18, all silent. Work through them in
order — each hides the next.

### 1. `resume=` in a boot entry that never boots

The Titan's hibernation wrote its image fine and came back to a cold boot. The
parameter *existed* — in the fallback entry:

```
[..._linux-fallback.conf]
options root=UUID=fdda5cbe-… resume=UUID=71a89f67-… …
```

and that entry was unbootable three ways over: `initrd /boot/intel-ucode.img` on
an **AMD** machine (and at a path that does not exist inside the ESP),
`initrd /initramfs-linux-fallback.img` which the preset never generates
(`PRESETS=('default')`), and a `root=UUID=` matching no partition on the disk.
The entry that actually boots had no `resume=` at all.

```bash
# which entries exist, and what each passes
for f in /boot/loader/entries/*.conf; do echo "[$f]"; grep ^options "$f"; done
blkid -U <the-uuid-in-resume=>      # must resolve to your swap
```

> systemd-boot reads only `*.conf`. HyDE leaves `*.conf.hyde.bkp` siblings in
> that directory; they are inert, not entries.

### 2. The `resume` hook missing from mkinitcpio

Separate machine, separate fault. The HP had no `resume=` **and** no hook:

```
HOOKS=(… block filesystems fsck)          # no resume
```

The hook is what reads `resume=` and hands control to the saved image. Without
it the parameter is inert even when present. It must come after the hook that
provides the swap device (`block`), and adding it needs `mkinitcpio -P`.

### 3. `resume failed (-5)` — the image is there and unreadable

```
PM: hibernation: resume from hibernation
PM: hibernation: resume failed (-5)
```

`-5` is `EIO`. This is **not** "no image found" — the kernel located the
signature and failed reading. With no NVMe errors anywhere in the journal, the
cause was space: the image had been written to a filesystem that could not take
it.

**On an NVIDIA machine the hibernation image is not the only thing being
written.** `nvidia-hibernate.service` dumps video memory to
`NVreg_TemporaryFilePath` (default `/var/tmp`), and it needs **as much free
space as the card has VRAM** — 16 GiB on the Titan's 5060 Ti. That requirement
appears in neither the Arch wiki's hibernation page nor NVIDIA's own README, and
it is what turned a full disk into a failed resume.

```bash
grep -rhs 'TemporaryFilePath' /etc/modprobe.d/ /usr/lib/modprobe.d/
systemctl is-enabled nvidia-{suspend,hibernate,resume}.service   # all three
nvidia-smi --query-gpu=memory.total --format=csv,noheader
```

Point the dump at a disk with room if the root filesystem is tight:

```
# /etc/modprobe.d/nvidia-hibernate.conf
options nvidia NVreg_TemporaryFilePath=/mnt/somewhere-with-space/nvidia-tmp
```

### Confirming it actually worked

A successful resume leaves **no new boot**. `hibernation exit` appears inside the
*same* boot session:

```bash
journalctl -b 0 | grep -E 'hibernation (entry|exit)|resume failed'
journalctl --list-boots | tail -3
```

If a new boot started, it did not resume — whatever the screen showed.

A second, subtler confirmation: after a real resume `/proc/cmdline` shows the
**hibernated** kernel's command line, not the one used to boot into the image.
On the HP that meant `resume=` was still absent from `/proc/cmdline` after a
successful resume, because the kernel that came back had booted before the
parameter was added. Absent there is evidence *for* a resume, not against it.

> A cold boot after a failed resume is not dangerous here: activating swap
> rewrites its header, destroying the stale image. The dangerous shape is
> resuming an image *after* the filesystem has been modified, which needs a
> second OS or a deliberate `swapoff`; it does not happen in this setup.

---

## Checking hibernation is viable

```bash
cat /sys/power/resume          # "0:0" = not configured
grep -o 'resume=[^ ]*' /proc/cmdline
free -h                        # swap must exceed used RAM
```

Security note: the hibernation image contains **all of RAM in the clear**. On an
unencrypted disk that includes any keys and passwords that were in memory. None
of these three disks are encrypted, so a 17 G swap partition on the Titan is a
17 G window onto whatever was in memory at hibernation time.

### Which machine is actually a good candidate

| | RAM | image_size | VRAM dump | total I/O | verdict |
|---|---|---|---|---|---|
| Titan | 31 GiB | 12.3 GiB | **16 GiB** | ~28 GiB | works; took an afternoon and a CMOS clear |
| pavilion | 7.5 GiB | 3.0 GiB | none | ~3 GiB | worked first try |
| nomad | 15 GiB | — | none | — | not configured |

Roughly **nine times** the data to write and read back on the Titan, which is
why it is visibly slower — not the RAM size alone, but the VRAM dump the Intel
machines simply do not have.

> Log timestamps do not measure this. `hibernation entry` → `hibernation exit`
> spans however long the machine sat powered off, so the Titan's "2m58s" and the
> HP's "32s" compare nothing. The data volume is the honest number.

The proprietary NVIDIA driver is what makes the Titan hard: a VRAM dump the size
of the card, three services that must be enabled, and a resume path that fails
opaquely. The Intel machines have none of that.

`systemctl suspend` preserves the session without touching swap, VRAM or
firmware, and is the right default unless you specifically need power-off
persistence.

---

## zram

Already set up by `zram-generator`. Inspect and tune:

```bash
swapon --show
cat /etc/systemd/zram-generator.conf
```

All three machines carry ~4 G of zram. Titan sat at **100%** for days without it
being a problem (memory pressure at 0.00) — but with no second tier, any spike
turns into an OOM. See
[the thumbnailer case](06-troubleshooting.md#session-dies-in-a-loop--oom-from-the-thumbnail-generator).
