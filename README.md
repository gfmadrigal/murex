# Murex Linux Build System

**Murex** is a minimal, terminal-first Linux distribution designed for reproducible, modular builds.  
It emphasizes simplicity, control, and hybrid philosophy: Unix-y core with a minimal X stack, static linking via musl, and a carefully curated userland.

---

## Table of Contents

- [Philosophy](#philosophy)  
- [Requirements](#requirements)  
- [Repository Structure](#repository-structure)  
- [Getting Started](#getting-started)  
- [Build Process](#build-process)  
- [Configuration](#configuration)  

---

## Philosophy

Murex is designed around these principles:

1. **Terminal-first** – the shell is the primary interface; GUI programs run only if explicitly requested via `startx`.  
2. **Modularity** – each build stage is isolated and reproducible.  
3. **Hybrid simplicity** – core system uses musl, 9base or sbase utilities, runit init, and minimal userland tools.  
4. **Reproducibility** – all sources, patches, and configurations are versioned and checksum-verified.  
5. **Transparency** – scripts are readable, auditable, and self-contained.

---

## Requirements

To build Murex, you need a host Linux system with:

- `bash`, `coreutils`, `wget`, `tar`, `patch`, `make`, `gcc`  
- `sudo` access  
- ~20–30 GB of free disk space for the build  
- Internet connection for downloading source packages  

**Note:** Only x86_64 is supported at this time. Future releases may include additional architectures.

---

## Repository Structure


- `build.conf` – central configuration (paths, versions, architecture).  
- `build-all.sh` – orchestrates all scripts sequentially.  
- `scripts/` – modular, numbered build stages.  
- `sources/` – source tarballs (downloads are stored here).  
- `patches/` – custom patches and configuration files.  
- `rootfs/` – working chroot environment during build.  
- `logs/` – all build logs.  
- `cache/` – optional storage for intermediate builds.

---

## Getting Started

1. Clone the repository:

    `git clone https://github.com/yourusername/murex.git`
    `cd murex`

2. Review `build.conf` and adjust paths or versions as needed.

3. Make the main build script executable:
    `chmod +x build-all.sh`

## Build Process

The build system is **modular**. You can either run all steps at once:

    `sudo ./build-all.sh`

Or run each script individually.

**Logs** for each stage are saved under `logs/` for debugging and reproducibility.

## Configuration

- `build.conf` - set architecture, compiler flags, target paths, and versions.
- `patches/` - store all source patches and config files