{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib) mkOption;
  inherit (lib.types)
    attrsOf
    anything
    ;

  cfg = config.shb.sops;

  contract = "fileSecrets";
  providerName = "sops";
  inherit (lib.contract.forModule config) fileSecrets;

  # The provider option lives at `shb.sops.secret`, so `fulfill'`'s absolute leaf
  # `path` is `secretRoot ++ <consumer> ++ <secret>`. Drop the root prefix to get
  # the per-consumer path we key the secret by.
  secretRoot = [
    "shb"
    "sops"
    "secret"
  ];
  qualifiedName = path: lib.concatStringsSep "_" (lib.drop (lib.length secretRoot) path);
in
{
  imports = [
    ../../lib/module.nix
  ];

  # The contract provider option reads `config.contracts` for its
  # `default`/`type`, which cannot be evaluated in the sandboxed split options
  # doc build. Document it in the eager build instead.
  meta.buildDocsInSandbox = false;

  options.shb.sops.secret = mkOption {
    description = "Secret following the `fileSecrets` contract, provided through sops-nix.";
    default = config.contracts.${contract}.providerRequests.${providerName};
    defaultText = lib.literalExpression "config.contracts.${contract}.providerRequests.${providerName}";
    type = fileSecrets.mkProviderType {
      overrides.request = {
        owner.default = "root";
        group.default = "root";
      };
      providerOptions = {
        settings = mkOption {
          description = ''
            Settings specific to the Sops provider.

            This is a passthrough option to set [sops-nix options](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix).

            Note though that the `mode`, `owner`, `group`, and `restartUnits`
            are managed by the [request](#blocks-sops-options-shb.sops.secret) option.
          '';
          type = attrsOf anything;
          default = { };
        };
      };
      # Key the result path by the full `want` path (not the leaf `name`) so two
      # consumers requesting a same-named secret (e.g. `lldap.jwtSecret` and
      # `authelia.jwtSecret`) do not collide. The generated `sops.secrets` key
      # below derives from the same path, so they always agree.
      fulfill' = { path, ... }: { path = "/run/secrets/${qualifiedName path}"; };
    };
  };

  config = {
    contracts.${contract}.providers.${providerName}.module = options.shb.sops.secret;

    sops.secrets = lib.concatMapNestedAttrs' options.shb.sops.secret.type (
      path: secretCfg:
      # `concatMapNestedAttrs'` gives the path relative to the provider option
      # root; re-prefix with `secretRoot` so `qualifiedName` matches the
      # absolute-path form `fulfill'` receives.
      {
        ${qualifiedName (secretRoot ++ path)} = {
          inherit (secretCfg.request) mode owner group;
        }
        // lib.optionalAttrs (secretCfg.request.restartUnits != [ ]) {
          inherit (secretCfg.request) restartUnits;
        }
        // secretCfg.settings;
      }) cfg.secret;
  };
}
