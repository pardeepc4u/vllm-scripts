#!/usr/bin/env bash
# Proxmox host / LXC NVIDIA, CUDA, and vLLM diagnostic and recovery reference.
# Run one mode at a time. Read the printed plan before using --apply.
#
# Examples:
#   On Proxmox host:  ./proxmox-lxc-nvidia-cuda-vllm-recovery.sh host-diagnose
#   In vLLM LXC:      ./proxmox-lxc-nvidia-cuda-vllm-recovery.sh lxc-diagnose
#   In vLLM LXC:      ./proxmox-lxc-nvidia-cuda-vllm-recovery.sh lxc-install-toolkit 13.1 --apply
#   In vLLM LXC:      ./proxmox-lxc-nvidia-cuda-vllm-recovery.sh vllm-configure 13.1 --apply
#
# Important:
# - An LXC uses the Proxmox host's NVIDIA KERNEL MODULE.
# - The LXC's libcuda1/libnvidia-ml1 must match that loaded host module exactly.
# - Do not install NVIDIA DKMS/kernel packages inside an LXC.
# - Use versioned CUDA TOOLKIT packages only in the LXC (cuda-toolkit-X-Y), not cuda/cuda-drivers.

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-help}"
VERSION="${2:-}"
APPLY="${3:-}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
die() { red "ERROR: $*"; exit 1; }
require_root() { [[ "${EUID}" -eq 0 ]] || die "Run as root."; }
require_apply() { [[ "${APPLY}" == "--apply" ]] || die "Dry-run only. Re-run with --apply after reviewing the commands."; }
require_lxc() { systemd-detect-virt -cq || die "This mode must run inside an LXC container."; }
require_not_lxc() { ! systemd-detect-virt -cq || die "This mode must run on the Proxmox host, not inside an LXC."; }

kernel_driver_version() {
    awk '/NVRM version:/ {print $8; exit}' /proc/driver/nvidia/version 2>/dev/null || true
}

installed_pkg_version() {
    dpkg-query -W -f='${Version}\n' "$1" 2>/dev/null || true
}

cuda_toolkit_from_torch() {
    if [[ -x /opt/vllm/bin/python ]]; then
        /opt/vllm/bin/python -c 'import torch; print(torch.version.cuda or "")' 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import torch; print(torch.version.cuda or "")' 2>/dev/null || true
    fi
}

print_banner() {
    cat <<EOF

=== NVIDIA / CUDA / vLLM recovery reference ===
Mode: ${MODE}
Host: $(hostname)
Kernel: $(uname -r)
Virtualization: $(systemd-detect-virt 2>/dev/null || true)
===============================================
EOF
}

host_diagnose() {
    require_root
    require_not_lxc
    print_banner
    info "Loaded NVIDIA kernel module"
    cat /proc/driver/nvidia/version 2>/dev/null || true
    echo
    info "NVIDIA-SMI"
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || yellow "nvidia-smi is unavailable or failed."
    echo
    info "Installed NVIDIA / CUDA packages"
    dpkg -l | awk '/^(ii|hi)/ && ($2 ~ /^(nvidia|libnvidia|libcuda|cuda)/) {print}' || true
    echo
    info "DKMS status"
    command -v dkms >/dev/null 2>&1 && dkms status || true
    echo
    info "Running kernel headers"
    dpkg -l "pve-headers-$(uname -r)" "linux-headers-$(uname -r)" 2>/dev/null || true
    echo
    info "GPU device nodes"
    ls -l /dev/nvidia* 2>/dev/null || true
    echo
    green "Host diagnostic complete. Record the loaded driver version before changing LXC libraries."
}

lxc_diagnose() {
    require_root
    require_lxc
    print_banner
    local host_ver libcuda_ver nvml_ver torch_cuda
    host_ver="$(kernel_driver_version)"
    libcuda_ver="$(installed_pkg_version libcuda1)"
    nvml_ver="$(installed_pkg_version libnvidia-ml1)"
    torch_cuda="$(cuda_toolkit_from_torch)"

    info "Host NVIDIA module visible in LXC"
    cat /proc/driver/nvidia/version 2>/dev/null || true
    echo
    info "Core NVIDIA package versions"
    printf 'host kernel module: %s\nlibcuda1:            %s\nlibnvidia-ml1:      %s\n' \
        "${host_ver:-missing}" "${libcuda_ver:-missing}" "${nvml_ver:-missing}"
    echo
    info "NVIDIA device nodes"
    ls -l /dev/nvidia* 2>/dev/null || true
    echo
    info "Dynamic linker selections"
    ldconfig -p 2>/dev/null | grep -E 'libcuda\.so\.1|libnvidia-ml\.so\.1' || true
    echo
    info "NVIDIA paths that may override system libraries"
    find /usr/local/cuda /usr/local/cuda-* /opt  -type f \( -name 'libcuda.so*' -o -name 'libnvidia-ml.so*' \) -printf '%p -> %l\n' 2>/dev/null || true
    echo
    info "NVSMI"
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || yellow "nvidia-smi is missing or cannot initialize."
    echo
    info "vLLM Python / PyTorch CUDA test"
    if [[ -x /opt/vllm/bin/python ]]; then
        /opt/vllm/bin/python - <<'PY' || true
import ctypes
import torch
print("torch:", torch.__version__)
print("torch CUDA build:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
print("CUDA devices:", torch.cuda.device_count())
for library in ("libcuda.so.1", "libnvidia-ml.so.1"):
    try:
        print(library, "=>", ctypes.CDLL(library))
    except OSError as exc:
        print(library, "ERROR:", exc)
PY
    else
        yellow "/opt/vllm/bin/python does not exist."
    fi
    echo
    info "CUDA toolkit / compiler"
    printf 'PyTorch CUDA version: %s\n' "${torch_cuda:-unknown}"
    local nvcc_bin="" nvcc_candidate
    if command -v nvcc >/dev/null 2>&1; then
        nvcc_bin="$(command -v nvcc)"
    elif [[ -x /usr/local/cuda/bin/nvcc ]]; then
        nvcc_bin="/usr/local/cuda/bin/nvcc"
    else
        for nvcc_candidate in /usr/local/cuda-*/bin/nvcc; do
            [[ -x "${nvcc_candidate}" ]] && nvcc_bin="${nvcc_candidate}"
        done
    fi
    if [[ -n "${nvcc_bin}" ]]; then
        "${nvcc_bin}" --version || true
        if ! command -v nvcc >/dev/null 2>&1; then
            yellow "nvcc found at ${nvcc_bin} but not in PATH."
            yellow "Interactive shells: export PATH=\"$(dirname "${nvcc_bin}"):\$PATH\""
            yellow "vLLM service: run '$SCRIPT_NAME vllm-configure <cuda-version> --apply'."
        fi
    else
        yellow "nvcc not found in PATH or under /usr/local/cuda*. Install with: $SCRIPT_NAME lxc-install-toolkit <cuda-version> --apply"
    fi
    ls -ld /usr/local/cuda /usr/local/cuda-* 2>/dev/null || true
    echo
    info "vLLM service environment"
    systemctl show vllm.service -p Environment 2>/dev/null || true
    echo

    if [[ -n "${host_ver}" && "${libcuda_ver}" == "${host_ver}-1" && "${nvml_ver}" == "${host_ver}-1" ]]; then
        green "Core LXC driver libraries match the host kernel module."
    else
        yellow "Core versions do not appear to match exactly. Align LXC driver libraries to host module ${host_ver:-<unknown>}."
    fi
}

lxc_align_libraries() {
    require_root
    require_lxc
    [[ -n "${VERSION}" ]] || die "Usage: $SCRIPT_NAME lxc-align-libraries <driver-version> --apply"
    require_apply

    local packages=(
        libcuda1 libnvcuvid1 libnvidia-encode1 libnvidia-gpucomp libnvidia-ml1
        libnvidia-pkcs11-openssl3 libnvidia-ptxjitcompiler1
    )
    info "Installing exact NVIDIA runtime library version ${VERSION}-1 in this LXC."
    info "This command intentionally excludes DKMS/kernel packages."
    apt update
    apt install --allow-downgrades "${packages[@]/%/=${VERSION}-1}"
    ldconfig
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        yellow "nvidia-smi binary not present. Note: since driver branch 560, the CUDA"
        yellow "repo's 'nvidia-smi' package is a transitional dummy without the binary."
        yellow "Options:"
        yellow "  1) Review the simulation, then install: apt install nvidia-driver-cuda=${VERSION}-1"
        yellow "     Reject the transaction if it proposes kernel/DKMS packages."
        yellow "  2) Copy the matching binary from the Proxmox host:"
        yellow "     pct push <CTID> /usr/bin/nvidia-smi /usr/bin/nvidia-smi"
    fi
    green "Libraries updated. Run '$SCRIPT_NAME lxc-diagnose' before starting vLLM."
}

lxc_install_toolkit() {
    require_root
    require_lxc
    [[ -n "${VERSION}" ]] || die "Usage: $SCRIPT_NAME lxc-install-toolkit <CUDA-major.minor> --apply"
    require_apply

    local package_version package
    package_version="${VERSION/.//-}"
    package="cuda-toolkit-${package_version}"
    info "Simulating ${package}; this should not install cuda-drivers, nvidia-driver, or DKMS packages."
    apt update
    apt -s install "${package}"
    read -r -p "Review simulation above. Install ${package} now? [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]] || die "Aborted."
    apt install "${package}"

    local cuda_dir="/usr/local/cuda-${VERSION}"
    [[ -x "${cuda_dir}/bin/nvcc" ]] || die "Expected ${cuda_dir}/bin/nvcc was not installed."
    ln -sfn "${cuda_dir}" /usr/local/cuda
    "${cuda_dir}/bin/nvcc" --version
    "${cuda_dir}/bin/ptxas" --version
    green "CUDA Toolkit ${VERSION} installed and /usr/local/cuda now points to it."
}

vllm_configure() {
    require_root
    require_lxc
    [[ -n "${VERSION}" ]] || die "Usage: $SCRIPT_NAME vllm-configure <CUDA-major.minor> --apply"
    require_apply

    local cuda_dir="/usr/local/cuda-${VERSION}"
    [[ -x "${cuda_dir}/bin/nvcc" ]] || die "${cuda_dir}/bin/nvcc is missing. Install toolkit first."
    mkdir -p /etc/systemd/system/vllm.service.d
    cat > /etc/systemd/system/vllm.service.d/cuda.conf <<EOF
[Service]
Environment="CUDA_HOME=${cuda_dir}"
Environment="PATH=${cuda_dir}/bin:/opt/vllm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="TRITON_PTXAS_PATH=${cuda_dir}/bin/ptxas"
Environment="VLLM_LOGGING_LEVEL=DEBUG"
EOF
    systemctl daemon-reload
    systemctl restart vllm.service
    sleep 3
    systemctl --no-pager --full status vllm.service || true
    journalctl -u vllm.service -b -n 120 --no-pager || true
}

host_prepare_update() {
    require_root
    require_not_lxc
    print_banner
    info "Preparing the host to install an NVIDIA DKMS driver."
    apt update
    apt install -y build-essential dkms "pve-headers-$(uname -r)"
    green "Prerequisites installed. Configure the NVIDIA repository matching this host's Debian base, then simulate the exact driver package installation."
    cat <<'EOF'

Suggested next checks:
  cat /etc/os-release
  apt-cache madison cuda-drivers nvidia-driver
  apt -s install cuda-drivers=<EXACT_VERSION>

After reviewing the transaction:
  apt install cuda-drivers=<EXACT_VERSION>
  update-initramfs -u -k all
  reboot

After reboot:
  cat /proc/driver/nvidia/version
  nvidia-smi

Only then align each GPU-enabled LXC to the exact loaded host driver version.
EOF
}

help() {
    cat <<EOF
Usage:
  $SCRIPT_NAME host-diagnose
      Run on Proxmox host. Print loaded NVIDIA module, DKMS, headers, GPUs.

  $SCRIPT_NAME host-prepare-update
      Run on Proxmox host. Installs DKMS/build/PVE-header prerequisites only.

  $SCRIPT_NAME lxc-diagnose
      Run inside vLLM LXC. Detect driver mismatch, GPU visibility, PyTorch, nvcc.

  $SCRIPT_NAME lxc-align-libraries <DRIVER_VERSION> --apply
      Run inside LXC. Example: 595.58.03 or 610.57.04.
      Aligns core NVIDIA runtime libraries to the host's loaded module version.

  $SCRIPT_NAME lxc-install-toolkit <CUDA_MAJOR.MINOR> --apply
      Run inside LXC. Example: 13.1.
      Installs versioned CUDA Toolkit only; asks after a simulation.

  $SCRIPT_NAME vllm-configure <CUDA_MAJOR.MINOR> --apply
      Run inside LXC. Example: 13.1.
      Writes /etc/systemd/system/vllm.service.d/cuda.conf and restarts vLLM.

Recommended workflow:
  1) Proxmox host: $SCRIPT_NAME host-diagnose
  2) If updating host: $SCRIPT_NAME host-prepare-update
  3) Upgrade host driver, reboot, verify nvidia-smi / loaded module.
  4) vLLM LXC: $SCRIPT_NAME lxc-diagnose
  5) vLLM LXC: $SCRIPT_NAME lxc-align-libraries <host-module-version> --apply
  6) vLLM LXC: $SCRIPT_NAME lxc-install-toolkit <CUDA-version> --apply
  7) vLLM LXC: $SCRIPT_NAME vllm-configure <CUDA-version> --apply
EOF
}

case "${MODE}" in
    host-diagnose) host_diagnose ;;
    host-prepare-update) host_prepare_update ;;
    lxc-diagnose) lxc_diagnose ;;
    lxc-align-libraries) lxc_align_libraries ;;
    lxc-install-toolkit) lxc_install_toolkit ;;
    vllm-configure) vllm_configure ;;
    help|-h|--help) help ;;
    *) die "Unknown mode '${MODE}'. Run '$SCRIPT_NAME help'." ;;
esac
