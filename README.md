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

## Check If You Need This

```bash
grep -m1 flags /proc/cpuinfo | tr ' ' '\n' | grep -E 'sse4|avx'
```

If this returns **nothing** — you need these binaries.
If it returns sse4_1, sse4_2, or avx — the official Google binaries will work.

## Prerequisites

1. Install gasket driver (kernel module for Coral PCIe):
   - For modern kernels (6.4+), use the patched version: https://github.com/google/gasket-driver
   - Apply these patches for kernel 6.18+:
     ```bash
     sed -i -e 's/no_llseek/noop_llseek/g' gasket_core.c
     sed -i -e 's/MODULE_IMPORT_NS(DMA_BUF)/MODULE_IMPORT_NS("DMA_BUF")/g' gasket_page_table.c
     sed -i 's/^[[:space:]]*\.llseek[[:space:]]*=[[:space:]]*no_llseek,[[:space:]]*$//' gasket_core.c
     dpkg-buildpackage -us -uc -tc -b
     sudo dpkg -i ../gasket-dkms_1.0-18_all.deb
     ```
   - Verify: `ls /dev/apex_0`

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

## Build Details

| Component | Version | Source |
|-----------|---------|--------|
| libedgetpu | master @ e35aed1 | https://github.com/google-coral/libedgetpu |
| tflite_runtime | 2.17.1 | https://github.com/tensorflow/tensorflow @ v2.17.1 |
| Build container | debian:bookworm | Debian 12 Bookworm |
| glibc | 2.36 | Debian 12 Bookworm |
| Python | 3.11 | - |
| Compiler flags | `-march=bonnell -mno-sse4.1 -mno-sse4.2 -mno-avx -mno-avx2` | - |

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
