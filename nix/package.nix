# noren as an app bundle, $out/Applications/Noren.app: the Swift app, the Dock payload and its
# loader (Dock/), and the icon. The one build of the bundle; the release workflow uses it too.
{
  lib,
  stdenv,
  swift,
  swiftpm,
  librsvg,
  libicns,
}:
let
  version = "0.0.0";
  # Package.swift's platforms
  minMacos = "26.0";
in
stdenv.mkDerivation {
  pname = "noren";
  inherit version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Sources
      ../Tests
      ../Dock
      ../assets
    ];
  };

  nativeBuildInputs = [
    swift
    swiftpm
    librsvg
    libicns
  ];

  # Swift Testing runs without XCTest, which nixpkgs does not have on macOS
  doCheck = true;
  preCheck = ''
    appendToVar swiftpmFlags --disable-xctest
  '';

  # The Dock is arm64e, so its payload and the loader that starts a thread in it are too
  postBuild = ''
    $CC -arch arm64e -O2 -fobjc-arc -Wall -Werror -shared -o dock-payload.dylib Dock/payload.m \
      -framework Foundation -framework CoreGraphics
    $CC -arch arm64e -O2 -fobjc-arc -Wall -Werror -o noren-dock Dock/inject.m \
      -framework Foundation
    for size in 16 32 128 256 512; do
      rsvg-convert -w $size -h $size assets/icon.svg -o icon_$size.png
    done
    png2icns noren.icns icon_*.png
  '';

  installPhase = ''
    runHook preInstall
    app=$out/Applications/Noren.app/Contents
    install -Dm755 "$(swiftpmBinPath)/noren" $app/MacOS/noren
    install -Dm755 noren-dock $app/MacOS/noren-dock
    install -Dm644 dock-payload.dylib $app/Resources/dock-payload.dylib
    install -Dm644 noren.icns $app/Resources/noren.icns
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
    runHook postInstall
  '';

  meta = {
    description = "Bar, workspace strip and window border for the AeroSpace window manager";
    homepage = "https://github.com/skytect/noren";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
  };
}
