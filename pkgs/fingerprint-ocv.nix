# Драйвер сканера отпечатков FPC 10a5:9201 (стоит в Redmi Book 14 2024).
# libfprint этот сканер не поддерживает, поэтому вместо fprintd запускается
# fingerprint-ocv: он занимает то же имя на D-Bus (net.reactivated.Fprint),
# и PAM, KDE и fprintd-enroll работают с ним как с обычным fprintd.
# Оригинал заброшен в 2023 году и без исправлений Kiwironic не работает:
# проверка отпечатка не проходила, база была доступна всем на запись.
# Всё закреплено на коммиты + хеши: обновление — только вручную.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  libusb1,
  libevent,
  dbus,
  openssl,
  opencv,
}:

let
  # Исправления Kiwironic (patches/) — отдельный репозиторий
  kiwi = fetchFromGitHub {
    owner = "Kiwironic";
    repo = "xiaomi-fpc9201-fingerprint-linux";
    rev = "89291ca77b77fdfbb4d63eb43c5fe256f257fe55";
    hash = "sha256-9eTl6ZsAbhvV5Xf/zdPIwoclFxIs9zjJkgHoay7P1M0=";
  };

  # Подмодули оригинала, на тех же коммитах, что записаны в нём.
  # fetchSubmodules не подходит: подмодуль vcpkg указан по SSH и не скачается,
  # а он и не нужен — библиотеки берутся из nixpkgs (патч 06)
  jinx = fetchFromGitHub {
    owner = "vrolife";
    repo = "jinx";
    rev = "154366c25a0b8c3f531c37efbfffa4934a138523";
    hash = "sha256-5Brg1gizUsW2w6hAh+ApksUvtJyCfef7zxyRzAYVqD4=";
  };
  asyncusb = fetchFromGitHub {
    owner = "vrolife";
    repo = "asyncusb";
    rev = "d9e29478037123cfff8f009d7112250c4b2fd3df";
    hash = "sha256-hNoqsh9gu+MI/1NcyJor0qDElAsmcAGzkhTqW11O2Jk=";
  };
  asyncdbus = fetchFromGitHub {
    owner = "vrolife";
    repo = "asyncdbus";
    rev = "62c2c87092c7674fcd3ec98573a2a436bfff9d83";
    hash = "sha256-EueQvMT3FjBEXLoHr7LnczMRG7cEy80VjMGt47h6Amw=";
  };
in
stdenv.mkDerivation {
  pname = "fingerprint-ocv";
  version = "0-unstable-2022-12-04";

  src = fetchFromGitHub {
    owner = "vrolife";
    repo = "fingerprint-ocv";
    rev = "7691977ca8d28050f95a42454880b572ce7f9d5e";
    hash = "sha256-te08FtxsVnAkP7F+BsDbkMEriGsgqBVlW8lAJbNNDt0=";
  };

  # Положить подмодули на их места (из Nix store они только для чтения)
  postUnpack = ''
    for m in jinx:${jinx} asyncusb:${asyncusb} asyncdbus:${asyncdbus}; do
      rm -rf "$sourceRoot/''${m%%:*}"
      cp -r "''${m#*:}" "$sourceRoot/''${m%%:*}"
    done
    chmod -R u+w "$sourceRoot"
    # Готовая программа из репозитория не используется: только сборка из исходников
    rm -f "$sourceRoot/fingerprint-ocv"
  '';

  # Порядок и папки — как в patches/README.md: 00, 01, 10, 11 относятся
  # к подмодулям и накладываются изнутри них
  patches = map (n: "${kiwi}/patches/${n}") [
    "02-cvext-matching-robustness.patch"
    "03-main-umask-security.patch"
    "04-fpc9201-signal-and-logging.patch"
    "05-fingerprint-atomic-save.patch"
    "06-cmake-system-libs.patch"
    "07-opencv5-module-names.patch"
    "08-polkit-authorization.patch"
    "09-disconnect-mid-scan-crash.patch"
    "12-crypto-evp-mac-hmac.patch"
  ];

  postPatch = ''
    patch -d jinx -p1 < ${kiwi}/patches/00-jinx-result-move-assign.patch
    patch -d asyncdbus -p1 < ${kiwi}/patches/01-asyncdbus-no-abort-on-spurious-wakeup.patch
    patch -d jinx -p1 < ${kiwi}/patches/10-jinx-queue2-get-return.patch
    patch -d jinx -p1 < ${kiwi}/patches/11-jinx-error-message-fallback.patch
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    libusb1
    libevent
    dbus
    openssl
    opencv
  ];

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeBool "BUILD_TESTING" false)
    # Сетевые части jinx драйверу не нужны: не собирать их вовсе
    (lib.cmakeBool "JINX_BUILD_HTTP" false)
    (lib.cmakeBool "JINX_BUILD_EVDNS" false)
    (lib.cmakeBool "JINX_BUILD_CJSON" false)
  ];

  meta = {
    description = "Userspace driver for the FPC 10a5:9201 fingerprint sensor, replacing fprintd";
    homepage = "https://github.com/Kiwironic/xiaomi-fpc9201-fingerprint-linux";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "fingerprint-ocv";
  };
}
