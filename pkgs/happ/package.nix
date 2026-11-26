# Happ proxy client, repackaged from the vendor .deb (closed source, freely redistributable).
# Based on https://github.com/MrShitFox/happ-nixos (GPL-3.0).
# Update: bump `version`, then `nix store prefetch-file <url>` for the new hash.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  qt6,
  libGL,
  libx11,
  libsm,
  libice,
  libxext,
  libxi,
  libxtst,
  e2fsprogs,
  fontconfig,
  freetype,
  libgpg-error,
  openssl,
  cacert,
  coreutils,
  lsb-release,
  net-tools,
  iproute2,
  iptables,
  procps,
}:
let
  # Tools the client and its cores shell out to: device info, TUN routing, core management.
  runtimeDeps = [
    coreutils
    lsb-release
    net-tools
    iproute2
    iptables
    procps
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "happ";
  version = "4.8.8";

  src = fetchurl {
    url = "https://github.com/Happ-proxy/happ-desktop/releases/download/${finalAttrs.version}/Happ.linux.x64.deb";
    hash = "sha256-hEO2EvE1Fwm5CGgzgmge4/nj5dIBMm2MR7KJ+9MQQV8=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    qt6.wrapQtAppsHook
  ];

  # The vendor ships its own Qt runtime (qt.conf + plugins); nixpkgs' Qt wrapper would mix in a second one.
  dontWrapQtApps = true;

  buildInputs = [
    stdenv.cc.cc.lib
    libGL
    libx11
    libsm
    libice
    libxext
    libxi
    libxtst
    e2fsprogs
    fontconfig
    freetype
    libgpg-error
    qt6.qtwayland
    openssl
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    dpkg -x $src .
    mkdir -p $out/happ $out/bin
    cp -r opt/happ/. $out/happ/
    cp -r usr/share $out/share

    # The bundled Qt Wayland plugins crash on Hyprland; run through XWayland instead.
    rm -rf $out/happ/lib/plugins/wayland-*
    rm -f $out/happ/lib/plugins/platforms/libqwayland*.so

    for exe in Happ happd; do
      wrapProgram $out/happ/bin/$exe \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ openssl ]}" \
        --prefix PATH : "${lib.makeBinPath runtimeDeps}" \
        --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
        --set QT_QPA_PLATFORM xcb
    done

    ln -s $out/happ/bin/Happ $out/bin/happ

    runHook postInstall
  '';

  meta = {
    description = "Happ proxy client (Xray: VLESS/VMess/Trojan/Shadowsocks) with a TUN daemon";
    homepage = "https://github.com/Happ-proxy/happ-desktop";
    platforms = [ "x86_64-linux" ];
    mainProgram = "happ";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
