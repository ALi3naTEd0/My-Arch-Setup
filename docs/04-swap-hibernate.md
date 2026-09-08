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

## Checking hibernation is viable

```bash
cat /sys/power/resume          # "0:0" = not configured
grep -o 'resume=[^ ]*' /proc/cmdline
free -h                        # swap must exceed used RAM
```

Security note: the hibernation image contains **all of RAM in the clear**. On an
unencrypted disk that includes any keys and passwords that were in memory.

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
