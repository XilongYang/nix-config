{config, pkgs, lib, ... } :
{
  # networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Asia/Tokyo";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.hosts = {
  };

  networking.firewall.allowedTCPPorts = [ 8000 ];
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "10.5.27.10";
    prefixLength = 24;
  }];
  networking.defaultGateway = "10.5.27.1";
  networking.nameservers = ["1.1.1.1"];
}
