{
  description = "ONIX forge development shell";

  inputs = {
    # Pinned to the same nixpkgs generation as Gearbox because nixGL's NVIDIA
    # path still depends on the older nvidia-x11/generic.nix `kernel` argument.
    nixpkgs.url = "github:NixOS/nixpkgs?rev=4c1018dae018162ec878d42fec712642d214fdfa";
    nixgl.url = "github:nix-community/nixGL";
  };

  outputs = { nixpkgs, nixgl, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
            overlays = [
              (final: prev: {
                xorg = prev.xorg // {
                  libX11 = final.libx11;
                  libxcb = final.libxcb;
                  libxshmfence = final.libxshmfence;
                };
              })
            ];
            config = {
              allowUnfree = true;
              nvidia.acceptLicense = true;
            };
          }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default =
          let
            nvidiaVersion = builtins.getEnv "NVIDIA_VERSION";
            hasNvidia = nvidiaVersion != "";

            nixglPkgs = import "${nixgl}/default.nix" ({
              inherit pkgs;
            } // pkgs.lib.optionalAttrs hasNvidia {
              inherit nvidiaVersion;
              nvidiaHash = null;
            });

            nixGLTarget =
              if hasNvidia
              then "${nixglPkgs.nixGLNvidia}/bin/nixGLNvidia-${nvidiaVersion}"
              else "${nixglPkgs.nixGLIntel}/bin/nixGLIntel";
            nixVulkanTarget =
              if hasNvidia
              then "${nixglPkgs.nixVulkanNvidia}/bin/nixVulkanNvidia-${nvidiaVersion}"
              else "${nixglPkgs.nixVulkanIntel}/bin/nixVulkanIntel";

            nixGLAlias = pkgs.runCommand "nixGL" { } ''
              mkdir -p $out/bin
              ln -s ${nixGLTarget} $out/bin/nixGL
            '';
            nixVulkanAlias = pkgs.runCommand "nixVulkan" { } ''
              mkdir -p $out/bin
              ln -s ${nixVulkanTarget} $out/bin/nixVulkan
            '';

            guiLibs = with pkgs; [
              alsa-lib
              libx11
              libxcb
              libxcursor
              libxi
              libxkbcommon
              libxrandr
              libxshmfence
              mesa
              udev
              vulkan-loader
              wayland
            ];
          in
          pkgs.mkShell {
            packages = with pkgs; [
              bashInteractive
              cargo
              clang
              cmake
              coreutils
              cpio
              curl
              dosfstools
              e2fsprogs
              findutils
              gawk
              gzip
              gnugrep
              gnused
              gnumake
              gnutar
              gptfdisk
              just
              kmod
              mdbook
              openssl
              openssh
              OVMF.fd
              parted
              pkg-config
              qemu
              rustc
              shellcheck
              sqlite
              systemd
              util-linux
              xfsprogs
              xz
              zstd

              nixGLAlias
              nixVulkanAlias
              nixglPkgs.nixGLIntel
              nixglPkgs.nixVulkanIntel
            ] ++ pkgs.lib.optionals hasNvidia [
              nixglPkgs.nixGLNvidia
              nixglPkgs.nixVulkanNvidia
            ] ++ guiLibs;

            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath guiLibs;

            shellHook = ''
              export ONIX_OVMF_CODE="${pkgs.OVMF.fd}/FV/OVMF_CODE.fd"
              export ONIX_OVMF_VARS_TEMPLATE="${pkgs.OVMF.fd}/FV/OVMF_VARS.fd"
              export ONIX_SYSTEMD_BOOT_EFI="${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi"
            '';
          };
      });
    };
}
