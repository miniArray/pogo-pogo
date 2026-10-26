{
  description = "Pogo! Pogo!: a pogo platformer in Godot 4 with player-supplied asset packs";

  # Godot 4.6.3-stable with cached binaries for x86_64-linux and aarch64-linux.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/331800de5053fcebacf6813adb5db9c9dca22a0c";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      stamp = self.shortRev or self.dirtyShortRev or "dirty";
    in
    {
      packages = forAll (pkgs: rec {
        pogo-pogo = pkgs.callPackage ./package.nix { buildStamp = stamp; };
        default = pogo-pogo;
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            godot # 4.6.x editor; `godot --headless` for checks
            godot-export-templates-bin
            python3
            python3Packages.pillow # test-pack and screenshot images
            python3Packages.jsonschema # standard validator for the course contract
            python3Packages.websockets # browser check over the DevTools protocol
            chromium # headless browser check of the web export
          ];
          # tools/export.sh links these into Godot's XDG template path.
          GODOT_EXPORT_TEMPLATES = pkgs.godot-export-templates-bin;
        };
      });
    };
}
