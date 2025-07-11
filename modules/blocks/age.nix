{ config, lib, pkgs, ... }:
let
  inherit (lib) mapAttrs mkOption;
  inherit (lib.types) attrsOf anything submodule;

  contracts = pkgs.callPackage ../contracts {};

  cfg = config.shb.age;
in
{
  options.shb.age = {
    secret = mkOption {
      description = "Secret following the [secret contract](./contracts-secret.html).";
      default = {};
      type = attrsOf (submodule ({ name, options, ... }: {
        options = contracts.secret.mkProvider {
          settings = mkOption {
            description = ''
              Settings specific to the Age provider.

              This is a passthrough option to set [agenix options](https://github.com/ryantm/agenix/blob/main/modules/age.nix).

              Note though that the `mode`, `owner`, and `group`
              are managed by the [shb.age.secret.<name>.request](#blocks-age-options-shb.age.secret._name_.request) option.
            '';

            type = attrsOf anything;
            default = {};
          };

          resultCfg = {
            path = "/run/secrets/${name}";
            pathText = "/run/secrets/<name>";
          };
        };
      }));
    };
  };

  config = {
    age.secrets = let
      attrs = ["mode" "owner" "group"];
      mkSecret = n: secretCfg: (lib.getAttrs attrs secretCfg.request) // secretCfg.settings;
    in mapAttrs mkSecret cfg.secret;
  };
}
