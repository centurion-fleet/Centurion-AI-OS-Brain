Name:           centurion-desktop
Version:        0.14.0
Release:        1%{?dist}
Summary:        Native Personal Centurion desktop and iPhone service
License:        MIT
URL:            https://github.com/NousResearch/Centurion-AI-OS
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  vte291-gtk4-devel
BuildRequires:  desktop-file-utils
BuildRequires:  firewalld-filesystem
BuildRequires:  systemd-rpm-macros
Requires:       python3
Requires:       firewalld
Requires:       vte291-gtk4

%description
Native GTK4/libadwaita desktop application and encrypted LAN service for a
Personal Centurion. The service allows CenturionAI Remote on iPhone to discover
and communicate with this Centurion over the local network.

%prep
%autosetup

%build
cargo build --release --locked --manifest-path desktop-native/Cargo.toml

%install
install -Dm0755 desktop-native/target/release/centurion-desktop \
  %{buildroot}%{_bindir}/centurion-desktop
install -Dm0755 desktop-native/target/release/centurion-remote \
  %{buildroot}%{_bindir}/centurion-remote
install -Dm0644 desktop-native/resources/com.centurion.desktop.desktop \
  %{buildroot}%{_datadir}/applications/com.centurion.desktop.desktop
for size in 16 22 24 32 48 64 128 256 512; do
  install -Dm0644 desktop-native/resources/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png \
    %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png
done
install -Dm0644 desktop-native/resources/icons/hicolor/scalable/apps/com.centurion.desktop.png \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/com.centurion.desktop.png
install -Dm0644 desktop-native/packaging/systemd/centurion-remote.service \
  %{buildroot}%{_userunitdir}/centurion-remote.service
install -Dm0644 desktop-native/packaging/firewalld/centurion-remote.xml \
  %{buildroot}%{_prefix}/lib/firewalld/services/centurion-remote.xml

desktop-file-validate \
  %{buildroot}%{_datadir}/applications/com.centurion.desktop.desktop

%post
%firewalld_reload

%postun
%firewalld_reload

%files
%license LICENSE
%{_bindir}/centurion-desktop
%{_bindir}/centurion-remote
%{_datadir}/applications/com.centurion.desktop.desktop
%{_datadir}/icons/hicolor/*/apps/com.centurion.desktop.png
%{_userunitdir}/centurion-remote.service
%{_prefix}/lib/firewalld/services/centurion-remote.xml

%changelog
* Sat Jul 11 2026 Centurion AI OS <engineering@centurion.ai> - 0.14.0-1
- Initial native GTK4 desktop and encrypted iPhone service
