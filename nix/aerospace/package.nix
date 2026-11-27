# The AeroSpace inside Noren.app: AeroSpace built from a pinned commit of main, with the fixes it
# does not have yet (below), and noren's default config (assets/aerospace.toml) as the config it
# runs with while the user has none. Same layout as nixpkgs' aerospace:
# $out/Applications/AeroSpace.app and $out/bin/aerospace, plus man pages and shell completions.
#
# Upstream builds the app with xcodebuild and the CLI with SwiftPM (build-release.sh). Xcode is
# not in nixpkgs, so both are built here with SwiftPM: the app is the package's AeroSpaceApp
# product (the same sources Xcode builds) put into a bundle by hand, with the Info.plist keys
# upstream's Xcode project generates. Both binaries get the same build info section
# (version, commit), since the CLI warns when the app's differs.
#
# Bump: set rev and version, empty both hashes and build; the errors give the new ones. Drop a
# patch once upstream has it.
{
  lib,
  stdenv,
  fetchFromGitHub,
  swift,
  swiftpm,
  fetchSwiftPMDeps,
  apple-sdk_26,
  asciidoctor,
  complgen,
  installShellFiles,
  libicns,
  versionCheckHook,
}:
let
  rev = "d69a64d833ca2cfe0e088cfae8e5e9751ec9eff3";
  # Upstream's MACOS_MIN_DEPLOYMENT_TARGET (versions.sh)
  minMacos = "13";
  # Focus fixes, both found with a screenshot tool's area captures:
  # - native-tabs-only (https://github.com/nikitabobko/AeroSpace/discussions/2414): the native tab
  #   heuristic takes only a window still there for the background tab. An area selection overlay
  #   closing as the editor shows passed for a tab swap: the editor took the overlay's id, which was
  #   then dropped, as if the focused window had closed.
  # - focus-after-close (https://github.com/nikitabobko/AeroSpace/discussions/2415): when a closed
  #   window's focus goes to another app's window, macOS gets that window too, not the app macOS
  #   picks, often one without windows.
  # And monitor-geometry (https://github.com/nikitabobko/AeroSpace/pull/2405 at e948c6a, as is): a
  # monitor's size was taken again only when the number of monitors changed, so a screen that took
  # another's place at the same corner (unplugging an external display) kept that display's size.
  patches = [
    ./native-tabs-only.patch
    ./focus-after-close.patch
    ./monitor-geometry.patch
  ];
  # The version both binaries report: upstream's, and the patches' digest. noren restarts the
  # AeroSpace running when it reports another version than its command (BundledAeroSpace.swift),
  # so a change to the patches alone counts as another build too.
  buildVersion =
    let
      digest = builtins.hashString "sha256" (lib.concatMapStrings (builtins.hashFile "sha256") patches);
    in
    "${version}+${builtins.substring 0 8 digest}";
  version = "0.21.3-Beta-unstable-2026-11-24";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "aerospace";
  inherit version patches;

  src = fetchFromGitHub {
    owner = "nikitabobko";
    repo = "AeroSpace";
    inherit rev;
    hash = "sha256-lKgvQRngHz5wuFYf+XPv4sZddk9ADJbOSK5gwP1bmEI=";
  };

  swiftpmDeps = fetchSwiftPMDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-tpdonLti9fB3J37STn1w6vmVFFBV+ebdhFH+QEb7odE=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    swift
    swiftpm
    asciidoctor
    complgen
    installShellFiles
    libicns
  ];

  buildInputs = [
    apple-sdk_26
  ];

  env.SWIFTPM_MACOS_MIN_DEPLOYMENT_TARGET = minMacos;

  # Build against SDK 26 (upstream's release uses 26.5). nixpkgs' swift propagates SDK 27, where
  # SwiftUI's @State is a macro whose plugin (libSwiftUIMacros) ships only inside Xcode, so
  # `@State` fails with "plugin for module 'SwiftUIMacros' not found". The newest SDK among the
  # inputs wins, so this one is chosen by hand.
  preConfigure = ''
    export DEVELOPER_DIR=${apple-sdk_26}
    export SDKROOT=${apple-sdk_26.sdkroot}
  '';

  # Read by both binaries from this section (Sources/Common/buildInfo.swift): version, commit,
  # short commit
  preBuild = ''
    printf '%s\n%s\n%s\n' ${buildVersion} ${rev} ${builtins.substring 0 7 rev} > "$NIX_BUILD_TOP/build-info.txt"
    appendToVar swiftpmFlags -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __aero_build \
      -Xlinker "$NIX_BUILD_TOP/build-info.txt"
  '';

  # Man pages and completions, as upstream's build-docs.sh (build-man) and build-shell-completion.sh
  postBuild = ''
    mkdir man
    cp -r docs/*.adoc docs/assets docs/util docs/config-examples man/
    (cd man && asciidoctor -b manpage aerospace*.adoc)
    # gman renders bare .~ and /~ as ligatures
    sed -E -i 's|\.~|\.\\[ti]|g; s|/~|/\\[ti]|g' man/aerospace-test.1

    mkdir completions
    for target in "--bash aerospace" "--fish aerospace.fish" "--zsh _aerospace"; do
      complgen ''${target% *} "completions/''${target#* }" grammar/commands-bnf-grammar.txt
    done
  '';

  installPhase = ''
    runHook preInstall
    binPath="$(swiftpmBinPath)"
    install -Dm755 "$binPath/aerospace" "$out/bin/aerospace"

    app="$out/Applications/AeroSpace.app/Contents"
    install -Dm755 "$binPath/AeroSpaceApp" "$app/MacOS/AeroSpace"
    install -Dm644 ${../../assets/aerospace.toml} "$app/Resources/default-config.toml"
    png2icns "$app/Resources/AppIcon.icns" resources/Assets.xcassets/AppIcon.appiconset/icon.png
    cat > "$app/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key><string>en</string>
      <key>CFBundleExecutable</key><string>AeroSpace</string>
      <key>CFBundleIconFile</key><string>AppIcon</string>
      <key>CFBundleIdentifier</key><string>bobko.aerospace</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>CFBundleName</key><string>AeroSpace</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>${buildVersion}</string>
      <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
      <key>LSMinimumSystemVersion</key><string>${minMacos}.0</string>
      <key>LSUIElement</key><true/>
    </dict>
    </plist>
    PLIST
    echo -n "APPL????" > "$app/PkgInfo"

    installManPage man/*.1
    installShellCompletion --bash completions/aerospace
    installShellCompletion --fish completions/aerospace.fish
    installShellCompletion --zsh completions/_aerospace
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  # The app answers --version without starting (Sources/AppBundle/initAppBundle.swift)
  postInstallCheck = ''
    [ "$(timeout 30 "$out/Applications/AeroSpace.app/Contents/MacOS/AeroSpace" --version)" = "${buildVersion} ${rev}" ]
  '';

  meta = {
    description = "i3-like tiling window manager for macOS";
    homepage = "https://github.com/nikitabobko/AeroSpace";
    license = lib.licenses.mit;
    mainProgram = "aerospace";
    platforms = lib.platforms.darwin;
  };
})
