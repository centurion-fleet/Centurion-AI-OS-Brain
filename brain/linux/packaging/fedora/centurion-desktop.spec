Name:           centurion-desktop
Version:        %{version}
Release:        1%{?dist}
Summary:        Native Sovereign AI Brain desktop and iPhone service
License:        LicenseRef-Proprietary
URL:            https://github.com/centurion-fleet/Centurion-AI-OS
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  webkitgtk6.0-devel
BuildRequires:  vte291-gtk4-devel
BuildRequires:  desktop-file-utils
BuildRequires:  firewalld-filesystem
BuildRequires:  systemd-rpm-macros
Requires:       python3
Requires:       firewalld
Requires:       webkitgtk6.0
Requires:       nodejs
Requires:       vte291-gtk4

%description
Native GTK4/libadwaita Sovereign AI Brain desktop application and encrypted LAN
service for a Centurion Sovereign. The service allows Sovereign AI Remote on
iPhone to discover and communicate with this brain over the local network.

%prep
%autosetup

%build
cargo build --release --locked --manifest-path brain/Cargo.toml

%install
install -Dm0755 brain/target/release/centurion-desktop \
  %{buildroot}%{_bindir}/centurion-desktop
install -Dm0755 brain/target/release/centurion-remote \
  %{buildroot}%{_bindir}/centurion-remote
install -Dm0644 brain/linux/resources/com.centurion.desktop.desktop \
  %{buildroot}%{_datadir}/applications/com.centurion.desktop.desktop
for size in 16 22 24 32 48 64 128 256 512; do
  install -Dm0644 brain/linux/resources/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png \
    %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/com.centurion.desktop.png
done
install -Dm0644 brain/linux/resources/icons/hicolor/scalable/apps/com.centurion.desktop.png \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/com.centurion.desktop.png
install -Dm0644 brain/linux/packaging/systemd/centurion-remote.service \
  %{buildroot}%{_userunitdir}/centurion-remote.service
install -Dm0644 brain/linux/packaging/firewalld/centurion-remote.xml \
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
* Sat Jul 11 2026 Centurion AI OS <support@1human1ai.com> - 0.14.0-1
- Initial native GTK4 desktop and encrypted iPhone service
