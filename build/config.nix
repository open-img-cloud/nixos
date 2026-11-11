{ config, lib, pkgs, modulesPath, ... }:
{
  # Imports for the qemu/cloud profile. Note: the `openstack-slim`
  # image variant we build (openstack-slim.nix) also imports
  # `nixos/modules/virtualisation/openstack-config.nix` automatically,
  # which provides:
  #   - sshd with PermitRootLogin = "prohibit-password"
  #   - systemd `openstack-init` (fetches /1.0/meta-data + user-data
  #     from 169.254.169.254)
  #   - systemd `apply-openstack-data` (applies hostname + SSH key)
  #   - SSH host key fingerprint print on console
  # We don't reimplement those services here: only override what we
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
  # tty1 for the VNC console, ttyS0 (last, so it owns /dev/console) for the
  # serial log that `openstack console log show` and Proxmox read
  # (IMAGE_STANDARDS.md, section C).
  boot.kernelParams = [ "console=tty1" "console=ttyS0,115200n8" ];
  boot.loader.grub.device = "/dev/vda";
  boot.loader.timeout = 1;
  boot.loader.grub.extraConfig = ''
    serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1
    terminal_output console serial
    terminal_input console serial
  '';

  # Tighten the upstream PermitRootLogin = "prohibit-password" to "no":
  # we expose root only via the nixos user with sudo, never directly.
  services.openssh.settings.PermitRootLogin = lib.mkForce "no";
  # Public key only: keyboard-interactive can still ask a password through
  # PAM (reported by the catalog runtime smoke).
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;
  services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce false;

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

  # Upstream's metadata fetcher (openstack-config.nix -> ec2-data.nix)
  # writes the instance SSH key to root's authorized_keys only. Root
  # login is disabled above, so without this the image is unreachable:
  # install the same key for the `nixos` user (IMAGE_STANDARDS.md, D.3).
  systemd.services.oic-default-user-ssh-key = {
    description = "Install the instance SSH key for the nixos user";
    wantedBy = [ "multi-user.target" ];
    after = [ "apply-ec2-data.service" ];
    wants = [ "apply-ec2-data.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      key=/etc/ec2-metadata/public-keys-0-openssh-key
      if [ -s "$key" ]; then
        install -d -m 0700 -o nixos -g users /home/nixos/.ssh
        install -m 0600 -o nixos -g users "$key" /home/nixos/.ssh/authorized_keys
        echo "SSH key installed for nixos"
      else
        echo "no SSH key in instance metadata"
      fi
    '';
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

  # 1. Documentation (man, info, the static HTML NixOS manual, etc.):
  #    ~200-300 MB. Users can install on demand if they need it.
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

  # 3. (Removed) `environment.noXlibs = true`: option deleted in
  #    NixOS 25.05+. Upstream rationale: it caused surprising
  #    breakages. The X libs we'd save are small (~50-100 MB) and
  #    the bigger wins are the channel + docs.

  # `copyChannel` is a make-disk-image argument, not a NixOS module
  # option: see openstack-slim.nix, which
  # pins it to false (saves ~500-1500 MB; biggest single shrink lever
  # for cloud images that bootstrap their channel via cloud-config).
}
