# noren as an app bundle, $out/Applications/Noren.app: the Swift app, the Dock payload and its
# loader (Dock/), the icon, the cursors (assets/cursors), and AeroSpace (nix/aerospace): its app
# in Contents/Helpers, its `aerospace` command beside noren's, and the login agent noren registers
# to run it (Contents/Library/LaunchAgents, through SMAppService). $out/bin has both commands. The one build
# of the bundle; the release workflow signs and ships it.
{
  lib,
  aerospace,
  stdenv,
  swift,
  swiftpm,
  fetchSwiftPMDeps,
  librsvg,
  libicns,
  python3,
}:
let
  version = "0.1.0";
  # Package.swift's platforms
  minMacos = "26.0";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "noren";
  inherit version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Package.resolved
      ../Sources
      ../Tests
      ../Dock
      ../assets
    ];
  };

  swiftpmDeps = fetchSwiftPMDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-VU714uHAWvy5JChFjnQ2zsmlrSO8G1P2czVQcss8JCg=";
  };

  nativeBuildInputs = [
    swift
    swiftpm
    librsvg
    libicns
    # The cursors are baked from their drawings (assets/cursors/make.py)
    (python3.withPackages (ps: [
      ps.numpy
      ps.scipy
      ps.pillow
    ]))
  ];

  # Swift Testing runs without XCTest, which nixpkgs does not have on macOS
  doCheck = true;
  preCheck = ''
    appendToVar swiftpmFlags --disable-xctest
  '';

  # The Dock is arm64e, so its payload and the loader that starts a thread in it are too
  postBuild = ''
    $CC -arch arm64e -O2 -fobjc-arc -Wall -Werror -shared -o dock-payload.dylib Dock/payload.m \
      -I Sources/NorenPrivate \
      -framework Foundation -framework CoreGraphics
    $CC -arch arm64e -O2 -fobjc-arc -Wall -Werror -o noren-dock Dock/inject.m \
      -framework Foundation
    for size in 16 32 128 256 512; do
      rsvg-convert -w $size -h $size assets/icon.svg -o icon_$size.png
    done
    png2icns noren.icns icon_*.png
    python3 assets/cursors/make.py cursors
  '';

  installPhase = ''
    runHook preInstall
    app=$out/Applications/Noren.app/Contents
    install -Dm755 "$(swiftpmBinPath)/noren" $app/MacOS/noren
    install -Dm755 noren-dock $app/MacOS/noren-dock
    install -Dm644 dock-payload.dylib $app/Resources/dock-payload.dylib
    install -Dm644 noren.icns $app/Resources/noren.icns
    cp -R cursors $app/Resources/Cursors
    mkdir -p $app/Helpers
    cp -R ${aerospace}/Applications/AeroSpace.app $app/Helpers/
    install -Dm755 ${lib.getExe aerospace} $app/MacOS/aerospace
    # local.noren.aerospace: AeroSpace in the login session, kept running; its own agent, so noren
    # restarting or updating alone leaves it, and the windows, as they are
    install -d $app/Library/LaunchAgents
    cat > $app/Library/LaunchAgents/local.noren.aerospace.plist <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>local.noren.aerospace</string>
      <key>BundleProgram</key><string>Contents/Helpers/AeroSpace.app/Contents/MacOS/AeroSpace</string>
      <key>RunAtLoad</key><true/>
      <key>KeepAlive</key><true/>
      <key>ProcessType</key><string>Interactive</string>
      <key>LimitLoadToSessionType</key><string>Aqua</string>
    </dict>
    </plist>
    PLIST
    cat > $app/Info.plist <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key><string>noren</string>
      <key>CFBundleIdentifier</key><string>local.noren</string>
      <key>CFBundleName</key><string>Noren</string>
      <key>CFBundleIconFile</key><string>noren</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>${version}</string>
      <key>LSMinimumSystemVersion</key><string>${minMacos}</string>
      <key>LSUIElement</key><true/>
      <key>NSPrincipalClass</key><string>NSApplication</string>
    </dict>
    </plist>
    PLIST
    mkdir -p $out/bin
    ln -s ../Applications/Noren.app/Contents/MacOS/noren $out/bin/noren
    ln -s ../Applications/Noren.app/Contents/MacOS/aerospace $out/bin/aerospace
    mkdir -p $out/share
    for dir in man bash-completion fish zsh; do
      if [ -e ${aerospace}/share/$dir ]; then ln -s ${aerospace}/share/$dir $out/share/$dir; fi
    done
    runHook postInstall
  '';

  meta = {
    description = "Bar, workspace strip and window border for the AeroSpace window manager";
    homepage = "https://github.com/skytect/noren";
    license = lib.licenses.mit;
    mainProgram = "noren";
    platforms = [ "aarch64-darwin" ];
  };
})
