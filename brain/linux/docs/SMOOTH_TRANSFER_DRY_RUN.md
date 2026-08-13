# Smooth Transfer — advisor dry-run card

Replace the 2-hour terminal playbook with this checklist.

## Customer (5 steps)

1. Sign in → **Account / Get Brain**
2. Click **Centurion AI OS Brain for Linux** (only live option)
3. Extract the archive → run `./install.sh`
4. Open **Sovereign AI Brain** from the app menu
5. Confirm **Transfer complete** → continue Chat (Soul / sessions kept)

## Staff verification (before republish)

1. Account overview + Get Brain show four platforms; only Linux downloads
2. Test machine already has `~/.centurion` (Soul + ≥1 session) and a working Python `centurion` / venv
3. Download published Smooth Transfer tarball via Linux card (**no SSH**)
4. Run `install.sh` only → app menu shows Sovereign AI Brain
5. Open Brain → Transfer dialog → Soul/sessions present → one chat turn with **no** status/terminal spam
6. License still active (no re-activate unless hardware fingerprint changed)

## Republish

```bash
# On private Linux build host:
desktop-native/scripts/install-user.sh
desktop-native/scripts/package-brain-release.sh
# Upload desktop-native/dist/centurion-brain-*-linux-*.tar.gz via Admin → Releases
```

If binaries are not available on this workstation, package on the usual build host, then publish from Admin.
