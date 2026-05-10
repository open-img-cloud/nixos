<div id="top"></div>

<!-- PROJECT SHIELDS -->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![GPL-2.0 License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">

<h3 align="center">NixOS Cloud Images</h3>

  <p align="center">
    Signed NixOS images for OpenStack, built declaratively from a Nix
    flake
    <br />
    <br />
    <a href="https://github.com/open-img-cloud/nixos/issues">Report a bug</a>
    ·
    <a href="https://github.com/open-img-cloud/nixos/issues">Request a feature</a>
  </p>
</div>

## About

This repo builds [NixOS][nixos] cloud images via a Nix flake that
imports [nix-community/nixos-generators][nixos-generators] and
declares an OpenStack-friendly NixOS configuration. Build is driven by
the openimages.cloud reusable [`build-nix-flake-image.yml`][reusable]
workflow (third paradigm after libguestfs and DIB).

NixOS is a third paradigm vs the cloud-init-based distros (alpaquita,
alpine, AL2023, …): the OS doesn't ship cloud-init at all; instead a
custom systemd service (`openstack-init`) defined in `build/config.nix`
fetches the OpenStack `/1.0/meta-data/` HTTP endpoint at boot to apply
hostname + SSH keys.

This pipeline is the openimages.cloud-aligned successor of the legacy
[`linitio/openstack-nixos-image`][legacy] (2024-04 vintage), rebuilt
around cosign-signed releases, R2/Garage object storage, and the
`build-nix-flake-image.yml` reusable.

## Versioning

`<version>` is the **NixOS release** (`YY.MM`, e.g. `25.11`), which
maps to the matching `nixos-X.Y` branch of `github.com/NixOS/nixpkgs`.
The flake input `nixpkgs.url` is rewritten to that branch at build
time by `build/nix-build.sh` (substituting the literal `VERSION` token
in `flake.nix.template`).

`system.stateVersion` is set to the same value, pinning the on-disk
defaults to that release.

| NixOS release | Channel        |
|---------------|----------------|
| 25.05         | nixos-25.05    |
| 25.11         | nixos-25.11 ← default |

## Where to download

Public CDN, served via Cloudflare in front of an R2 bucket (mirror of
the source-of-truth Garage):

| URL pattern                                                                | Cache policy                  |
|----------------------------------------------------------------------------|-------------------------------|
| `https://images.openimages.cloud/nixos/<version>/<filename>`               | `max-age=31536000, immutable` |
| `https://images.openimages.cloud/nixos/latest/<filename>`                  | `max-age=300`                 |

Browse: [images.openimages.cloud/nixos/latest/][latest]

Filename: `nixos-<version>-x86_64.qcow2` (e.g. `nixos-25.11-x86_64.qcow2`).

## Verify before deploy

cosign 3.x:

```sh
sha256sum -c <filename>.sha256                    # integrity
cosign verify-blob \
    --bundle <filename>.bundle \
    --new-bundle-format \
    --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-nix-flake-image\.yml@' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    <filename>                                     # provenance
```

## How to use

### OpenStack

```sh
# Pull the qcow2 (replace <V> with the desired NixOS release, e.g. 25.11)
curl -fLO https://images.openimages.cloud/nixos/<V>/nixos-<V>-x86_64.qcow2

openstack image create \
    --disk-format qcow2 --container-format bare \
    --min-disk 5 \
    --file nixos-<V>-x86_64.qcow2 \
    "NixOS <V>"
```

The default user is `nixos` (passwordless sudo via wheel). SSH keys
come from `/1.0/meta-data/public-keys/0/openssh-key` of the OpenStack
metadata service.

### Proxmox VE

> ⚠️ **Known limitation**: the current `openstack-init` service in
> `build/config.nix` only fetches metadata over HTTP from
> `169.254.169.254`. **ConfigDrive** (the vfat label `config-2` Proxmox
> emits) is **not** read. NixOS images deployed on Proxmox won't pick
> up SSH keys / hostname unless the network metadata is reachable.
> Tracked as a follow-up — see the comment in `config.nix`.

## Release flow

1. **`watch.yml`** runs daily 06:59 UTC, calls `build/detect-upstream.sh`
   which queries `api.github.com/repos/NixOS/nixpkgs/branches` and
   emits the highest `nixos-X.Y` branch.
2. If the version differs from `VERSION`, the workflow opens a PR
   `auto/upstream-bump`.
3. Merging the PR + pushing a `v<VERSION>` tag fires `release.yml`,
   which calls the shared `build-nix-flake-image.yml@main` reusable
   workflow.
4. The reusable runs `build/nix-build.sh` inside the `nixos/nix:2.21.2`
   container on a GH-hosted ubuntu-latest runner. The script enables
   flakes + kvm system features in `/etc/nix/nix.conf`, renders
   `flake.nix` from `flake.nix.template`, runs `nix build .#openstack`,
   and copies the result to the workflow's output dir.
5. Output qcow2 is signed (cosign keyless), bundled with MANIFEST,
   uploaded to Garage + R2, and Cloudflare cache for `latest/` is
   purged.

## Repository layout

```
VERSION                                     single line, e.g. "25.11"
build/
  nix-build.sh                              builds the flake's `openstack` package
  detect-upstream.sh                        prints latest nixos-X.Y branch on stdout
  flake.nix.template                        flake.nix with VERSION token to substitute
  config.nix                                NixOS module (bootloader, openssh, openstack-init)
  openstack-qcow2-compressed.nix            custom DIB-style format wrapper
.github/workflows/
  release.yml                               calls build-nix-flake-image.yml on tag push
  watch.yml                                 daily cron, calls upstream-watch.yml
.gitignore                                  repo-local override for global build/ exclusion
LICENSE                                     GPL-2.0
```

## Notes vs the cloud-init-based repos

- **No cloud-init.** NixOS implements its own metadata fetching via the
  `openstack-init` systemd service in `build/config.nix`. The org-wide
  `99_oic-policy.cfg` cloud-init drop-in injected by the libguestfs
  reusable does NOT apply here.
- **No smoke test in the reusable.** NixOS's metadata model is custom
  enough that the generic ConfigDrive smoke loop wouldn't validate
  anything useful. Validation happens after publication via deploying
  the image into an OpenStack tenant.
- **Build is deterministic.** Two builds of the same `flake.nix` +
  `flake.lock` produce byte-identical qcow2s — Nix's whole point.

## Contributing

Fork, branch, PR. Keep changes focused. The most-touched file is
`build/config.nix` — the NixOS module that defines the image. Adding
ConfigDrive support there (parse `/dev/disk/by-label/config-2`) is
the highest-priority follow-up.

## License

Distributed under the GPL-2.0 License. See `LICENSE`.

## Contact

Kevin Allioli — kevin@stackops.ch · [@stackopshq](https://twitter.com/stackopshq)

Project: [open-img-cloud/nixos](https://github.com/open-img-cloud/nixos)

[nixos]: https://nixos.org/
[nixos-generators]: https://github.com/nix-community/nixos-generators
[reusable]: https://github.com/open-img-cloud/.github/blob/main/.github/workflows/build-nix-flake-image.yml
[legacy]: https://github.com/linitio/openstack-nixos-image
[org]: https://github.com/open-img-cloud
[shared]: https://github.com/open-img-cloud/.github
[latest]: https://images.openimages.cloud/nixos/latest/

<!-- shields -->
[contributors-shield]: https://img.shields.io/github/contributors/open-img-cloud/nixos.svg?style=for-the-badge
[contributors-url]: https://github.com/open-img-cloud/nixos/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/open-img-cloud/nixos.svg?style=for-the-badge
[forks-url]: https://github.com/open-img-cloud/nixos/network/members
[stars-shield]: https://img.shields.io/github/stars/open-img-cloud/nixos.svg?style=for-the-badge
[stars-url]: https://github.com/open-img-cloud/nixos/stargazers
[issues-shield]: https://img.shields.io/github/issues/open-img-cloud/nixos.svg?style=for-the-badge
[issues-url]: https://github.com/open-img-cloud/nixos/issues
[license-shield]: https://img.shields.io/github/license/open-img-cloud/nixos.svg?style=for-the-badge
[license-url]: https://github.com/open-img-cloud/nixos/blob/main/LICENSE
