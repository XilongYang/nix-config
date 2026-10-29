{
  # RSSHub turns sites without a feed (bilibili, weibo, github, ...) into RSS.
  # It only ever needs to be reachable by goeland on this same host, so the
  # port is bound to loopback and the firewall is left untouched.
  virtualisation.oci-containers.containers.rsshub = {
    # The registry is spelled out on purpose: podman has no default and NixOS
    # sets no unqualified-search-registries, so a short name fails to resolve.
    image = "docker.io/diygod/rsshub:latest";
    autoStart = true;

    ports = [ "127.0.0.1:1200:1200" ];

    environment = {
      NODE_ENV = "production";
      TZ = "Asia/Tokyo";

      # In-memory cache: no Redis to run, and a single daily digest does not
      # need the cache to survive a restart.
      CACHE_TYPE = "memory";
      CACHE_EXPIRE = "3600";
    };
  };
}
