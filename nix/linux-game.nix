{
  buildPkgs,
  runtimePkgs,
  source,
}:
# Pogo! Pogo! for Linux devices: the game pack is exported once on the build
# machine (x86_64) and runs on the same Godot version for the target system.
# A device downloads both from a cache; nothing builds there.
let
  exporter = buildPkgs.godot;
  runtime =
    assert runtimePkgs.godot.version == exporter.version;
    runtimePkgs.godot;
  lib = buildPkgs.lib;
  gameSource = lib.fileset.toSource {
    root = source;
    fileset = lib.fileset.unions [
      (source + /project.godot)
      (source + /export_presets.cfg)
      (source + /scenes)
      (source + /src)
      (source + /schema)
      (source + /courses)
    ];
  };
  pack =
    buildPkgs.runCommand "pogo-pogo-pack"
      {
        nativeBuildInputs = [ exporter ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
        cp -r ${gameSource} source
        chmod -R u+w source
        cd source
        godot --headless --path . --import > import.log 2>&1 || true
        godot --headless --path . --import > import.log 2>&1 || true
        cat import.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' import.log; then exit 1; fi
        mkdir -p "$out"
        godot --headless --path . --export-pack "Linux ARM64" "$out/pogo-pogo.pck" > export.log 2>&1
        cat export.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' export.log; then exit 1; fi
        test -s "$out/pogo-pogo.pck"
      '';
in
buildPkgs.runCommand "pogo-pogo-linux"
  {
    passthru = { inherit pack runtime; };
    meta = {
      description = "Pogo! Pogo! with a prebuilt game pack and the matching Godot runtime";
      mainProgram = "pogo-pogo";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/pogo-pogo"
    ln -s ${pack}/pogo-pogo.pck "$out/share/pogo-pogo/pogo-pogo.pck"
    cat > "$out/bin/pogo-pogo" <<'LAUNCHER'
    #!${runtimePkgs.runtimeShell}
    # Usage: pogo-pogo [godot options] [-- game options]
    exec ${runtime}/bin/godot --main-pack ${pack}/pogo-pogo.pck ${
      lib.optionalString (
        runtimePkgs.stdenv.hostPlatform.system == "aarch64-linux"
      ) "--rendering-method gl_compatibility --rendering-driver opengl3_es"
    } "$@"
    LAUNCHER
    chmod +x "$out/bin/pogo-pogo"
  ''
