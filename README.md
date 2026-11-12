<p align="center">
  <a href="https://openimages.cloud/images/nixos/">
    <img src="https://openimages.cloud/img/og/nixos.png" alt="NixOS cloud image for OpenStack and Proxmox" width="720">
  </a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/nixos/"><img alt="Latest version" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Fnixos%2Flatest%2FMANIFEST.json&query=%24.version&label=latest&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://github.com/open-img-cloud/nixos/actions/workflows/release.yml"><img alt="Release" src="https://github.com/open-img-cloud/nixos/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://openimages.cloud/verify/"><img alt="Signed with Sigstore cosign" src="https://img.shields.io/badge/signed-Sigstore%20cosign-2459c4"></a>
  <a href="https://openimages.cloud/quality/"><img alt="Boot-tested on OpenStack" src="https://img.shields.io/badge/boot--tested-OpenStack-2459c4"></a>
  <a href="LICENSE"><img alt="License GPL-2.0" src="https://img.shields.io/badge/license-GPL--2.0-555"></a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/nixos/"><b>Catalog page</b></a> ·
  <a href="https://images.openimages.cloud/nixos/latest/">Download</a> ·
  <a href="https://openimages.cloud/verify/">Verify</a> ·
  <a href="https://github.com/open-img-cloud/docs">Documentation</a> ·
  <a href="https://github.com/open-img-cloud/nixos/issues">Report an issue</a>
</p>

NixOS cloud image (qcow2) for **OpenStack** and **Proxmox**: built declaratively from a Nix
flake with the native NixOS image framework, made ready for both clouds with the same rules as
every [openimages.cloud](https://openimages.cloud) image, signed with Sigstore cosign and
boot-tested on a real OpenStack before it is published.

## At a glance

| | |
|---|---|
| **Upstream** | [NixOS](https://nixos.org/), the `nixos-<version>` branch of [nixpkgs](https://github.com/NixOS/nixpkgs) |
| **Default user** | `nixos`, SSH key only, passwordless `sudo` (group `wheel`) |
| **Firmware** | BIOS |
| **Format** | qcow2, x86_64, root filesystem grown to the disk at first boot |
| **Version** | the NixOS release, `YY.MM`, e.g. `26.05` ([all versions](https://images.openimages.cloud/nixos/versions.json)) |
| **Support** | Follows the NixOS release cycle (two releases a year, `YY.05` and `YY.11`) |

## Quick start

```sh
# Latest version and its file name, from the signed manifest
M=https://images.openimages.cloud/nixos/latest/MANIFEST.json
V=$(curl -fsS $M | jq -r .version); F=$(curl -fsS $M | jq -r .filename)
curl -fLO https://images.openimages.cloud/nixos/$V/$F
```

<details>
<summary><b>OpenStack</b></summary>

```sh
openstack image create --disk-format qcow2 --container-format bare \
  --property os_distro=nixos --property os_version=$V \
  --property hw_qemu_guest_agent=yes --property os_admin_user=nixos \
  --file "$F" "NixOS $V"
```

The full property set (SCSI disk, multiqueue, quiesced snapshots) is on the
[catalog page](https://openimages.cloud/images/nixos/) and in
[`index.json`](https://images.openimages.cloud/index.json). To keep images up to date
automatically, use [oic-sync](https://github.com/open-img-cloud/oic-sync).

</details>

<details>
<summary><b>Proxmox VE</b></summary>

The commands to create a cloud-init template from this image are on the
[catalog page](https://openimages.cloud/images/nixos/).

</details>

<details>
<summary><b>Verify the signature</b></summary>

```sh
curl -fLO https://images.openimages.cloud/nixos/$V/$F.bundle
cosign verify-blob "$F" --bundle "$F.bundle" \
  --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-(libguestfs|dib|nix-flake|freebsd)-image\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

</details>

## What this image contains

The whole image is declared in [`build/config.nix`](build/config.nix) and
[`build/openstack-slim.nix`](build/openstack-slim.nix), built by `nix build .#openstack` from
[`build/flake.nix.template`](build/flake.nix.template), whose `nixpkgs` input and
`system.stateVersion` are set to the release in [`VERSION`](VERSION):

- the `qemu-guest` and `headless` profiles, GRUB with the console on `tty1` and `ttyS0`;
- cloud-init with the openimages.cloud policy: config drive read first, then the metadata
  service; it sets the hostname, grows the root filesystem and installs the instance key for
  `nixos`. The network stays with NixOS (DHCP, IPv4 and IPv6), since the NixOS cloud-init
  distro cannot render network configuration;
- sshd with public keys only, no root login, root password locked;
- a slim image: no nixpkgs channel copied into the disk, no documentation, only the `C` and
  `en_US` locales, compressed qcow2.

Every release must pass the same [runtime contract](https://openimages.cloud/quality/) on
OpenStack: SSH with the injected key, cloud-init finished, DNS, hostname, root filesystem grown,
passwordless `sudo`, IPv6 address and egress.

### Note

The flake follows the `nixos-<version>` branch; the repository has no `flake.lock`, so each
build takes the head of that branch at build time.

## How releases happen

1. Every day at 06:59 UTC a watcher looks for a new NixOS release tag in nixpkgs and opens a
   pull request that bumps [`VERSION`](VERSION).
2. Merging it is all it takes: the release is tagged, built, signed, boot-tested and
   published, then `latest/` and the [catalog](https://openimages.cloud/images/) move to it.

This repository only holds what is specific to NixOS: [`VERSION`](VERSION),
the [`build/`](build) flake files, [`build/nix-build.sh`](build/nix-build.sh),
[`build/detect-upstream.sh`](build/detect-upstream.sh) and thin workflows calling the shared
pipeline in [`open-img-cloud/.github`](https://github.com/open-img-cloud/.github).

## License

The build tooling in this repository is under [GPL-2.0](LICENSE). The image keeps the licensing
terms of NixOS and of each package it contains. This project is not affiliated with the NixOS project.
