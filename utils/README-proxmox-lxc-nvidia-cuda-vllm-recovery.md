# Proxmox LXC NVIDIA, CUDA, and vLLM Recovery Guide

This guide accompanies `proxmox-lxc-nvidia-cuda-vllm-recovery.sh`. It is a reference workflow for NVIDIA GPU sharing from a Proxmox host into an LXC that runs vLLM.

It focuses on the recurring failures:

- `NVRM: API mismatch`
- `Failed to initialize NVML` / `Can't initialize NVML`
- `RuntimeError: Failed to infer device type`
- `nvidia-smi: command not found`
- `RuntimeError: Could not find nvcc and default cuda_home='/usr/local/cuda' doesn't exist`

## Architecture and rules

An LXC does not boot its own kernel. When NVIDIA GPUs are exposed to an LXC, the **Proxmox host** owns and loads the NVIDIA kernel module. The LXC receives `/dev/nvidia*` device nodes and must use NVIDIA user-space libraries compatible with the host's loaded module.

Keep these rules in mind:

| Layer | What it owns | What to install |
|---|---|---|
| Proxmox host | NVIDIA kernel driver/module, DKMS, GPU device nodes | Driver, DKMS, matching PVE headers |
| vLLM LXC | vLLM, PyTorch, CUDA Toolkit, matching NVIDIA runtime libraries | NVIDIA runtime libraries matching host; `cuda-toolkit-X-Y` |
| vLLM LXC | Does not own a kernel | Do **not** install NVIDIA DKMS, kernel modules, or host kernel headers |

The host module version and core LXC libraries must match exactly:

```text
Host:    NVRM Kernel Module 610.57.04
LXC:     libcuda1             610.57.04-1
LXC:     libnvidia-ml1        610.57.04-1
```

A mismatch such as host `595.58.03` and LXC `610.57.04` causes NVML/CUDA errors and prevents vLLM from detecting its GPU.

## Installation

Copy the recovery script to both the Proxmox host and the vLLM LXC, then make it executable:

```bash
chmod +x proxmox-lxc-nvidia-cuda-vllm-recovery.sh
```

Show the built-in help:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh help
```

All destructive or state-changing LXC actions require an explicit `--apply` flag. Toolkit installation additionally displays an `apt` simulation and asks for an interactive confirmation.

## Normal validation workflow

### 1. Diagnose the Proxmox host

Run on the **Proxmox host**:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh host-diagnose
```

Important output includes:

- `cat /proc/driver/nvidia/version`
- `nvidia-smi`
- `dkms status`
- Installed PVE headers for the active kernel
- Existing `/dev/nvidia*` device nodes

Record the loaded driver version. Example:

```text
NVRM version: NVIDIA UNIX x86_64 Kernel Module  610.57.04
```

That exact value, `610.57.04`, is what the LXC core NVIDIA runtime libraries must use.

### 2. Diagnose the vLLM LXC

Run inside the **vLLM LXC**:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh lxc-diagnose
```

The diagnostic checks:

- Host module version visible through `/proc/driver/nvidia/version`
- Installed `libcuda1` and `libnvidia-ml1` versions
- NVIDIA device mapping under `/dev/nvidia*`
- The linker-selected `libcuda.so.1` and `libnvidia-ml.so.1`
- `nvidia-smi` availability
- PyTorch CUDA device visibility
- CUDA Toolkit and `nvcc`
- vLLM systemd environment variables

A healthy result should show PyTorch CUDA as available and at least one CUDA device:

```text
CUDA available: True
CUDA devices: 1
```

## Fix driver/library mismatches

### Symptom

Typical log messages include:

```text
NVRM: API mismatch: the client has version 610.57.04,
but this kernel module has version 595.58.03
```

or:

```text
Failed to initialize NVML: Driver/library version mismatch
```

### Correct procedure

1. Determine the version loaded on the **Proxmox host**:

```bash
cat /proc/driver/nvidia/version
```

2. Stop vLLM before changing libraries:

```bash
systemctl stop vllm.service
```

3. In the LXC, align core NVIDIA libraries to the exact loaded host version. For a host at `595.58.03`:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh \
  lxc-align-libraries 595.58.03 --apply
```

4. Recheck:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh lxc-diagnose
```

Do not merely use the same driver *branch*. `595.58.03` and `595.91.07` are different library/module versions and should be treated as mismatched for this LXC setup.

## Update the host driver

Update the Proxmox host first, reboot, validate it, then update LXC user-space packages to that exact version.

### 1. Stop GPU consumers

On the Proxmox host, stop all GPU-sharing containers and GPU-passthrough workloads as appropriate:

```bash
pct stop <VLLM_CTID>
```

### 2. Prepare DKMS and headers

On the Proxmox host:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh host-prepare-update
```

This installs build prerequisites and headers matching the currently running PVE kernel. It does not install a new NVIDIA driver itself.

### 3. Install the desired driver on host

Use an NVIDIA repository that matches the Debian base of the Proxmox host. Check first:

```bash
cat /etc/os-release
apt-cache madison cuda-drivers nvidia-driver
```

Always simulate an exact version before installing it:

```bash
apt -s install cuda-drivers=<EXACT_DRIVER_VERSION>
```

If the simulation looks correct and does not remove Proxmox packages:

```bash
apt install cuda-drivers=<EXACT_DRIVER_VERSION>
update-initramfs -u -k all
reboot
```

After reboot:

```bash
cat /proc/driver/nvidia/version
nvidia-smi
dkms status
```

Do not update the LXC until the host has loaded the new version successfully.

### 4. Align the LXC afterward

For example, if the host now shows `610.57.04`:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh \
  lxc-align-libraries 610.57.04 --apply
```

Then rerun LXC diagnostics.

## Install CUDA Toolkit for vLLM

### Symptom

vLLM can see the GPU but fails with:

```text
RuntimeError: Could not find nvcc and default cuda_home='/usr/local/cuda' doesn't exist
```

This means vLLM needs CUDA compilation tooling and cannot find a full CUDA Toolkit installation. NVIDIA driver runtime libraries alone do not include `nvcc`.

### Find the PyTorch CUDA version

Inside the LXC:

```bash
/opt/vllm/bin/python -c "import torch; print(torch.__version__); print(torch.version.cuda)"
```

For example:

```text
Torch: 2.13.0+cu130
CUDA: 13.0
```

### Install a supported versioned toolkit

List available toolkits:

```bash
apt update
apt-cache search '^cuda-toolkit-[0-9]+-[0-9]+$'
```

If CUDA 13.0 is not in the current repository but CUDA 13.1 is, install CUDA 13.1, provided the host driver meets the toolkit's minimum driver requirement.

Use the script:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh \
  lxc-install-toolkit 13.1 --apply
```

The script simulates the package transaction first. Stop if it proposes driver packages such as:

```text
cuda-drivers
nvidia-driver
nvidia-open
nvidia-kernel-dkms
nvidia-open-kernel-dkms
```

The desired package is a versioned toolkit package, such as `cuda-toolkit-13-1`; it installs compiler/tooling and should not manage the LXC kernel driver.

After a successful install:

```bash
/usr/local/cuda/bin/nvcc --version
/usr/local/cuda/bin/ptxas --version
```

## Configure the vLLM service

Set `CUDA_HOME`, `PATH`, and Triton's `ptxas` path using a systemd override:

```bash
./proxmox-lxc-nvidia-cuda-vllm-recovery.sh \
  vllm-configure 13.1 --apply
```

This creates:

```text
/etc/systemd/system/vllm.service.d/cuda.conf
```

The override contains entries similar to:

```ini
[Service]
Environment="CUDA_HOME=/usr/local/cuda-13.1"
Environment="PATH=/usr/local/cuda-13.1/bin:/opt/vllm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="TRITON_PTXAS_PATH=/usr/local/cuda-13.1/bin/ptxas"
Environment="VLLM_LOGGING_LEVEL=DEBUG"
```

It then reloads systemd, restarts vLLM, and prints current service logs.

To monitor manually:

```bash
journalctl -u vllm.service -f
```

To validate from Python:

```bash
/opt/vllm/bin/python - <<'PY'
import torch
print("torch CUDA:", torch.version.cuda)
print("available:", torch.cuda.is_available())
print("devices:", torch.cuda.device_count())
if torch.cuda.is_available():
    print("device 0:", torch.cuda.get_device_name(0))
PY
```

## LXC GPU passthrough checks

Inside the LXC, the following nodes typically need to exist:

```bash
ls -l /dev/nvidia*
```

Expected devices include:

```text
/dev/nvidia0
/dev/nvidiactl
/dev/nvidia-uvm
/dev/nvidia-uvm-tools
```

For multiple GPUs, also expose the GPU nodes you intend to use, such as `/dev/nvidia1` and `/dev/nvidia2`.

On the Proxmox host, inspect the LXC configuration:

```bash
pct config <VLLM_CTID>
```

A typical configuration includes cgroup permissions and bind mounts for NVIDIA device nodes. Example only—adapt it to the device major/minor numbers shown by `ls -l /dev/nvidia*` on your host:

```ini
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 511:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
```

Restart the LXC after changing its Proxmox configuration:

```bash
pct restart <VLLM_CTID>
```

## Troubleshooting matrix

| Error | Most likely cause | First action |
|---|---|---|
| `NVRM: API mismatch` | Host module and LXC driver libraries differ | Run host and LXC diagnostics; align LXC libraries to the exact host version |
| `Can't initialize NVML` | Mismatched `libnvidia-ml.so` or missing device access | Check `libnvidia-ml1`, `ldconfig`, `/dev/nvidia*`, and LXC configuration |
| `Failed to infer device type` | PyTorch cannot see a usable CUDA device | Check PyTorch CUDA test, NVML, device mappings, and `CUDA_VISIBLE_DEVICES` |
| `nvidia-smi: command not found` | CUDA repo's `nvidia-smi` deb is a transitional dummy without the binary (driver branches ≥560); apt reports it installed anyway | Simulate `apt -s install nvidia-driver-cuda=<host-version>-1` (reject kernel/DKMS proposals), or copy `/usr/bin/nvidia-smi` from the host via `pct push` |
| `Could not find nvcc` | CUDA Toolkit absent or `CUDA_HOME` absent | Install `cuda-toolkit-X-Y`, point `/usr/local/cuda` to it, add systemd override |
| Driver works before update, fails after PVE kernel update | DKMS module was not built for new PVE kernel | Install matching `pve-headers-$(uname -r)`, check `dkms status`, rebuild/reinstall driver, reboot |
| vLLM starts but does not use all GPUs | GPU nodes or `CUDA_VISIBLE_DEVICES` restrict visibility | Check `/dev/nvidia*`, service environment, and vLLM tensor-parallel configuration |

## Safe upgrade sequence

Use this order every time:

1. Back up or snapshot the vLLM LXC.
2. Stop vLLM and other GPU consumers.
3. Upgrade the NVIDIA driver on the Proxmox host.
4. Reboot the Proxmox host.
5. Verify the running host module with `nvidia-smi` and `/proc/driver/nvidia/version`.
6. Update each GPU-enabled LXC runtime library set to the exact host module version.
7. Install or retain the versioned CUDA Toolkit required by vLLM.
8. Verify `nvcc`, PyTorch CUDA availability, and device count.
9. Restart vLLM and review logs.

## Things to avoid

- Do not upgrade the LXC NVIDIA libraries before the host is updated and rebooted.
- Do not mix NVIDIA `.run` installers with `apt`/CUDA repository packages on the same operating-system layer.
- Do not install `nvidia-kernel-dkms`, NVIDIA kernel headers, or a kernel driver inside an LXC.
- Do not run blind `apt full-upgrade` commands in a GPU LXC with version-pinned NVIDIA libraries.
- Do not set a broad `LD_LIBRARY_PATH` to CUDA compatibility or toolkit directories unless you know the exact library needed. It can cause an LXC to load a newer `libcuda.so` or `libnvidia-ml.so` than the host module.
- Do not create an empty `/usr/local/cuda`; it must lead to a real toolkit with `bin/nvcc`.

## Quick command reference

```bash
# Host module version
cat /proc/driver/nvidia/version

# Host GPU status
nvidia-smi

# LXC NVIDIA library versions
dpkg-query -W -f='${Package} ${Version}\n' libcuda1 libnvidia-ml1

# LXC GPU node visibility
ls -l /dev/nvidia*

# PyTorch CUDA check
/opt/vllm/bin/python -c "import torch; print(torch.version.cuda, torch.cuda.is_available(), torch.cuda.device_count())"

# CUDA compiler check
/usr/local/cuda/bin/nvcc --version

# vLLM logs
journalctl -u vllm.service -b -n 200 --no-pager

# vLLM service override
systemctl cat vllm.service
```

## Sources

vLLM documents that non-container GPU installations may need a full CUDA Toolkit, a valid `CUDA_HOME`, and `nvcc` on `PATH`; it also supplies builds for CUDA 13.0. NVIDIA’s CUDA compatibility guidance documents CUDA 13.x support on driver branches at or above 580, while individual toolkit releases have their own minimum driver versions.
