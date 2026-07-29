# Brain Settings → Update QA — v5.2.62

**Tag:** `v5.2.62`  
**Purpose:** Fix update failures Adrian hit, then verify Settings → Check for update / Update now.

## What this cut fixes

1. **macOS / BSD `install -D`** — already in 5.2.61; still here  
2. **Nested git checkouts break stash** — `git stash -u` failed when sibling clones (e.g. help-center) sat inside the tree → Settings → Update aborted before pull  
3. **install-user.sh mid-run self-reset** — no longer rewrites `scripts/` while bash is running that script  
4. **Build log path** — `desktop-build.log` now under profile-aware `CENTURION_HOME` (matches error dialog)  
5. **Missing icons** — skip with a note instead of aborting the whole install  

## How to test (do not `git pull` first)

Stay on whatever Brain is currently running (**5.2.59–5.2.61**). Let the app fetch.

1. Open **Sovereign AI Brain** → **Settings** → **Check for update**  
2. Expect **Update available (v5.2.62)** (or screen rebuild if git already pulled)  
3. Tap **Update now** (or **Rebuild this screen** if that is what appears)  
4. Wait for cargo rebuild (can take several minutes)  
5. Dialog: **Update complete** / **Screen rebuilt** → **Quit now**  
6. Reopen Brain → About / build stamp shows **5.2.62**

```bash
# On the Brain host after update:
cat ~/.centurion/desktop-build.json
# "version": "5.2.62"
```

### CLI smoke (optional)

```bash
centurion update --check --json --screen-version 5.2.61
# status update_available, behind >= 1 after fetch of this tag
```

## Pass criteria

- [ ] Check for update does not show a hard error  
- [ ] Update / rebuild finishes without icon/`install` abort  
- [ ] Quit + reopen loads **5.2.62**  
- [ ] Chat / Crypto Chat still works after remote restart (Linux systemd)  

## Notes

- Dirty local WIP is autostashed with `--no-restore-stash` so the screen rebuild stays clean. Restore later with `git stash list` / `git stash apply` if needed.  
- Nested checkouts are **left on disk** (not stashed) by design.  
