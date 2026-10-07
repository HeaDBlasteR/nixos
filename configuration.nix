{ config, pkgs, ... }:

let
  # Пакеты из ветки unstable
  unstable = import <nixos-unstable> { config = config.nixpkgs.config; };

  claudeDesktopRev = "5007b9c968b87df7a3f641e4ff29958934eeb60c";
  claudeDesktop = (builtins.getFlake "github:aaddrick/claude-desktop-debian/${claudeDesktopRev}")
    .packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-fhs;

  # KDE-плагин обоев для waywallen
  waywallenDisplay = pkgs.kdePackages.callPackage ./pkgs/waywallen-display.nix { };

  # Драйвер сканера отпечатков
  fingerprintOcv = pkgs.callPackage ./pkgs/fingerprint-ocv.nix { };
in
{
  imports = [ ./hardware-configuration.nix ];

  # --- Загрузка ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;  # не больше 10 систем в меню: /boot всего 1 ГБ
  boot.loader.timeout = 1;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # --- Система ---
  networking.hostName = "redmibook";
  networking.networkmanager.enable = true;
  services.resolved.settings.Resolve.LLMNR = false;
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";

  # --- Железо ---
  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth.enable = true;
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-media-driver ];
  };
  services.fwupd.enable = true;

  # --- Отпечаток пальца ---
  # Сканер FPC 10a5:9201 не поддерживается libfprint, поэтому вместо fprintd
  # работает fingerprint-ocv
  services.fprintd.enable = true;
  systemd.services.fprintd.serviceConfig = {
    ExecStart = [
      ""                                            # убрать запуск самого fprintd
      "${fingerprintOcv}/bin/fingerprint-ocv --bus=system --min-score=0.30 --min-area=150000"
    ];
    Restart = "on-failure";                         # перезапуск, если драйвер упадёт
    RestartSec = "1s";
  };
  systemd.services.fprintd.wantedBy = [ "multi-user.target" ];
  # Вход в SDDM — только по паролю
  security.pam.services.sddm.fprintAuth = false;

  # --- KDE Plasma 6 ---
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1"; # Electron-приложения

  # --- Программы по умолчанию ---
  xdg.mime.defaultApplications = pkgs.lib.genAttrs [
    "text/plain"
    "text/markdown" "application/json" "application/x-yaml" "application/toml"
    "text/x-csrc" "text/x-c++src" "text/x-chdr" "text/x-c++hdr"
    "text/x-csharp" "text/x-python" "text/x-python3" "application/x-shellscript"
    "text/javascript" "text/css"
    "text/x-cmake" "text/x-makefile" "text/x-nix"
    "application/sql" "text/x-sql"
  ] (_: "code.desktop");

  # --- Звук ---
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- Пользователь ---
  users.users.kuragy = {
    isNormalUser = true;
    description = "artyom";
    extraGroups = [ "wheel" "networkmanager" ];
  };

  # --- Nix ---
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.settings.substituters = [ "https://mirror.yandex.ru/nixos?priority=10" ];  # зеркало Яндекса первым,
                                                    # официальный cache.nixos.org остаётся запасным
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # --- Совместимость и удобство разработки ---
  programs.nix-ld.enable = true;    # чтобы запускались чужие бинарники и pip-колёса с C-кодом
  programs.direnv.enable = true;
  programs.git.enable = true;

  # --- VPN ---
  programs.amnezia-vpn = {
    enable = true;
    package = unstable.amnezia-vpn;                 # 5.0.x из unstable
  };

  # --- Steam и запись экрана ---
  programs.steam.enable = true;
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
  };

  # --- Разделы дисков ---
  programs.partition-manager.enable = true;

  # --- Flatpak ---
  services.flatpak.enable = true;

  # --- Синхронизация хранилища Obsidian ---
  services.syncthing = {
    enable = true;
    user = "kuragy";
    dataDir = "/home/kuragy";
    openDefaultPorts = true;
    settings = {
      options.urAccepted = -1;
      devices.pc = {
        id = "WAYEFTG-H3OQ7XN-TITS4NG-ERDC4JG-EWAKDZG-YQTTON3-XPMUR37-R5YSJA2";
        name = "ПК";
        addresses = [ "tcp://10.8.1.5:22000" ];
      };
      folders.obsidian = {
        id = "obsidian";
        label = "Obsidian";
        path = "/home/kuragy/Obsidian";
        devices = [ "pc" ];
        versioning = {
          type = "trashcan";
          params.cleanoutDays = "30";
        };
      };
    };
  };

  # --- Шрифты ---
  fonts.fontconfig.localConf = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <match target="pattern">
        <test name="family" qual="any" compare="eq"><string>Calibri</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Times New Roman</string><string>Liberation Serif</string></edit>
      </match>
      <match target="pattern">
        <test name="family" qual="any" compare="eq"><string>Calibri Light</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Times New Roman</string><string>Liberation Serif</string></edit>
      </match>
      <match target="pattern">
        <test name="family" qual="any" compare="eq"><string>Cambria</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Times New Roman</string><string>Liberation Serif</string></edit>
      </match>
    </fontconfig>
  '';

  # --- Базы данных ---
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    ensureDatabases = [ "kuragy" ];
    ensureUsers = [{
      name = "kuragy";
      ensureDBOwnership = true;
      ensureClauses.createdb = true;
    }];
  };

  # --- Программы ---
  environment.systemPackages = with pkgs; [
    # Редакторы
    vscode
    obsidian

    # Claude
    claudeDesktop
    unstable.claude-code

    # Nix
    nil                             # языковой сервер Nix

    # C / C++
    gcc gdb gnumake cmake
    clang-tools                     # автодополнение и подсказки для C/C++ в редакторе
    valgrind                        # поиск утечек памяти и выходов за границы массивов
    man-pages man-pages-posix       # справка по функциям C: `man 3 printf`, `man 3p pthread_create`

    # C#
    (dotnetCorePackages.combinePackages [
      dotnetCorePackages.sdk_8_0
      dotnetCorePackages.sdk_10_0
    ])

    # TypeScript
    nodejs typescript

    # Python
    python313

    # Базы данных
    pgadmin4-desktopmode
    dbeaver-bin

    # Браузеры и общение
    google-chrome
    telegram-desktop

    # Офис
    libreoffice-qt6-still
    hunspellDicts.ru_RU             # русская проверка орфографии

    # Файлы и торренты
    qbittorrent

    # Живые обои
    waywallenDisplay

    # Видео
    haruna                          # видеоплеер для KDE

    # Архивы (Ark использует их для .7z и .rar)
    p7zip unrar

    # Учёба
    xournalpp                       # рукописные пометки поверх PDF
    qalculate-qt                    # калькулятор

    # Система и диски
    kdePackages.filelight           # чем занят диск
    kdePackages.isoimagewriter      # запись загрузочной флешки
    btop                            # монитор ресурсов

    # Терминал
    ripgrep fd bat tree
    yt-dlp

    # Разное
    wget curl htop
  ];

  system.stateVersion = "26.05";
}
