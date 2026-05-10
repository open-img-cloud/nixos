# Custom nixos-generators format wrapper that's identical to the
# upstream `openstack` format BUT calls `make-disk-image.nix` with
# `copyChannel = false`. Saves ~500-1500 MB by not baking the full
# nixpkgs channel into the qcow2 — operators bootstrap the channel
# at first boot if they need it.
#
# Imports the same upstream openstack module so the
# `services.openssh` + `systemd.services.openstack-init` /
# `apply-openstack-data` configuration we rely on stays consistent.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    "${toString modulesPath}/virtualisation/openstack-config.nix"
  ];

  system.build.openstackImage = import "${toString modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    diskSize = "auto";
    format = "qcow2-compressed";
    copyChannel = false;
    configFile = pkgs.writeText "configuration.nix" (pkgs.lib.readFile ./config.nix);
  };

  formatAttr = "openstackImage";
  fileExtension = ".qcow2";
}
