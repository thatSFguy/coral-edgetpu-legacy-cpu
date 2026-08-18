# Coral Edge TPU Libraries for Legacy CPUs (SSSE3)

Pre-compiled Google Coral Edge TPU libraries for CPUs that only support
SSE/SSE2/SSSE3 instructions — no SSE4.1, SSE4.2, or AVX required.

## Who This Is For

If you get `Illegal instruction` when trying to use a Google Coral PCIe TPU
on older hardware, this is for you. The official Google prebuilt libraries
require SSE4.2 minimum. These binaries target `-march=bonnell` (Intel Atom
microarchitecture) and work on any x86_64 CPU with SSSE3 support.

## Tested Hardware

- **CPU**: Intel Atom D2700 (Thecus N5550 NAS)
- **OS**: Debian 12 Bookworm (inside Docker container)
- **Kernel**: 6.18.x with patched gasket-dkms
- **Frigate**: 0.17.0

The kernel driver build in [`gasket/`](gasket/) is maintained separately from
the binaries and targets the kernels openmediavault ships today — see
[Kernel driver on openmediavault](#kernel-driver-on-openmediavault).

## PCIe only — USB Coral is not supported by the current binary

The `libedgetpu.so.1.0` committed under `binaries/` was built from bazel's
**PCIe-only** target, so it does not link libusb and cannot see a Coral USB
Accelerator. If you plug one in you get `No EdgeTPU was detected`, with nothing
in the logs to explain why. Confirm for yourself:

```bash
readelf -d binaries/libedgetpu.so.1.0 | grep -c libusb   # 0 = PCIe only
```

A USB-capable build — one library serving both transports, which is upstream's
default for Linux — is produced by
[`.github/workflows/build-libedgetpu.yml`](.github/workflows/build-libedgetpu.yml)
and published as a release asset rather than committed here:

**[libedgetpu-v1.0-usb-beta](https://github.com/thatSFguy/coral-edgetpu-legacy-cpu/releases/tag/libedgetpu-v1.0-usb-beta)**
— `sha256 34043d3dde102ee222c7900f005c623f2e84ac01e47f704c2aae752eb126c28b`

It is built from the same upstream commit as the PCIe-only binary here
(`e35aed18`); only the bazel target differs, so PCIe behaviour is unchanged.
Two independent CI runs produced byte-identical output.

> **USB is untested on real hardware.** The build is gated on linkage,
> glibc and instruction-set checks, but nobody has yet run a USB Coral against
> it. Treat any USB release asset as a beta, and please report results on
> [#1](https://github.com/thatSFguy/coral-edgetpu-legacy-cpu/issues/1).
> The PCIe path is the tested one.

## Check If You Need This

```bash
grep -m1 flags /proc/cpuinfo | tr ' ' '\n' | grep -E 'sse4|avx'
```

If this returns **nothing** — you need these binaries.
If it returns sse4_1, sse4_2, or avx — the official Google binaries will work.

## Prerequisites

1. The **gasket kernel driver** (`/dev/apex_0`). Upstream
   [google/gasket-driver](https://github.com/google/gasket-driver) has not been
   updated since 2024 and no longer compiles on current kernels. Build it with
   the patched DKMS package in this repo:

   ```bash
   git clone https://github.com/thatSFguy/coral-edgetpu-legacy-cpu.git
   cd coral-edgetpu-legacy-cpu
   sudo ./gasket/build-gasket-dkms.sh
   ```

   Verify: `ls /dev/apex_0`

   See [Kernel driver on openmediavault](#kernel-driver-on-openmediavault)
   for details, and for what to do when you switch kernels.

2. Docker with Frigate container

## Installation

### Option A: Volume Mount (Recommended — survives container restarts)

1. Download the binaries:
   ```bash
   mkdir -p /opt/coral-libs
   wget https://github.com/thatSFguy/coral-edgetpu-legacy-cpu/raw/main/binaries/libedgetpu.so.1.0 \
     -O /opt/coral-libs/libedgetpu.so.1.0
   wget https://github.com/thatSFguy/coral-edgetpu-legacy-cpu/raw/main/binaries/_pywrap_tensorflow_interpreter_wrapper.so \
     -O /opt/coral-libs/_pywrap_tensorflow_interpreter_wrapper.so
   ```

2. Add to your Frigate `docker-compose.yml` volumes section:
   ```yaml
   volumes:
     - /opt/coral-libs/libedgetpu.so.1.0:/usr/lib/x86_64-linux-gnu/libedgetpu.so.1.0
     - /opt/coral-libs/_pywrap_tensorflow_interpreter_wrapper.so:/usr/local/lib/python3.11/dist-packages/tflite_runtime/_pywrap_tensorflow_interpreter_wrapper.so
   ```

3. Add Coral detector to Frigate `config.yml`:
   ```yaml
   detectors:
     coral:
       type: edgetpu
       device: pci
   ```

4. Restart Frigate:
   ```bash
   docker compose down && docker compose up -d
   ```

5. Verify in logs:
   ```bash
   docker exec frigate cat /dev/shm/logs/frigate/current | grep -i "tpu\|edgetpu"
   ```
   Should show: `TPU found` with no errors after it.

### Option B: Install Script
```bash
curl -sSL https://raw.githubusercontent.com/thatSFguy/coral-edgetpu-legacy-cpu/main/install/install.sh | bash
```

## Kernel driver on openmediavault

The prebuilt `.so` files in this repo are **userspace** libraries and are
completely independent of the host kernel. What breaks when you move to a newer
kernel is the **gasket driver** — the PCIe kernel module that creates
`/dev/apex_0`. Upstream `google/gasket-driver` was last touched in April 2024
and fails to compile on anything newer than 6.11.

[`gasket/build-gasket-dkms.sh`](gasket/build-gasket-dkms.sh) clones upstream at a
pinned commit, applies
[`gasket/gasket-kernel-compat.patch`](gasket/gasket-kernel-compat.patch), builds
`gasket-dkms_1.0-18_all.deb` and installs it.

```bash
sudo ./gasket/build-gasket-dkms.sh              # build for the running kernel
sudo ./gasket/build-gasket-dkms.sh -k 7.0.0-1-pve  # or for a not-yet-booted one
sudo ./gasket/build-gasket-dkms.sh -b           # build the .deb only
```

### Which kernels openmediavault offers

openmediavault 8 is built on Debian 13 Trixie. The `openmediavault-kernel`
plugin (omv-extras, **System → Kernel**) is what most people use to move off the
stock kernel:

| Source | Menu path | Kernel |
|--------|-----------|--------|
| Debian stock | Debian → Install Debian kernel | 6.12 LTS at Trixie release; newer via `trixie-backports` (7.0, 7.1, …) |
| Proxmox | Proxmox → Install Proxmox kernel | 6.14, 6.17, **7.0** |

Every one of these needs the patch. `no_llseek` was deleted in 6.12, so even the
oldest Debian stock kernel on a fresh openmediavault 8 install fails to build
the upstream driver, and each newer series has added another breakage since.

### What the patch fixes

All four changes are guarded by `LINUX_VERSION_CODE`, so a single patched tree
builds on old and new kernels alike. That matters on openmediavault, where DKMS
rebuilds the module for every installed kernel — typically a Debian kernel and a
Proxmox kernel side by side, plus whatever you boot next.

| Kernel | Upstream breakage | Fix |
|--------|-------------------|-----|
| 6.2 | `dma_buf_map_attachment()` / `dma_buf_unmap_attachment()` began requiring the caller to hold the dma\_buf reservation lock (`dma_resv_assert_held()`) | call the `*_unlocked()` variants |
| 6.12 | `no_llseek` removed — `error: 'no_llseek' undeclared` | drop `.llseek`; a NULL `.llseek` already means `-ESPIPE` |
| 6.13 | symbol namespaces became string literals — `error: expected ',' or ';' before 'DMA_BUF'` | `MODULE_IMPORT_NS("DMA_BUF")` |
| 7.1 | `zap_vma_ptes()` renamed to `zap_special_vma_range()` — `error: implicit declaration of function 'zap_vma_ptes'` | call the new name |

The 6.2 change is a runtime issue rather than a build failure: it only shows up
as a `WARN` splat when a dma-buf is mapped, and only on kernels built with
`CONFIG_DEBUG_MUTEXES` or lockdep. It is fixed here anyway because the
`*_unlocked()` variants are what this call site actually wants.

`build-gasket-dkms.sh` also installs `dh-dkms`, which `debian/rules` needs for
`dh --with dkms`. It used to be part of the `dkms` package; on Debian 12 and 13
it is a separate one, and without it `dpkg-buildpackage` fails before it starts.

### Verified

The patched source was compiled as an out-of-tree module against mainline
kernel trees at each of these tags. `gasket.ko` and `apex.ko` both build with
no errors and no warnings:

| Mainline tag | Corresponds to | Unpatched | Patched |
|--------------|----------------|-----------|---------|
| v6.8  | Proxmox 6.8 (OMV 7 era) | builds | builds |
| v6.12 | Debian 13 stock kernel | fails | builds |
| v6.14 | Proxmox 6.14 | fails | builds |
| v6.17 | Proxmox 6.17 | fails | builds |
| v7.0  | Proxmox 7.0, Debian backports 7.0 | fails | builds |
| v7.1  | Debian backports 7.1 | fails | builds |

The `.deb` was also built end to end from a clean checkout.

Proxmox kernels carry their own patch stack on top of mainline, so this is a
strong signal rather than a guarantee, and it is a compile-and-package check
either way — runtime testing needs Coral hardware. **No kernel above 6.18 has
been run against an actual Coral yet.** If you boot 6.17, 7.0 or 7.1 with this
patch, please report back in an issue either way.

### Kernel headers

The build needs headers for the target kernel. The plugin installs them
alongside the kernel, but if `/lib/modules/$(uname -r)/build` is missing:

```bash
# Proxmox kernel — or use System → Kernel → Proxmox → Install Proxmox kernel
sudo apt-get install proxmox-headers-$(uname -r | cut -d. -f1,2)

# Debian stock kernel — or System → Kernel → Debian → Install Debian kernel headers
sudo apt-get install linux-headers-amd64
```

`gasket-dkms` upstream hard-depends on a Debian-flavoured
`linux-headers-*` package, which Proxmox's `proxmox-headers-X.Y` does not
reliably satisfy. The script demotes that to a `Recommends:` after verifying
real headers are present on disk, so the install does not fail on a
Proxmox-only system.

### Switching kernels later

`dkms.conf` ships `AUTOINSTALL="YES"`, so installing a new kernel through the
plugin rebuilds gasket for it automatically — as long as the matching headers
package is installed. To build for a kernel you have installed but not booted:

```bash
sudo dkms install -m gasket -v 1.0 -k 7.0.0-1-pve
```

After a reboot, confirm with `ls -l /dev/apex_0` and `lsmod | grep apex`.

### Secure Boot

DKMS modules are unsigned by default. With Secure Boot on, the kernel refuses to
load `gasket` and `apex` and `/dev/apex_0` never appears — `dmesg` shows
`Key was rejected by service`. Either enroll a MOK for DKMS signing or turn
Secure Boot off in the BIOS. The script warns if it detects Secure Boot enabled.

### If `/dev/apex_0` still does not appear

```bash
lspci -nn | grep 1ac1:089a     # is the card visible at all?
lsmod | grep -E 'gasket|apex'  # did the modules load?
dmesg | grep -iE 'gasket|apex' # what did they say?
dkms status gasket             # did DKMS build for this kernel?
```

A card that shows up in `lspci` but produces no `/dev/apex_0`, with
`apex 0000:0X:00.0: Error in ndev_init` or PCIe link errors in `dmesg`, is
usually the well-known Coral ASPM problem rather than a driver-build problem.
Try booting with `pcie_aspm=off` (add it to `GRUB_CMDLINE_LINUX_DEFAULT` in
`/etc/default/grub`, then `update-grub`).

## Build Details

| Component | Version | Source |
|-----------|---------|--------|
| libedgetpu | master @ e35aed1 | https://github.com/google-coral/libedgetpu |
| libedgetpu bazel target | `libedgetpu_direct_pci.so` (**PCIe only, no USB**) | - |
| tflite_runtime | 2.17.1 | https://github.com/tensorflow/tensorflow @ v2.17.1 |
| Build container | debian:bookworm | Debian 12 Bookworm |
| glibc | 2.36 | Debian 12 Bookworm |
| Python | 3.11 | - |
| Compiler flags | `-march=bonnell -mno-sse4.1 -mno-sse4.2 -mno-avx -mno-avx2` | - |

These are built against Debian 12's glibc 2.36 and Python 3.11 because that is
what the **Frigate container** ships — not what the host runs. They are mounted
into the container and loaded by its Python, so the host's distribution, glibc
and kernel do not come into it. Running openmediavault 8 (Debian 13 Trixie,
glibc 2.41, Python 3.13) on a 7.0 kernel changes nothing for these files; only
the [gasket driver](#kernel-driver-on-openmediavault) has to track the kernel.

If you want to use them *outside* a container, on the openmediavault host
itself, that is where the glibc and Python versions above start to matter and a
rebuild is likely needed.

## Compatibility

| CPU Generation | SSE Support | Works? |
|---------------|-------------|--------|
| Intel Atom (Bonnell/Saltwell) | SSE, SSE2, SSSE3 | ✅ Yes |
| Intel Core 2 (pre-2010) | SSE, SSE2, SSSE3 | ✅ Yes |
| Intel Nehalem+ (2010+) | SSE4.1, SSE4.2 | Use official binaries |
| Intel Sandy Bridge+ (2011+) | AVX | Use official binaries |

## Frigate Version Compatibility

These binaries are compiled for **Frigate 0.17.0** (tflite_runtime 2.17.1).
If Frigate updates and changes its tflite_runtime version, a rebuild will be needed.

## Related Issues

These GitHub issues describe the problem this solves:
- https://github.com/google-coral/edgetpu/issues/808
- https://github.com/google/gasket-driver/issues/55
- https://github.com/blakeblackshear/frigate/discussions/5932

## License

- libedgetpu: Apache 2.0 (https://github.com/google-coral/libedgetpu/blob/master/LICENSE)
- tflite_runtime: Apache 2.0 (https://github.com/tensorflow/tensorflow/blob/master/LICENSE)
