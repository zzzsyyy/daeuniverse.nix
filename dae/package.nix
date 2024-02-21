{ lib
, clang
, fetchFromGitHub
, buildGoModule
}:
buildGoModule rec {
  pname = "dae";
  version = "unstable-2024-02-20-1f96p0q";

  src = fetchFromGitHub {
    owner = "daeuniverse";
    repo = pname;
    rev = "59daed6c81d1f476d730f211129f35fdd08a8ebc";
    hash = "sha256-c7Rg20HDlJnKd9wUO5mew9wzH0MdZu6vIFIQOQxXF30=";
    fetchSubmodules = true;
  };

  vendorHash = "sha256-/r118MbfHxXHt7sKN8DOGj+SmBqSZ+ttjYywnqOIPuY=";

  proxyVendor = true;

  nativeBuildInputs = [ clang ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/daeuniverse/dae/cmd.Version=${version}"
    "-X github.com/daeuniverse/dae/common/consts.MaxMatchSetLen_=64"
  ];

  preBuild = ''
    make CFLAGS="-D__REMOVE_BPF_PRINTK -fno-stack-protector -Wno-unused-command-line-argument" \
    NOSTRIP=y \
    ebpf
  '';

  # network required
  doCheck = false;

  postInstall = ''
    install -Dm444 install/dae.service $out/lib/systemd/system/dae.service
    substituteInPlace $out/lib/systemd/system/dae.service \
      --replace /usr/bin/dae $out/bin/dae
  '';

  meta = with lib; {
    description = "A Linux high-performance transparent proxy solution based on eBPF";
    homepage = "https://github.com/daeuniverse/dae";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "dae";
  };
}
