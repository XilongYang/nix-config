{
  programs.git = {
    enable = true;
    signing.format = "openpgp";
    settings = {
      user.name = "Xilong Yang";
      user.email = "contact@xilong.site";
      user.signingkey = "1D3659FB3DEC56A5844668EA1E1BBEE5D3C8516C";
      commit.gpgsign = true;
      gpg.program = "gpg";
      init.defaultBranch = "main";
    };
  };
}
