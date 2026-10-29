{
  virtualisation.hypervGuest.enable = true;

  virtualisation.podman = {
    enable = true;

    # Provide `docker` as an alias and /run/docker.sock, so container tooling
    # that only speaks the Docker API keeps working.
    dockerCompat = true;
    dockerSocket.enable = true;

    # Let containers resolve each other by name on user-defined networks.
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.oci-containers.backend = "podman";
}
