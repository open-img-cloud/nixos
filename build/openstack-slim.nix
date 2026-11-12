# `openstack-slim` image variant for the native NixOS image framework
# (`image.modules`, built through `system.build.images.openstack-slim`).
#
# Same base as the built-in `openstack` variant (openstack-config.nix:
# sshd, openstack-init / apply-openstack-data metadata services), but
# make-disk-image is called with:
#   - copyChannel = false: the nixpkgs channel is not baked into the
#     qcow2 (saves ~500-1500 MB; operators bootstrap a channel at first
#     boot if they need one);
#   - format = "qcow2-compressed" and diskSize = "auto": smallest file,
#     the root partition grows on first boot.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    # Not openstack-config.nix: its EC2-style metadata fetcher waits for the
    # network and reads 169.254.169.254 only. cloud-init (config.nix) reads
    # the config drive first, without network, like the rest of the catalog.
    "${modulesPath}/image/file-options.nix"
  ];

  image.extension = "qcow2";
  system.nixos.tags = [ "openstack" ];

  system.build.image = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    inherit (config.image) baseName;
    diskSize = "auto";
    format = "qcow2-compressed";
    copyChannel = false;
    configFile = pkgs.writeText "configuration.nix" (lib.readFile ./config.nix);
  };
}
