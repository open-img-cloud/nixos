{ config, lib, pkgs, modulesPath, ... }:
{
  # Imports for the qemu/cloud profile. Note: the nixos-generators
  # `openstack` format we target also imports
  # `nixos/modules/virtualisation/openstack-config.nix` automatically,
  # which provides:
  #   - sshd with PermitRootLogin = "prohibit-password"
  #   - systemd `openstack-init` (fetches /1.0/meta-data + user-data
  #     from 169.254.169.254)
  #   - systemd `apply-openstack-data` (applies hostname + SSH key)
  #   - SSH host key fingerprint print on console
  # We don't reimplement those services here — only override what we
  # need beyond upstream defaults.
  imports = [
    "${toString modulesPath}/profiles/qemu-guest.nix"
    "${toString modulesPath}/profiles/headless.nix"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  boot.growPartition = true;
  boot.kernelParams = [ "console=tty1" ];
  boot.loader.grub.device = "/dev/vda";
  boot.loader.timeout = 1;
  boot.loader.grub.extraConfig = ''
    serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1
    terminal_output console serial
    terminal_input console serial
  '';

  # Tighten the upstream PermitRootLogin = "prohibit-password" to "no"
  # — we expose root only via the nixos user with sudo, never directly.
  services.openssh.settings.PermitRootLogin = lib.mkForce "no";

  # Enable a getty on tty1 so the qemu serial console gives a login prompt.
  systemd.services."serial-getty@tty1".enable = true;

  # Force getting the hostname from OpenStack metadata.
  networking.hostName = "";

  # Lock the root password (a literal `!` won't match any hash).
  users.users.root.hashedPassword = "!";

  # Default user (`nixos`) with passwordless sudo via wheel.
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  nix.settings.auto-optimise-store = true;
  security.sudo.wheelNeedsPassword = false;

  # ---------------------------------------------------------------------
  # Image-size shrinking
  # ---------------------------------------------------------------------
  # Default NixOS images include a full nixpkgs channel copy + full
  # documentation + X11 client libs even on headless machines. For
  # cloud workloads none of that is useful, and it pushes the qcow2
  # past 2 GB. The four levers below trim it to ~600-800 MB without
  # functional impact:

  # 1. Documentation (man, info, the static HTML NixOS manual, etc.)
  #    — ~200-300 MB. Users can install on demand if they need it.
  documentation = {
    enable = false;
    man.enable = false;
    doc.enable = false;
    info.enable = false;
    nixos.enable = false;
  };

  # 2. Strip locales down to C + en_US. Saves ~100-150 MB. Operators
  #    needing extra locales add them to their own NixOS config.
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];

  # 3. Drop the X11 client libs that some headless tools transitively
  #    pull in (~50-100 MB).
  environment.noXlibs = true;

  # `copyChannel` is a make-disk-image argument, not a NixOS module
  # option — see flake.nix.template's customFormats override which
  # pins it to false (saves ~500-1500 MB; biggest single shrink lever
  # for cloud images that bootstrap their channel via cloud-config).
}
