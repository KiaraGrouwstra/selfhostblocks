nixpkgs = <nixpkgs>
patched = (import nixpkgs { }).applyPatches {
  name = "nixpkgs-patched";
  src = nixpkgs;
  patches = [
    ./patches/lldap.patch
    ./patches/0001-nixos-borgbackup-add-option-to-override-state-direct.patch
  ];
}
nixosSystem = import "${patched}/nixos/lib/eval-config.nix"
pkgs = import (patched // {
  inherit nixosSystem;
}) { }
lib = pkgs.lib
shb = let shb = (import ./lib { inherit pkgs lib; }); in shb // {
  test = pkgs.callPackage ./test/common.nix { };
  contracts = pkgs.callPackage ./modules/contracts { inherit shb; };
}
m = "audiobookshelf";
x = nixosSystem {
  modules = [
    ./lib/module.nix
    shb.test.baseModule
    ./modules/services/${m}.nix
  ];
}

# k = "backup"
k1 = "sso"
y1 = x.options.shb.${m}.${k1}.type
# y1.name == "submodule"
# # manually try and pick what goes into `submodule`
# t = (builtins.head (builtins.head y1.getSubModules).imports).options
z1 = lib.evalModules { modules = y1.getSubModules; }
r1 = builtins.removeAttrs z1.config.request [ "excludePatterns" "hooks" ]
# iterate over contracts to find which one matches
# s1 = shb.contracts.backup.mkRequester r1

k2 = "sharedSecretForAuthelia"
y2 = z1.options.${k2}.type
# y2.name == "submodule"
z2 = lib.evalModules { modules = y2.getSubModules; }
r2 = builtins.removeAttrs z2.config.request [ "excludePatterns" "hooks" ]
l2 = "secret"
s2 = shb.contracts.${l2}.mkRequester r2

# s2.request.description == z2.options.request.description
# s2.result.description == z2.options.result.description

# s == t # can't compare on this level
# ssoSecret = z1.options.result.default.path

# could i then automate this, given i would now know that shb.audiobookshelf.sso.sharedSecretForAuthelia needs a secret?
(
  let
    getPath = lib.flip (lib.foldl (lib.flip lib.getAttr));
    ksOf = lib.flip (lib.foldr (k: v: { ${k} = v; }));
    ks = [ k1 k2 ];
    w = lib.concatStringsSep "/" ([ m ] ++ ks);
    inherit (getPath ks config.shb.${m}) request;
    h = "hardcodedsecret";
    settings.content = "ssoPassword";
  in
  {
    # ok i feel like i'm essentially on the dual-link problem again here... so maybe focus on that first?
    shb = {
      ${m} = ksOf ks { inherit (config.shb.${h}.${w}) result; };
      ${h}.${w} = { inherit request settings; };
    };
  }
)
