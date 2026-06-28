{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      ChallengeResponseAuthentication = false;
      UsePAM = true;
      X11Forwarding = false;
      AllowTcpForwarding = "yes";
      AllowAgentForwarding = "no";
      ClientAliveInterval = 60;
      ClientAliveCountMax = 3;
      LogLevel = "VERBOSE";
    };
  };
}
