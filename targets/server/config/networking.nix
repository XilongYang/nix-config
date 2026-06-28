{
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Tokyo";

  networking.hosts = { };

  networking.firewall.allowedTCPPorts = [ 8000 ];
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.5.27.10";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.5.27.1";
  networking.nameservers = [ "1.1.1.1" ];
}
