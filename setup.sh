#!/usr/bin/env bash
#
# setup.sh — provision a fresh Debian machine to build and boot this
# x86_64 bare-metal kernel. Designed for an arm64 (aarch64) VM, but works
# on amd64 too.
#
# Everything here is cross-work on arm64: the compiler targets x86_64, the
# ISO carries GRUB's i386-pc bootloader, and QEMU emulates an x86_64 PC in
# software (TCG — no KVM, since the host CPU is not x86).
#
# Usage:
#   ./setup.sh [options]
#
#   --toolchain=apt      Use Debian's gcc-x86-64-linux-gnu cross compiler.
#                        Minutes to install. This is the default.
#   --toolchain=source   Build a true x86_64-elf GCC from source via the
#                        ./x86_64-elf script. 20-60+ minutes, RAM hungry.
#   --no-qemu            Skip installing QEMU (build-only machine).
#   --no-efi             Only make the ISO BIOS-bootable, not UEFI.
#   --no-verify          Skip the end-to-end build + boot smoke test.
#   --suite=NAME         Override the Debian suite (default: autodetected).
#   -h, --help           Show this help.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

TOOLCHAIN=apt
WITH_QEMU=1
WITH_EFI=1
VERIFY=1
SUITE=""

# ---- Output helpers ------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
    C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""
fi

step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s[ok]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '    %s[!]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '\n%serror:%s %s\n\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
setup.sh — provision a fresh Debian machine to build and boot this x86_64
bare-metal kernel. Works on arm64 (aarch64) and amd64 hosts.

Usage: ./setup.sh [options]

  --toolchain=apt      Use Debian's gcc-x86-64-linux-gnu cross compiler.
                       Minutes to install. This is the default.
  --toolchain=source   Build a true x86_64-elf GCC from source via the
                       ./x86_64-elf script. 20-60+ minutes, RAM hungry.
  --no-qemu            Skip installing QEMU (build-only machine).
  --no-efi             Only make the ISO BIOS-bootable, not UEFI.
  --no-verify          Skip the end-to-end build + boot smoke test.
  --suite=NAME         Override the Debian suite (default: autodetected).
  -h, --help           Show this help.
USAGE
    exit 0
}

# ---- Arguments -----------------------------------------------------------

for arg in "$@"; do
    case "$arg" in
        --toolchain=apt)    TOOLCHAIN=apt ;;
        --toolchain=source) TOOLCHAIN=source ;;
        --no-qemu)          WITH_QEMU=0 ;;
        --no-efi)           WITH_EFI=0 ;;
        --no-verify)        VERIFY=0 ;;
        --suite=*)          SUITE="${arg#*=}" ;;
        -h|--help)          usage ;;
        *) die "unknown option: $arg (try --help)" ;;
    esac
done

# ---- Environment detection ----------------------------------------------

step "Inspecting this machine"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    info "Not root — using sudo. You may be prompted for your password."
else
    die "This script needs root. Run it as root, or install sudo first:
       su -c 'apt-get install -y sudo && adduser $USER sudo'"
fi

command -v apt-get >/dev/null 2>&1 || die "apt-get not found. This script targets Debian and Debian derivatives."
command -v dpkg    >/dev/null 2>&1 || die "dpkg not found. This script targets Debian and Debian derivatives."

OS_NAME="unknown"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
    [ -n "$SUITE" ] || SUITE="${VERSION_CODENAME:-}"
fi

if [ -z "$SUITE" ]; then
    case "$(cat /etc/debian_version 2>/dev/null || echo)" in
        12*) SUITE=bookworm ;;
        13*) SUITE=trixie ;;
        *)   SUITE="" ;;
    esac
fi
[ -n "$SUITE" ] || die "Could not detect the Debian suite. Pass it explicitly, e.g. --suite=trixie"

HOST_ARCH="$(dpkg --print-architecture)"
KERNEL_ARCH="$(uname -m)"

info "OS:            $OS_NAME"
info "Suite:         $SUITE"
info "Host arch:     $HOST_ARCH ($KERNEL_ARCH)"
info "Target arch:   amd64 / x86_64-elf (bare metal)"

case "$HOST_ARCH" in
    arm64)
        info "Mode:          cross-build + full software emulation (TCG, no KVM)"
        ;;
    amd64)
        info "Mode:          native-arch build; KVM available if /dev/kvm exists"
        ;;
    *)
        warn "Host arch '$HOST_ARCH' is neither arm64 nor amd64. This should still"
        warn "work, but it is untested — the cross compiler package may not exist."
        ;;
esac

TOTAL_RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
info "RAM:           ${TOTAL_RAM_MB} MB"

# ---- Base packages -------------------------------------------------------

step "Installing base build and ISO tooling"

export DEBIAN_FRONTEND=noninteractive

$SUDO apt-get update -qq

BASE_PKGS=(
    build-essential make
    curl ca-certificates xz-utils file
    xorriso mtools dosfstools
    grub-common grub2-common
)
[ "$WITH_QEMU" -eq 1 ] && BASE_PKGS+=(qemu-system-x86)

INSTALL_PKGS=()
for p in "${BASE_PKGS[@]}"; do
    if apt-cache show "$p" >/dev/null 2>&1; then
        INSTALL_PKGS+=("$p")
    else
        warn "package '$p' is not available in $SUITE — skipping"
    fi
done

$SUDO apt-get install -y -qq "${INSTALL_PKGS[@]}"
ok "base tooling installed"

command -v grub-mkrescue >/dev/null 2>&1 || die "grub-mkrescue still missing after installing grub-common."
command -v xorriso       >/dev/null 2>&1 || die "xorriso still missing after install."

# ---- Cross compiler ------------------------------------------------------

step "Setting up the x86_64 cross compiler"

install_apt_toolchain() {
    if [ "$HOST_ARCH" = "amd64" ]; then
        info "Host is amd64 — the native gcc already targets x86_64."
        info "The Makefile will use plain 'gcc' with -ffreestanding."
        ok "toolchain ready (native gcc)"
        return 0
    fi

    local pkgs=(gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu)
    for p in "${pkgs[@]}"; do
        apt-cache show "$p" >/dev/null 2>&1 \
            || die "'$p' is not available for $HOST_ARCH on $SUITE.
       Fall back to building the toolchain from source:
           ./setup.sh --toolchain=source"
    done

    $SUDO apt-get install -y -qq "${pkgs[@]}"

    command -v x86_64-linux-gnu-gcc >/dev/null 2>&1 \
        || die "x86_64-linux-gnu-gcc not on PATH after install."

    info "$(x86_64-linux-gnu-gcc --version | head -1)"
    ok "toolchain ready (x86_64-linux-gnu-gcc)"

    cat <<'NOTE'

    Note: this is a linux-gnu targeted compiler, not a bare x86_64-elf one.
    For a freestanding kernel that difference does not matter — the Makefile
    already passes -ffreestanding -nostdlib -no-pie -fno-pic, which suppresses
    every assumption the compiler would otherwise make about a host OS. If you
    later want the "textbook" toolchain, re-run with --toolchain=source.
NOTE
}

install_source_toolchain() {
    local script="$REPO_DIR/x86_64-elf"
    [ -f "$script" ] || die "Expected the toolchain build script at $script"

    if command -v "$HOME/opt/cross/bin/x86_64-elf-gcc" >/dev/null 2>&1; then
        ok "x86_64-elf-gcc already built at ~/opt/cross"
        return 0
    fi

    if [ "$TOTAL_RAM_MB" -gt 0 ] && [ "$TOTAL_RAM_MB" -lt 2048 ]; then
        warn "Only ${TOTAL_RAM_MB} MB of RAM. Building GCC needs roughly 2 GB;"
        warn "without swap the build will be OOM-killed part way through"
        warn "('Killed signal terminated program cc1plus'). Add swap first:"
        warn "  sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile"
        warn "  sudo mkswap /swapfile && sudo swapon /swapfile"
    fi

    $SUDO apt-get install -y -qq \
        bison flex libgmp-dev libmpc-dev libmpfr-dev texinfo libisl-dev wget

    info "Building binutils + GCC from source. This takes 20-60+ minutes."
    bash "$script"

    export PATH="$HOME/opt/cross/bin:$PATH"
    command -v x86_64-elf-gcc >/dev/null 2>&1 \
        || die "x86_64-elf-gcc missing after the source build."

    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        if ! grep -qs 'opt/cross/bin' "$rc"; then
            printf '\n# x86_64-elf cross toolchain (added by Kernel/setup.sh)\nexport PATH="$HOME/opt/cross/bin:$PATH"\n' >> "$rc"
            info "added ~/opt/cross/bin to PATH in $rc"
        fi
    done

    ok "toolchain ready (x86_64-elf-gcc)"
}

case "$TOOLCHAIN" in
    apt)    install_apt_toolchain ;;
    source) install_source_toolchain ;;
esac

# ---- GRUB target platform modules ---------------------------------------
#
# This is the part that actually bites on arm64.
#
# grub-mkrescue lives in grub-common, which IS built for arm64 and is a
# target-agnostic tool — it can assemble an ISO for any platform. But the
# platform modules it stitches in live in separate packages:
#
#   i386-pc    <- grub-pc-bin        (BIOS boot)
#   x86_64-efi <- grub-efi-amd64-bin (UEFI boot)
#
# and both of those are published for amd64/i386 ONLY. On arm64 they simply
# do not exist, so a plain `apt install grub-pc-bin` fails and grub-mkrescue
# dies with "cannot find /usr/lib/grub/i386-pc".
#
# We cannot `apt install grub-pc-bin:amd64` either: it depends on
# grub-common (= exact version), so multi-arch resolution would try to swap
# our arm64 grub-common for an amd64 one and leave grub-mkrescue unrunnable.
#
# The contents of these packages are not host executables though — they are
# x86 target payloads that only ever get embedded into the ISO. So we
# download the amd64 .deb without installing it, and unpack just the
# platform directory into /usr/lib/grub/ where grub-mkrescue looks.

GRUB_DIR=/usr/lib/grub
AMD64_ARCH_ADDED=0

grub_platform_present() {
    [ -f "$GRUB_DIR/$1/normal.mod" ] && [ -f "$GRUB_DIR/$1/modinfo.sh" ]
}

grub_common_version() {
    dpkg-query -W -f='${Version}' grub-common 2>/dev/null || echo ""
}

# Download an amd64 .deb into $1 using apt, without installing it.
apt_fetch_amd64_deb() {
    local destdir=$1 pkg=$2

    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx amd64; then
        info "enabling amd64 as a foreign architecture (for downloads only)"
        $SUDO dpkg --add-architecture amd64
        AMD64_ARCH_ADDED=1
        $SUDO apt-get update -qq || {
            warn "apt-get update failed with amd64 enabled; rolling that back"
            $SUDO dpkg --remove-architecture amd64 || true
            AMD64_ARCH_ADDED=0
            $SUDO apt-get update -qq || true
            return 1
        }
    fi

    ( cd "$destdir" && $SUDO apt-get download -qq "${pkg}:amd64" ) >/dev/null 2>&1
}

# Fallback: resolve the pool path straight out of the archive indexes.
direct_fetch_amd64_deb() {
    local destdir=$1 pkg=$2 want_ver=$3
    local spec base path url filename

    for spec in \
        "https://deb.debian.org/debian|dists/$SUITE/main/binary-amd64/Packages.gz" \
        "https://deb.debian.org/debian|dists/$SUITE-updates/main/binary-amd64/Packages.gz" \
        "https://deb.debian.org/debian-security|dists/$SUITE-security/main/binary-amd64/Packages.gz"
    do
        base="${spec%%|*}"; path="${spec#*|}"
        filename="$(curl -fsSL "$base/$path" 2>/dev/null | gunzip 2>/dev/null | awk -v pkg="$pkg" -v ver="$want_ver" '
            /^Package: /  { p = $2 }
            /^Version: /  { v = $2 }
            /^Filename: / { f = $2 }
            /^$/          { if (p == pkg && (ver == "" || v == ver)) print f; p = v = f = "" }
            END           { if (p == pkg && (ver == "" || v == ver)) print f }
        ' | tail -1)"

        if [ -n "$filename" ]; then
            url="$base/$filename"
            info "fetching $(basename "$url")"
            curl -fsSL -o "$destdir/$(basename "$url")" "$url" && return 0
        fi
    done
    return 1
}

install_grub_platform() {
    local platform=$1 pkg=$2 required=$3
    local tmp deb want_ver got_ver src

    if grub_platform_present "$platform"; then
        ok "$platform modules already present in $GRUB_DIR/$platform"
        return 0
    fi

    if [ "$HOST_ARCH" = "amd64" ]; then
        info "installing $pkg natively"
        if $SUDO apt-get install -y -qq "$pkg"; then
            ok "$platform modules installed from $pkg"
            return 0
        fi
        [ "$required" -eq 1 ] && die "failed to install $pkg"
        warn "could not install $pkg — continuing without $platform"
        return 1
    fi

    info "$pkg has no $HOST_ARCH build; fetching the amd64 payload instead"

    want_ver="$(grub_common_version)"
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if ! apt_fetch_amd64_deb "$tmp" "$pkg"; then
        info "apt download unavailable — falling back to the archive index"
        direct_fetch_amd64_deb "$tmp" "$pkg" "$want_ver" \
            || direct_fetch_amd64_deb "$tmp" "$pkg" "" \
            || { [ "$required" -eq 1 ] && die "could not download $pkg (amd64) for $SUITE"
                 warn "could not download $pkg — continuing without $platform"; return 1; }
    fi

    deb="$(find "$tmp" -maxdepth 1 -name "${pkg}_*.deb" | head -1)"
    [ -n "$deb" ] || { [ "$required" -eq 1 ] && die "no .deb landed for $pkg"
                       warn "no .deb landed for $pkg"; return 1; }

    got_ver="$(dpkg-deb -f "$deb" Version)"
    if [ -n "$want_ver" ] && [ "$got_ver" != "$want_ver" ]; then
        warn "version skew: grub-common is $want_ver but $pkg is $got_ver."
        warn "grub-mkrescue and its modules come from the same source package,"
        warn "so a mismatch here can produce an ISO that hangs at boot."
    fi

    dpkg-deb -x "$deb" "$tmp/root"
    src="$tmp/root/usr/lib/grub/$platform"
    [ -d "$src" ] || { [ "$required" -eq 1 ] && die "$pkg did not contain usr/lib/grub/$platform"
                       warn "$pkg did not contain $platform"; return 1; }

    $SUDO install -d "$GRUB_DIR"
    $SUDO cp -a "$src" "$GRUB_DIR/"
    printf '%s %s (unpacked by Kernel/setup.sh; remove this directory to undo)\n' \
        "$pkg" "$got_ver" | $SUDO tee "$GRUB_DIR/$platform/.installed-by-kernel-setup" >/dev/null

    grub_platform_present "$platform" \
        || { [ "$required" -eq 1 ] && die "$platform modules still look incomplete"
             warn "$platform modules incomplete"; return 1; }

    ok "$platform modules installed ($pkg $got_ver)"
}

step "Installing GRUB's x86 target modules"

install_grub_platform i386-pc grub-pc-bin 1

if [ "$WITH_EFI" -eq 1 ]; then
    install_grub_platform x86_64-efi grub-efi-amd64-bin 0 \
        || warn "ISO will be BIOS-bootable only (that is all QEMU's default SeaBIOS needs)"
fi

# ---- QEMU ----------------------------------------------------------------

if [ "$WITH_QEMU" -eq 1 ]; then
    step "Checking QEMU"
    command -v qemu-system-x86_64 >/dev/null 2>&1 \
        || die "qemu-system-x86_64 missing after installing qemu-system-x86."
    info "$(qemu-system-x86_64 --version | head -1)"

    if [ "$HOST_ARCH" != "amd64" ]; then
        info "x86_64 guests run under TCG (software emulation) on $HOST_ARCH."
        info "That is expected and correct — KVM cannot accelerate a foreign ISA."
        info "Boot takes a few seconds instead of milliseconds. Fine for this kernel."
    elif [ -r /dev/kvm ]; then
        info "/dev/kvm is available — you can add '-enable-kvm' for native speed."
    fi
    ok "QEMU ready"
fi

# ---- Verification --------------------------------------------------------

if [ "$VERIFY" -eq 0 ]; then
    step "Skipping verification (--no-verify)"
else
    step "Verifying: building the kernel"

    cd "$REPO_DIR"
    make clean >/dev/null 2>&1 || true

    if ! make kernel.elf; then
        die "the kernel failed to build. See the compiler output above."
    fi
    ok "kernel.elf built"

    # The multiboot2 header magic is 0xE85250D6. GRUB only scans the first
    # 32 KB of the file for it, so a header that drifts past that boundary
    # is the classic "Error loading uncompressed kernel" failure.
    if head -c 32768 kernel.elf | od -An -tx1 -v | tr -d ' \n' | grep -q 'd65052e8'; then
        ok "multiboot2 magic found within the first 32 KB"
    else
        warn "could not confirm the multiboot2 magic in the first 32 KB of kernel.elf"
    fi

    step "Verifying: building the bootable ISO"
    if ! make kernel.iso; then
        die "grub-mkrescue failed. If it complained about /usr/lib/grub/i386-pc,
       the GRUB module step above did not take effect."
    fi
    ok "kernel.iso built ($(du -h kernel.iso | cut -f1))"

    if [ "$WITH_QEMU" -eq 1 ]; then
        step "Verifying: booting the ISO in QEMU"
        info "Booting headless with serial capture (up to 60s under emulation)..."

        serial_log="$(mktemp)"
        # The kernel halts forever on purpose, so QEMU never exits by itself.
        timeout 60 qemu-system-x86_64 \
            -cdrom kernel.iso -boot d \
            -display none -serial "file:$serial_log" \
            -no-reboot >/dev/null 2>&1 || true

        if grep -q "kprintf is working" "$serial_log" 2>/dev/null; then
            ok "the kernel booted and reached kernel_main"
            info "serial output:"
            sed 's/^/      | /' "$serial_log"
        else
            warn "did not see the expected kernel output on the serial port."
            warn "captured serial log:"
            sed 's/^/      | /' "$serial_log" 2>/dev/null || true
            warn "This does not necessarily mean the build is broken — try"
            warn "'make run-serial' by hand and watch it live."
        fi
        rm -f "$serial_log"
    fi
fi

# ---- Done ----------------------------------------------------------------

step "Setup complete"

cat <<EOF

    Build and boot:

      make run-serial     boot headless, kernel output straight to this
                          terminal over the emulated COM1 serial port.
                          Use this over SSH. Quit with Ctrl-A then X.

      make run            boot in a QEMU window. Needs a display / X11
                          forwarding — on a headless VM use run-serial.

      make kernel.elf     just compile, do not boot
      make kernel.iso     build the bootable ISO
      make clean          remove all build artifacts

EOF

if [ "$TOOLCHAIN" = "source" ]; then
cat <<EOF
    Your shell needs the cross toolchain on PATH. Open a new shell, or:

      export PATH="\$HOME/opt/cross/bin:\$PATH"

EOF
fi

if [ "$AMD64_ARCH_ADDED" -eq 1 ]; then
cat <<EOF
    Note: amd64 was enabled as a foreign dpkg architecture so the GRUB x86
    payloads could be downloaded. Nothing amd64 was installed. To undo it:

      sudo dpkg --remove-architecture amd64 && sudo apt-get update

EOF
fi
