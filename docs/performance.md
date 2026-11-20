# Performance Tuning

The images come tuned for gaming, but a few settings belong to the host kernel. They affect every program on the machine and stay after a container stops, so the containers never change them for you. This guide walks you through setting them yourself.

Run every command on the host that runs Docker.

## Checklist

| Setting                                         | Who needs it                                       | Worth it?                    |
| ----------------------------------------------- | -------------------------------------------------- | ---------------------------- |
| [Memory map limit](#memory-map-limit)           | Hosts where the limit is below 1048576             | Yes, if it is low            |
| [NTSync](#ntsync)                               | Anyone playing Windows games through Proton        | Yes, on Linux 6.14 or newer  |
| [Split-lock mitigation](#split-lock-mitigation) | Intel CPUs, only if the kernel log shows game hits | Only when a game is affected |
| [CPU power profile](#cpu-power-profile)         | Hosts that save power by default                   | Optional, costs power        |

## Memory Map Limit

Some games (Counter-Strike 2, Hogwarts Legacy, DayZ and others) need more memory maps than older defaults allow, and crash on launch or after loading without it. Most current distros already ship a high enough limit, but older releases may not.

**Check:**

```bash
sysctl vm.max_map_count
```

If it prints `1048576` or more, skip this section.

**Apply:**

```bash
echo "vm.max_map_count = 1048576" | sudo tee /etc/sysctl.d/80-gow-max-map-count.conf
sudo sysctl --system
```

Run the check again; it should now print `1048576`. The file keeps the setting across reboots.

**Undo:** `sudo rm /etc/sysctl.d/80-gow-max-map-count.conf` and reboot.

## NTSync

NTSync is a kernel driver that lets Wine handle Windows thread synchronization the way Windows does. Proton 11 and GE-Proton 10-10 or newer use it automatically when `/dev/ntsync` exists in the container, with no launch options. It can help CPU-heavy games, and fixes some that misbehave with the older esync and fsync.

You need Linux 6.14 or newer on the host.

### 1. Make sure the host has the device

```bash
ls -l /dev/ntsync
```

You want to see `crw-rw-rw-`. If the file is missing, load the driver and keep it loaded across reboots:

```bash
sudo modprobe ntsync
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf
```

If the permissions show `crw-------` instead, let regular users open it (systemd 257 and newer already do this):

```bash
echo 'KERNEL=="ntsync", MODE="0666"' | sudo tee /etc/udev/rules.d/70-ntsync.rules
sudo udevadm control --reload
sudo udevadm trigger --name-match=ntsync
```

### 2. Add it to the app in Wolf

In the app's entry in Wolf's `config.toml`, add the device next to anything already there:

```toml
devices = ["/dev/ntsync"]
```

Docker refuses to start a container with a device the host doesn't have. Only add this line once step 1 shows the device.

### 3. Confirm games use it

Start a Windows game, then on the Docker host:

```bash
docker ps --format '{{.Names}}'                # find the app container
docker exec <container> sh -c 'ls -l /proc/*/fd 2>/dev/null | grep -c ntsync'
```

A number above `0` means the game opened NTSync. `0` means it fell back, usually because the game uses an older Proton. Pick Proton 11 or newer in the game's Steam properties under Compatibility.

If one game misbehaves with NTSync, add `PROTON_NO_NTSYNC=1 %command%` to that game's launch options.

## Split-Lock Mitigation

Applies to Intel CPUs only. When a program performs a "split lock", Intel CPUs briefly stall every core, so the kernel deliberately slows that program down as punishment. A few Windows games do this constantly and drop to a stuttering mess.

**Check if your CPU is affected:**

```bash
grep -m1 -o split_lock_detect /proc/cpuinfo
```

No output means it doesn't apply (all AMD CPUs, older Intel CPUs); skip this section.

**Check if a game is affected:** play the game that stutters, then run:

```bash
sudo dmesg | grep -i "split lock"
```

Lines like `x86/split lock detection: #AC: Game.exe/4242 took a split_lock trap` mean the kernel is slowing that game down. No lines means this setting won't help.

**Apply** only if you saw those lines:

```bash
echo "kernel.split_lock_mitigate = 0" | sudo tee /etc/sysctl.d/80-gow-split-lock.conf
sudo sysctl --system
```

The cost: any program, not just games, can now stall the whole CPU without being slowed down. Fine on a gaming machine; think twice on a host shared with other people's workloads.

**Undo:** `sudo rm /etc/sysctl.d/80-gow-split-lock.conf` and reboot.

## CPU Power Profile

Many servers and laptops default to a power-saving CPU profile, which ramps clocks up slowly and can cost frame-time stability. Check what the CPU uses:

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
```

If either prints `powersave` or `power`/`balance_power`, switch to performance with your distro's tool. With `power-profiles-daemon` (most desktop distros):

```bash
powerprofilesctl set performance
```

On servers, `tuned-adm profile latency-performance` (from the `tuned` package) does the same and persists. The cost is higher idle power draw and heat.

## What The Images Already Do

You don't need to configure these:

- Raise the open-file limit to the container's hard limit (at most 524288), which Proton and large game downloads need.
- Give gamescope higher CPU priority when the app's profile grants `SYS_NICE`.
- Follow the stream's refresh rate instead of a fixed 60 Hz.
