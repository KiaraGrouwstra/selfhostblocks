{
  description = "Nextcloud example for Self Host Blocks";

  inputs = {
    selfhostblocks.url = "github:ibizaman/selfhostblocks";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs@{
      self,
      selfhostblocks,
      sops-nix,
    }:
    let
      system = "x86_64-linux";
      nixpkgs' = selfhostblocks.lib.${system}.patchedNixpkgs;

      basic =
        { config, ... }:
        {
          imports = [
            ./configuration.nix
            selfhostblocks.nixosModules.authelia
            selfhostblocks.nixosModules.nextcloud-server
            selfhostblocks.nixosModules.nginx
            selfhostblocks.nixosModules.sops
            selfhostblocks.nixosModules.ssl
            sops-nix.nixosModules.default
          ];

          sops.defaultSopsFile = ./secrets.yaml;

          shb.nextcloud = {
            enable = true;
            domain = "example.com";
            subdomain = "n";
            dataDir = "/var/lib/nextcloud";
            tracing = null;
            defaultPhoneRegion = "US";

            # This option is only needed because we do not access Nextcloud at the default port in the VM.
            port = 8080;

            apps = {
              previewgenerator.enable = true;
            };
          };

          # Route all `fileSecrets` contract requests through the sops provider.
          contracts.fileSecrets.defaultProvider = config.contracts.fileSecrets.providers.sops;
          # `settings.key` points the secret at its key in secrets.yaml, since the
          # contract names the sops secret by its joined `want` path
          # (`nextcloud_adminPass`), which differs from the yaml key.
          shb.sops.secret.nextcloud.adminPass.settings.key = "nextcloud/adminpass";

          # Set to true for more debug info with `journalctl -f -u nginx`.
          shb.nginx.accessLog = true;
          shb.nginx.debugLog = false;
        };

      ldap =
        { config, ... }:
        {
          shb.lldap = {
            enable = true;
            domain = "example.com";
            subdomain = "ldap";
            ldapPort = 3890;
            webUIListenPort = 17170;
            dcdomain = "dc=example,dc=com";
          };

          shb.nextcloud.apps.ldap = {
            enable = true;
            host = "127.0.0.1";
            port = config.shb.lldap.ldapPort;
            dcdomain = config.shb.lldap.dcdomain;
            adminName = "admin";
            userGroup = "nextcloud_user";
          };

          # Each `fileSecrets` request flows to the sops provider via the bus
          # (see `basic`'s `defaultProvider`). Only the yaml key needs setting,
          # since the contract names each sops secret by its joined `want` path
          # (`<consumer>_<secret>`) which differs from the key in `secrets.yaml`.
          shb.sops.secret.lldap.ldapUserPassword.settings.key = "lldap/user_password";
          shb.sops.secret.lldap.jwtSecret.settings.key = "lldap/jwt_secret";
          shb.sops.secret.nextcloud.ldapAdminPassword.settings.key = "lldap/user_password";
        };

      sso =
        { config, lib, ... }:
        {
          shb.certs = {
            cas.selfsigned.myca = {
              name = "My CA";
            };
            certs.selfsigned = {
              n = {
                ca = config.shb.certs.cas.selfsigned.myca;
                domain = "*.example.com";
                group = "nginx";
              };
            };
          };
          shb.nextcloud = {
            port = lib.mkForce null;
            ssl = config.shb.certs.certs.selfsigned.n;
          };
          shb.lldap.ssl = config.shb.certs.certs.selfsigned.n;

          services.dnsmasq = {
            enable = true;
            settings = {
              domain-needed = true;
              # no-resolv = true;
              bogus-priv = true;
              address = map (hostname: "/${hostname}/127.0.0.1") [
                "example.com"
                "n.example.com"
                "ldap.example.com"
                "auth.example.com"
              ];
            };
          };

          shb.authelia = {
            enable = true;
            domain = "example.com";
            subdomain = "auth";
            ssl = config.shb.certs.certs.selfsigned.n;
            ldapPort = config.shb.lldap.ldapPort;
            ldapHostname = "127.0.0.1";
            dcdomain = config.shb.lldap.dcdomain;
          };

          shb.nextcloud.apps.sso = {
            enable = true;
            endpoint = "https://${config.shb.authelia.subdomain}.${config.shb.authelia.domain}";
            clientID = "nextcloud";
            fallbackDefaultAuth = true;
          };

          # As in `ldap`: requests flow through the bus, so only the yaml keys
          # (which differ from the joined `want` paths) need pointing here.
          # `authelia.ldapAdminPassword` reuses the lldap user password, and
          # `nextcloud.ssoSecretForAuthelia` reuses the nextcloud SSO secret.
          shb.sops.secret.authelia = {
            jwtSecret.settings.key = "authelia/jwt_secret";
            ldapAdminPassword.settings.key = "lldap/user_password";
            sessionSecret.settings.key = "authelia/session_secret";
            storageEncryptionKey.settings.key = "authelia/storage_encryption_key";
            identityProvidersOIDCHMACSecret.settings.key = "authelia/hmac_secret";
            identityProvidersOIDCIssuerPrivateKey.settings.key = "authelia/private_key";
          };
          shb.sops.secret.nextcloud.ssoSecret.settings.key = "nextcloud/sso/secret";
          shb.sops.secret.nextcloud.ssoSecretForAuthelia.settings.key = "nextcloud/sso/secret";
        };

      sopsConfig = {
        sops.age.keyFile = "/etc/sops/my_key";
        environment.etc."sops/my_key".source = ./keys.txt;
      };
    in
    {
      nixosConfigurations = {
        basic = nixpkgs'.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sopsConfig
            basic
          ];
        };
        ldap = nixpkgs'.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sopsConfig
            basic
            ldap
          ];
        };
        sso = nixpkgs'.nixosSystem {
          system = "x86_64-linux";
          modules = [
            sopsConfig
            basic
            ldap
            sso
          ];
        };
      };

      colmena = {
        meta = {
          nixpkgs = import nixpkgs' {
            system = "x86_64-linux";
          };
          specialArgs = inputs;
        };

        basic =
          { config, ... }:
          {
            imports = [
              basic
            ];

            deployment = {
              targetHost = "example";
              targetUser = "nixos";
              targetPort = 2222;
            };
          };

        ldap =
          { config, ... }:
          {
            imports = [
              basic
              ldap
            ];

            deployment = {
              targetHost = "example";
              targetUser = "nixos";
              targetPort = 2222;
            };
          };

        sso =
          { config, ... }:
          {
            imports = [
              basic
              ldap
              sso
            ];

            deployment = {
              targetHost = "example";
              targetUser = "nixos";
              targetPort = 2222;
            };
          };
      };
    };
}
