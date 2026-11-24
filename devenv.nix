{ config, lib, pkgs, ... }:
let
  root = lib.escapeShellArg config.devenv.root;
  instanceId = builtins.substring 0 12 (builtins.hashString "sha256" config.devenv.root);
  apiHostname = "api.fortune-pies-${instanceId}.localhost";
  apiPort = toString config.processes.api.ports.http.value;
  postgresSocket = "${config.env.DEVENV_RUNTIME}/postgres";
  # Both libpq and SQLx use PGHOST when a connection URI has no host.
  databaseName = "prediction_pies";
  localRole = "pies_local";
in
{
  languages.rust.enable = true;

  packages = with pkgs; [
    convco
    direnv
    fzf
    gnupg
    mdformat
    pass
    prek
    shellcheck
    shfmt
    sqlx-cli
    wl-clipboard
    xh
    zstd
  ];

  env = {
    APP_ADDR = "127.0.0.1:3000";
    API_URL = "http://${apiHostname}";
    PGDATABASE = databaseName;
    DATABASE_URL = "postgresql://${localRole}@127.0.0.1:${toString config.env.PGPORT}/${databaseName}";
  };

  services.postgres = {
    enable = true;
    listen_addresses = "127.0.0.1";
    port = 5432;
    initialDatabases = [{ name = databaseName; user = localRole; }];
    hbaConf = ''
      local all all peer
      host  ${databaseName} ${localRole} 127.0.0.1/32 trust
    '';
  };

  # Probe through the socket with the initdb user, including in the SCRAM profile.
  processes.postgres.ready.exec = lib.mkForce ''
    test -f "$PGDATA/.devenv_initialized" &&
      psql -Xw -h ${lib.escapeShellArg postgresSocket} -U "$(id -un)" -d ${databaseName} -Atc 'SELECT 1' >/dev/null
  '';

  tasks."app:migrate" = {
    exec = "sqlx migrate run";
    after = [ "devenv:processes:postgres@ready" ];
  };

  process.proxy.enable = true;
  processes.api = {
    exec = "exec env PORT=${apiPort} cargo run --locked";
    after = [ "app:migrate" ];
    ports.http.allocate = 3000;
    proxy.hostname = apiHostname;
  };

  scripts.fmt.exec = "exec bash ${root}/scripts/quality.sh fmt";
  scripts.chk.exec = "exec bash ${root}/scripts/quality.sh chk";

  profiles.lab6.module = {
    services.postgres.listen_addresses = lib.mkForce "";
    services.postgres.initialDatabases = lib.mkForce [{ name = databaseName; }];
    env.DATABASE_URL = lib.mkForce "postgresql:///${databaseName}";
    process.proxy.enable = lib.mkForce false;
    processes.api.start.enable = false;
    tasks."app:migrate".exec = lib.mkForce "true";
  };

  profiles.secrets.module = {
    services.postgres.hbaConf = lib.mkForce ''
      local all all peer
      host  prediction_pies +pies_owner 127.0.0.1/32 scram-sha-256
    '';
    tasks."app:migrate".exec = lib.mkForce ''
      set -e
      bash ${root}/scripts/with-db-password.sh bash ${root}/scripts/setup-db-role.sh
      exec bash ${root}/scripts/with-db-password.sh sqlx migrate run
    '';
    processes.api.exec = lib.mkForce "exec env PORT=${apiPort} bash ${root}/scripts/with-db-password.sh cargo run --locked";
  };

  profiles.direct.module.process.proxy.enable = lib.mkForce false;
}
