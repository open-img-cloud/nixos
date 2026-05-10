{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    "${toString modulesPath}/../../modules/installer/cd-dvd/channel.nix"
  ];

  system.build.openstackImage = import "${toString modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    copyChannel = true;
    format = "qcow2-compressed";
    configFile = pkgs.writeText "configuration.nix" (pkgs.lib.readFile ./config.nix);
  };

  formatAttr = "openstackImage";
  fileExtension = ".qcow2";
}
