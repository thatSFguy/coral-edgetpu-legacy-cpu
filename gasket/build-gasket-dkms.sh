#!/bin/bash
#
# Build and install gasket-dkms (the Coral PCIe/M.2 kernel driver) on
# openmediavault, patched for modern kernels.
#
# Usage:
#   sudo ./build-gasket-dkms.sh [-k KERNEL_VERSION] [-r GASKET_REF] [-b]
#
#   -k KERNEL_VERSION  Kernel to build for (default: the running kernel).
#                      Use this right after installing a new Proxmox kernel
#                      but before rebooting, e.g. -k 7.0.0-1-pve.
#   -r GASKET_REF      git ref of google/gasket-driver (default: pinned commit).
#   -b                 Build the .deb only, do not install it.
#
set -euo pipefail

GASKET_REPO="https://github.com/google/gasket-driver.git"
GASKET_REF="5815ee3908a46a415aac616ac7b9aedcb98a504c"
KVER="$(uname -r)"
INSTALL=1
OUTDIR="${PWD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/gasket-kernel-compat.patch"
PATCH_URL="https://raw.githubusercontent.com/thatSFguy/coral-edgetpu-legacy-cpu/main/gasket/gasket-kernel-compat.patch"

while getopts ":k:r:bh" opt; do
  case "${opt}" in
    k) KVER="${OPTARG}" ;;
    r) GASKET_REF="${OPTARG}" ;;
    b) INSTALL=0 ;;
    h) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown option -${OPTARG}" >&2; exit 1 ;;
  esac
done

log()  { echo -e "\n\033[1;32m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m warning:\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m error:\033[0m $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must be run as root (use sudo)"

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "only x86_64 is supported" ;;
esac

# ---------------------------------------------------------------- headers ---
log "Target kernel: ${KVER}"

KBUILD="/lib/modules/${KVER}/build"
if [ ! -d "${KBUILD}" ]; then
  echo
  echo "No kernel headers found at ${KBUILD}."
  echo
  echo "On openmediavault, install them from the omv-extras Kernel plugin:"
  echo "  System -> Kernel -> Proxmox -> Install Proxmox kernel"
  echo "    (installs proxmox-kernel-X.Y and proxmox-headers-X.Y together)"
  echo "  System -> Kernel -> Debian -> Install Debian kernel headers"
  echo "    (installs linux-headers-amd64 for the Debian stock kernel)"
  echo
  echo "Or from a shell:"
  echo "  apt-get install proxmox-headers-\$(uname -r | cut -d. -f1,2)   # Proxmox kernel"
  echo "  apt-get install linux-headers-amd64                          # Debian kernel"
  echo
  die "kernel headers for ${KVER} are required"
fi
log "Kernel headers: ${KBUILD} -> $(readlink -f "${KBUILD}")"

# ------------------------------------------------------------ build deps ----
log "Installing build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
DEPS="git curl build-essential debhelper devscripts fakeroot dkms patch pciutils"
# dh_dkms moved out of the dkms package into dh-dkms; without it
# `dh --with dkms` in debian/rules fails. Present on Debian 12 and 13.
if apt-cache show dh-dkms >/dev/null 2>&1; then
  DEPS="${DEPS} dh-dkms"
fi
# shellcheck disable=SC2086
apt-get install --yes --no-install-recommends ${DEPS}

# ------------------------------------------------------------ get source ----
WORKDIR="$(mktemp -d /tmp/gasket-build.XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

log "Cloning ${GASKET_REPO} @ ${GASKET_REF}"
git clone --quiet "${GASKET_REPO}" "${WORKDIR}/gasket-driver"
git -C "${WORKDIR}/gasket-driver" checkout --quiet "${GASKET_REF}"

# ---------------------------------------------------------------- patch -----
if [ ! -f "${PATCH_FILE}" ]; then
  log "Patch not found next to this script, downloading it"
  PATCH_FILE="${WORKDIR}/gasket-kernel-compat.patch"
  curl -fsSL "${PATCH_URL}" -o "${PATCH_FILE}" \
    || die "could not download ${PATCH_URL}"
fi

log "Applying kernel compatibility patch"
cd "${WORKDIR}/gasket-driver"
if patch -p1 --dry-run --silent < "${PATCH_FILE}"; then
  patch -p1 < "${PATCH_FILE}"
elif patch -p1 --dry-run --silent --reverse < "${PATCH_FILE}"; then
  warn "patch already applied upstream, skipping"
else
  die "patch does not apply to ${GASKET_REF} -- upstream has changed, please open an issue"
fi

# gasket-dkms hard-depends on a Debian-flavoured kernel headers package.
# Proxmox kernels ship proxmox-headers-X.Y instead, which does not always
# satisfy that alternation. We have already verified real headers on disk
# above, so demote the dependency to a recommendation.
if ! grep -q '^Recommends: linux-headers' debian/control; then
  log "Relaxing the kernel-headers dependency (Proxmox headers do not satisfy it)"
  # shellcheck disable=SC2016  # ${misc:Depends} is a dpkg substvar, not a shell var
  sed -i \
    -e 's/^Depends: dkms (>= 1.95), linux-headers[^,]*, \${misc:Depends}$/Depends: dkms (>= 1.95), ${misc:Depends}\nRecommends: linux-headers-amd64 | linux-headers-generic | linux-headers | proxmox-default-headers/' \
    debian/control
  grep -q '^Recommends: linux-headers' debian/control \
    || warn "could not relax the dependency; install may need 'apt-get -f install'"
fi

# ---------------------------------------------------------------- build -----
log "Building gasket-dkms package"
dpkg-buildpackage -us -uc -tc -b

# shellcheck disable=SC2012  # our own filenames, plain ASCII
DEB="$(ls -1 "${WORKDIR}"/gasket-dkms_*_all.deb 2>/dev/null | head -1)"
[ -n "${DEB}" ] || die "build produced no .deb"

if [ "${INSTALL}" -eq 0 ]; then
  cp "${DEB}" "${OUTDIR}/"
  log "Built ${OUTDIR}/$(basename "${DEB}") (not installed)"
  exit 0
fi

# -------------------------------------------------------------- install -----
log "Installing $(basename "${DEB}")"
apt-get install --yes --no-install-recommends "${DEB}"

# DKMS autoinstall only targets the running kernel. If we are building for a
# kernel that is not booted yet, drive dkms directly.
DKMS_VER="$(dkms status gasket 2>/dev/null | sed -n 's#^gasket[/,] *\([^,:]*\).*#\1#p' | head -1)"
if [ -n "${DKMS_VER}" ] && ! dkms status -m gasket -v "${DKMS_VER}" -k "${KVER}" 2>/dev/null | grep -q installed; then
  log "Building gasket/${DKMS_VER} for ${KVER} via DKMS"
  dkms install -m gasket -v "${DKMS_VER}" -k "${KVER}" --force \
    || die "DKMS build failed for ${KVER}; see /var/lib/dkms/gasket/${DKMS_VER}/build/make.log"
fi

log "DKMS status"
dkms status gasket || true

# --------------------------------------------------------------- verify -----
if [ "${KVER}" = "$(uname -r)" ]; then
  modprobe gasket 2>/dev/null || true
  modprobe apex   2>/dev/null || true
  log "Verification"
  if [ -e /dev/apex_0 ]; then
    echo "  /dev/apex_0 present:"
    ls -l /dev/apex_0
  else
    warn "/dev/apex_0 is missing."
    echo "  Modules loaded:"
    lsmod | grep -E '^(gasket|apex)' || echo "    (none)"
    echo "  Coral device on the PCI bus:"
    lspci -nn 2>/dev/null | grep -i '1ac1:089a' || echo "    (not found -- check the card is seated and enabled in BIOS)"
    echo "  Recent kernel messages:"
    dmesg 2>/dev/null | grep -iE 'gasket|apex' | tail -20 || true
  fi
else
  log "Built for ${KVER}; reboot into that kernel, then check for /dev/apex_0"
fi

if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
  echo
  warn "Secure Boot is enabled. DKMS modules must be signed with an enrolled MOK"
  warn "or the kernel will refuse to load gasket/apex. Either enroll a key or"
  warn "disable Secure Boot in the BIOS."
fi

log "Done."
