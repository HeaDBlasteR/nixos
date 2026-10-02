{ config, pkgs, ... }:

let
  # Пакеты из ветки unstable — для программ, которым нужна версия новее, чем в 26.05
  unstable = import <nixos-unstable> { config = config.nixpkgs.config; };

  # Неофициальная сборка Claude Desktop (перепаковка официального .deb от Anthropic).
  # Закреплена на конкретный коммит: обновление — только вручную, сменой хеша
  # (последний коммит: https://github.com/aaddrick/claude-desktop-debian/commits/main)
  claudeDesktopRev = "5007b9c968b87df7a3f641e4ff29958934eeb60c";
  claudeDesktop = (builtins.getFlake "github:aaddrick/claude-desktop-debian/${claudeDesktopRev}")
    .packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-fhs;

  # KDE-плагин обоев для waywallen — свой пакет, см. pkgs/waywallen-display.nix
  waywallenDisplay = pkgs.kdePackages.callPackage ./pkgs/waywallen-display.nix { };
in
{
  imports = [ ./hardware-configuration.nix ];

  # --- Загрузка ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;  # не больше 10 систем в меню: /boot всего 1 ГБ
  boot.kernelPackages = pkgs.linuxPackages_latest;  # свежее ядро = лучше поддержка нового железа

  # --- Система ---
  networking.hostName = "redmibook";
  networking.networkmanager.enable = true;          # Wi-Fi через значок в трее
  services.resolved.settings.Resolve.LLMNR = false; # не отвечать на поиск имён от чужих устройств в сети
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";

  # --- Железо ---
  hardware.enableRedistributableFirmware = true;    # прошивки Wi-Fi, звука (SOF), Bluetooth
  hardware.bluetooth.enable = true;
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-media-driver ];    # аппаратное декодирование видео Intel
  };
  services.fwupd.enable = true;                     # обновление прошивок устройств из Linux

  # --- KDE Plasma 6 ---
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1"; # VS Code, Chrome и др. Electron-приложения
                                                     # работают нативно под Wayland, без размытия на 200%

  # --- Звук ---
  services.pulseaudio.enable = false;               # старый звуковой сервер выключен, его заменяет PipeWire
  security.rtkit.enable = true;                     # приоритет реального времени для звука: не трещит под нагрузкой
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;                       # звук для 32-битных программ (нужно Steam)
    pulse.enable = true;
  };

  # --- Пользователь ---
  users.users.kuragy = {
    isNormalUser = true;
    description = "artyom";                         # отображаемое имя на экране входа
    extraGroups = [ "wheel" "networkmanager" ];     # wheel = право на sudo
  };

  # --- Nix ---
  nixpkgs.config.allowUnfree = true;                # разрешить несвободные пакеты (VS Code, Chrome, Steam)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];  # новые команды nix; flakes этим не навязываются
  nix.settings.auto-optimise-store = true;          # одинаковые файлы в /nix/store хранятся один раз
  nix.settings.substituters = [ "https://mirror.yandex.ru/nixos?priority=10" ];  # зеркало Яндекса первым,
                                                    # официальный cache.nixos.org остаётся запасным
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";            # чистить поколения старше 2 недель
  };

  # --- Совместимость и удобство разработки ---
  programs.nix-ld.enable = true;    # чтобы запускались чужие бинарники и pip-колёса с C-кодом
  programs.direnv.enable = true;    # автоактивация окружения проекта при входе в папку
  programs.git.enable = true;       # модуль сам ставит пакет git

  # --- VPN ---
  programs.amnezia-vpn = {
    enable = true;
    package = unstable.amnezia-vpn;                 # 5.0.x из unstable (в 26.05 только 4.8)
  };

  # --- Steam и запись экрана ---
  programs.steam.enable = true;                     # Steam: 32-битные библиотеки, FHS-окружение, udev
  programs.obs-studio = {                           # OBS
    enable = true;
    enableVirtualCamera = true;                     # «виртуальная камера» для Zoom/Discord (модуль ядра v4l2loopback)
  };

  # --- Flatpak ---
  services.flatpak.enable = true;                   # программы с Flathub в отдельной «коробке» (сейчас: waywallen);
                                                    # сами программы ставятся командой flatpak, не через этот файл

  # --- Базы данных ---
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    ensureDatabases = [ "kuragy" ];                 # своя база с именем пользователя: `psql` без аргументов
    ensureUsers = [{
      name = "kuragy";                              # роль = имя в Linux → вход без пароля через сокет (peer)
      ensureDBOwnership = true;                     # владелец базы kuragy
      ensureClauses.createdb = true;                # право создавать базы для лабораторных
    }];
    # Пароль (для pgAdmin/DBeaver) задаётся вручную в psql: \password
    # Не в конфиге: всё отсюда попадает в /nix/store, а его читают все пользователи
  };

  # --- Программы ---
  environment.systemPackages = with pkgs; [
    # Редакторы
    vscode

    # Claude
    claudeDesktop                   # Claude Desktop (неофициальная сборка, см. let в начале файла)
    unstable.claude-code            # Claude Code в терминале: из unstable, т.к. обновляется очень часто

    # C / C++
    gcc gdb gnumake cmake
    clang-tools                     # clangd: автодополнение и подсказки для C/C++ в редакторе
    valgrind                        # поиск утечек памяти и выходов за границы массивов
    man-pages man-pages-posix       # справка по функциям C: `man 3 printf`, `man 3p pthread_create`

    # C#
    # Две версии SDK в одной команде `dotnet`: проект сам выбирает нужную
    # через <TargetFramework> (net8.0 / net10.0). Поддержка .NET 8 — до 10.11.2026
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

    # Файлы и торренты
    qbittorrent

    # Живые обои: KDE-часть waywallen (сама программа — через Flatpak)
    waywallenDisplay

    # Разное
    wget curl htop
  ];

  system.stateVersion = "26.05";
}
