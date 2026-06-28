{
  service.btrfsAutoSnapshot = {
    enable = true;
    device = "/dev/disk/by-uuid/962628ce-4388-424f-b246-99d1967cd72b";
  };

  systemd.tmpfiles.rules = [
    "d /data 0777 root root -"
  ];
}
