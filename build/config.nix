{ config, lib, pkgs, modulesPath, ... }:
{
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

  # SSH server with root login disabled (force using the `nixos` user).
  # `lib.mkForce` because nixos-generators' built-in `openstack` format
  # already sets PermitRootLogin = "prohibit-password" via its
  # virtualisation/openstack-config.nix module; without mkForce both
  # definitions conflict at evaluation time.
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkForce "no";
  };

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

  # NixOS doesn't ship cloud-init by default. We implement a minimal
  # OpenStack metadata fetcher that pulls hostname + SSH public keys from
  # the legacy /1.0/meta-data/ endpoint of OpenStack's Nova metadata
  # service (still supported alongside the modern /openstack/latest/).
  #
  # KNOWN LIMITATION: this fetches only via HTTP from 169.254.169.254 —
  # ConfigDrive (vfat label `config-2`, used by Proxmox VE and OpenStack
  # without DHCP-served metadata) is NOT supported here. Bringing
  # ConfigDrive parity is a follow-up: mount /dev/disk/by-label/config-2,
  # parse /openstack/latest/{meta_data.json,user_data}, apply the same.
  systemd.services.openstack-init = {
    path = [ pkgs.wget ];
    description = "Fetch OpenStack Metadata on startup";
    wantedBy = [ "multi-user.target" ];
    before = [ "apply-openstack-data.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    script = ''
      metaDir=/etc/openstack-metadata
      mkdir -m 0755 -p "$metaDir"
      rm -f "$metaDir/*"

      echo "getting instance metadata..."

      wget_imds() {
        wget --retry-connrefused "$@"
      }

      wget_imds -O "$metaDir/ami-manifest-path" http://169.254.169.254/1.0/meta-data/ami-manifest-path || true
      # When no user-data is provided, the OpenStack metadata server doesn't expose the user-data route.
      (umask 077 && wget_imds -O "$metaDir/user-data" http://169.254.169.254/1.0/user-data || rm -f "$metaDir/user-data")
      wget_imds -O "$metaDir/hostname" http://169.254.169.254/1.0/meta-data/hostname || true
      wget_imds -O "$metaDir/public-keys-0-openssh-key" http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key || true
    '';
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  systemd.services.apply-openstack-data = {
    description = "Apply OpenStack Data";
    wantedBy = [ "multi-user.target" "sshd.service" ];
    before = [ "sshd.service" ];
    after = [ "fetch-openstack-metadata.service" ];
    path = [ pkgs.iproute2 ];
    script = ''
      echo "setting host name..."
      if [ -s /etc/openstack-metadata/hostname ]; then
          ${pkgs.nettools}/bin/hostname $(cat /etc/openstack-metadata/hostname)
      fi

      if ! [ -e /home/nixos/.ssh/authorized_keys ]; then
          echo "obtaining SSH key..."
          mkdir -m 0700 -p /home/nixos/.ssh
          if [ -s /etc/openstack-metadata/public-keys-0-openssh-key ]; then
              cat /etc/openstack-metadata/public-keys-0-openssh-key >> /home/nixos/.ssh/authorized_keys
              echo "new key added to authorized_keys"
              chmod 600 /home/nixos/.ssh/authorized_keys
          fi
          chown -R nixos:users /home/nixos/.ssh
      fi

      # Extract the intended SSH host key for this machine from
      # the supplied user data, if available.  Otherwise sshd will
      # generate one normally.
      userData=/etc/openstack-metadata/user-data

      mkdir -m 0755 -p /etc/ssh

      if [ -s "$userData" ]; then
        key="$(sed 's/|/\n/g; s/SSH_HOST_DSA_KEY://; t; d' $userData)"
        key_pub="$(sed 's/SSH_HOST_DSA_KEY_PUB://; t; d' $userData)"
        if [ -n "$key" -a -n "$key_pub" -a ! -e /etc/ssh/ssh_host_dsa_key ]; then
            (umask 077; echo "$key" > /etc/ssh/ssh_host_dsa_key)
            echo "$key_pub" > /etc/ssh/ssh_host_dsa_key.pub
        fi

        key="$(sed 's/|/\n/g; s/SSH_HOST_ED25519_KEY://; t; d' $userData)"
        key_pub="$(sed 's/SSH_HOST_ED25519_KEY_PUB://; t; d' $userData)"
        if [ -n "$key" -a -n "$key_pub" -a ! -e /etc/ssh/ssh_host_ed25519_key ]; then
            (umask 077; echo "$key" > /etc/ssh/ssh_host_ed25519_key)
            echo "$key_pub" > /etc/ssh/ssh_host_ed25519_key.pub
        fi
      fi
    '';

    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };

  systemd.services.print-host-key = {
    description = "Print SSH Host Key";
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" ];
    script = ''
      # Print the host public key on the console so that the user
      # can obtain it securely by parsing the output.
      echo "-----BEGIN SSH HOST KEY FINGERPRINTS-----" > /dev/console
      for i in /etc/ssh/ssh_host_*_key.pub; do
          ${pkgs.openssh}/bin/ssh-keygen -l -f $i > /dev/console
      done
      echo "-----END SSH HOST KEY FINGERPRINTS-----" > /dev/console
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };
}
