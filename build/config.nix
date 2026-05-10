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
}
