# Release checklist (do these before sharing the APK)

Nothing in this project has been run yet, so work top to bottom.

## 1. Make it run
- [ ] Open in Godot 4.3+, fix any parse errors shown in the Output panel.
- [ ] Run `tests/test_runner.tscn` headless; all lines should say PASS.
- [ ] Play each campaign and the sandbox once on desktop.

## 2. Playtest and balance
- [ ] Can the player win and lose each campaign? Tune starting forces in `data/campaigns/*/scenario.json`.
- [ ] Try easy / normal / hard AI. Adjust `THRESHOLDS` and `RECRUIT_EVERY` in `scripts/ai/ai_player.gd`.
- [ ] Check dialogs and the map on a real phone (small screens, notches).

## 3. History pass
- [ ] Verify each entry in `docs/SOURCES.md` against the listed books and record page numbers.
- [ ] Upgrade or downgrade confidence tags; replace anything that cannot be verified.

## 4. Android build
- [ ] Set a real package name in `export_presets.cfg` (`package/unique_name`), not `com.example.swarajya`.
- [ ] Create your own release keystore; never commit it (see `.gitignore`).
- [ ] Bump `version/code` for every upload; `version/name` is shown to players.
- [ ] Export a release build; install on at least two devices; test save, load and a full campaign.
- [ ] The game requests no permissions and makes no network calls. Keep it that way, or add a privacy policy.

## 5. Store listing (if publishing)
- [ ] Screenshots, icon (replace the placeholder `icon.svg`), short description that states the history is simplified.
- [ ] Credit sources; make sure all art and any future music are original or properly licensed.
