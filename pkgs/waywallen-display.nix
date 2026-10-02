# KDE-часть waywallen: плагин обоев Plasma, который показывает кадры от
# программы waywallen (она ставится отдельно, через Flatpak).
# Собирается из исходников, а не из готового zip: готовый .so собран под
# обычные дистрибутивы и на NixOS может уронить plasmashell.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  gettext,
  patchelf,
  qtbase,
  qtdeclarative,
  libGL,
  vulkan-headers,
  vulkan-loader,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "waywallen-display";
  version = "0.4.0";

  # Закреплено на тег + хеш: обновление — только вручную, сменой версии и хеша
  src = fetchFromGitHub {
    owner = "waywallen";
    repo = "waywallen-display";
    tag = "v${finalAttrs.version}";
    hash = "sha256-qFCKUQSfx+bjbbfkj/REIf4w4U09sPCcilHI0lE6YqQ=";
  };

  # Своя доработка: ползунки насыщенности, яркости и контраста в настройках
  # обоев KDE (MultiEffect поверх кадра). При обновлении версии может
  # перестать применяться — тогда пересоздать патч.
  patches = [ ./waywallen-display-color-adjust.patch ];

  nativeBuildInputs = [
    cmake
    pkg-config
    gettext # msgfmt: переводы
    patchelf
  ];

  buildInputs = [
    qtbase
    qtdeclarative
    libGL # заголовки EGL/GLES
    vulkan-headers
    vulkan-loader # vulkan.pc для pkg-config
  ];

  # Это библиотека-плагин, а не программа: оборачивать нечего
  dontWrapQtApps = true;

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeBool "WAYWALLEN_DISPLAY_PLUGIN_QML" true)
    # QML-модуль — туда, где его ищет Qt на NixOS
    (lib.cmakeFeature "QML_INSTALL_DIR" "${placeholder "out"}/${qtbase.qtQmlPrefix}")
  ];

  postInstall = ''
    # KDE-пакет обоев (org.waywallen.kde) — отдельный компонент CMake
    cmake --install . --component kde_extension \
      --prefix $out/share/plasma/wallpapers
  '';

  # libEGL и libvulkan подгружаются через dlopen во время работы:
  # без явного пути NixOS их не найдёт
  postFixup = ''
    for so in $(find $out -name '*.so*' -type f); do
      patchelf --add-rpath ${lib.makeLibraryPath [ libGL vulkan-loader ]} "$so"
    done
  '';

  meta = {
    description = "KDE Plasma wallpaper plugin for the waywallen daemon";
    homepage = "https://github.com/waywallen/waywallen-display";
    license = with lib.licenses; [ mit gpl2Plus ];
    platforms = lib.platforms.linux;
  };
})
