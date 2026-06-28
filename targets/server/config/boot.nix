{
  boot = {
    initrd.availableKernelModules = [ "sd_mod" "sr_mod" ];
    initrd.kernelModules = [ ];
    kernelParams = [ ];
    kernelModules = [ ];
    extraModulePackages = [ ];

    loader = {
      timeout = 0;
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };
}
