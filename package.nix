# Pogo! Pogo!, exported from the Godot project in this directory.
#
# Ships $out/share/pogo-pogo/pogo-pogo.<arch> + pogo-pogo.pck and
# $out/bin/pogo-pogo wrapping it with the runtime libraries Godot dlopens.
# No asset pack is included; the game draws placeholder shapes without one.
{
  lib,
  stdenv,
  autoPatchelfHook,
  makeWrapper,
  godot,
  godot-export-templates-bin,
  alsa-lib,
  dbus,
  fontconfig,
  freetype,
  libGL,
  libpulseaudio,
  libxkbcommon,
  systemdLibs,
  wayland,
  xorg,
  gameSrc ? lib.cleanSource ./.,
  buildStamp ? "nix",
}:

let
  system = stdenv.hostPlatform.system;
  godotTemplatesDir = builtins.replaceStrings [ "-" ] [ "." ] godot.version;
  presetByArch = {
    aarch64-linux = { preset = "Linux ARM64"; binary = "pogo-pogo.arm64"; };
    x86_64-linux = { preset = "Linux x86_64"; binary = "pogo-pogo.x86_64"; };
  };
  arch = presetByArch.${system} or (throw "pogo-pogo: no Godot export preset for ${system}");
  runtimeLibs = [
    alsa-lib
    dbus.lib
    fontconfig.lib
    freetype
    libGL
    libpulseaudio
    libxkbcommon
    systemdLibs
    wayland
    xorg.libX11
    xorg.libXcursor
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXinerama
    xorg.libXrandr
    xorg.libXrender
  ];
in
stdenv.mkDerivation {
  pname = "pogo-pogo";
  version = buildStamp;
  src = gameSrc;

  nativeBuildInputs = [ autoPatchelfHook godot makeWrapper ];
  buildInputs = runtimeLibs;
  strictDeps = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir -p project
    cp -R --no-preserve=mode,ownership "$src/." project/
    echo "${buildStamp}" > project/build-stamp.txt
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure
    export HOME=$PWD/godot-home
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_CACHE_HOME=$HOME/.cache
    mkdir -p "$XDG_DATA_HOME/godot/export_templates"
    ln -s "${godot-export-templates-bin}/share/godot/export_templates/${godotTemplatesDir}" \
      "$XDG_DATA_HOME/godot/export_templates/${godotTemplatesDir}"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cd project
    godot --headless --import || true
    godot --headless --import
    mkdir -p ../build
    godot --headless --export-release "${arch.preset}" "$PWD/../build/${arch.binary}"
    test -f "../build/${arch.binary}" || { echo "export produced no binary" >&2; ls -la ../build >&2; exit 1; }
    test -f "../build/pogo-pogo.pck" || { echo "export produced no pck" >&2; ls -la ../build >&2; exit 1; }
    cd ..
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/pogo-pogo $out/bin
    install -m755 build/${arch.binary} $out/share/pogo-pogo/${arch.binary}
    install -m644 build/pogo-pogo.pck $out/share/pogo-pogo/pogo-pogo.pck
    echo "${buildStamp}" > $out/share/pogo-pogo/build-stamp.txt
    makeWrapper $out/share/pogo-pogo/${arch.binary} $out/bin/pogo-pogo \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
    runHook postInstall
  '';

  meta = {
    description = "Pogo! Pogo!, a pogo platformer in Godot";
    platforms = builtins.attrNames presetByArch;
    mainProgram = "pogo-pogo";
  };
}
