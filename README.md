# Isolated Runtime for Arbitrary JavaScript with Firecracker

This repository shows a minimal setup for running externally provided JavaScript (assumed potentially unsafe) in a host-isolated microVM powered by [Firecracker](https://firecracker-microvm.github.io/).

## Purpose

This repository is a minimal example for running untrusted JavaScript in an isolated microVM for a short-lived execution.
The goal is to prevent execution-side effects from reaching the host. The code disk is mounted read-only so the executed code cannot write changes back.
The scope is limited to the basic Firecracker flow: boot, run, and stop.

## Quick Start

```bash
just download          # Fetch kernel and base rootfs
just prepare-rootfs    # Build rootfs and app disk (stores index.js in app disk)
just run               # Start microVM and run index.js in isolation

tail -f /tmp/firecracker.out /tmp/firecracker.err # View logs
```

## Structure

This repository uses two disks attached to the VM:

- `rootfs.ext4`: Base disk with the guest OS, runtime (Node.js), and boot init script (`/init` from `init.sh`).
- `app.ext4`: Code disk that contains only the target `index.js`.
