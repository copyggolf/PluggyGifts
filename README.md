# Power of Gifts With Pluggy — Festive Edition

Responsive Thai mini-game portal at https://copyggolf.github.io/PluggyGifts/

- Catch: 28 appliance / IT items, 3 × 30 seconds, +10 / miss −5, five Cable Monsters per round (−50), one Power Buy APP bonus (+100) in round two.
- Buster: the supplied six Pluggy price signs. 01 / 02 / 03 give +10 / +25 / +50. 04 / 05 / 06 must be avoided; hitting gives −20. Three 30-second rounds.
- Mystery Shuffle: five attempts, 3–7 boxes, +50 / −20. Smooth paired arcs, desk stage and Pluggy guide, locked selection while moving.
- Original procedural festive music plus separate sound effects controls; preferences persist. Audio starts when allowed by browser autoplay policy, otherwise on the first user interaction.
- Illustrated How To Play before every game/replay. Results export as a 1080×1350 PNG with download, preview, long-press and supported mobile file-share options.
- Owner dashboard with authenticated access, online/playing counts, visitor/session totals, search, date/game filters, per-round details and current-page CSV export.

## Run

Any static web server works. Open index.html over HTTP or HTTPS (ES modules require a server). No bundler or runtime API key is needed for the games. GitHub Pages deploys from main/root.

## Statistics setup

[คู่มือภาษาไทย](SETUP-TH.md). Statistics remain disabled until config.js contains a Supabase Project URL and publishable key and backend/schema.sql has been installed. Only public publishable / legacy anon keys belong in config.js. Never include service_role keys or credentials in the public repository.

All player data tables enable RLS and deny direct public access. Public write-only functions validate visit secrets, game IDs, full round counts and summed scores; result IDs are idempotent. Owner reports check an explicit admin allowlist on every call. Scores are client-reported campaign engagement data, not authoritative contest submissions.

## Extending the game collection

1. Add the game entry (id, title, description, steps and rules) to game-config.js.
2. Register its renderer in gameRenderers in app.js. Use the shared session, loop, pause, add, feedback, roundEnd and result flow.
3. Define round count/timing explicitly (currently the shared flow treats shuffle as five attempts and other games as three rounds). Update HUD/result text and score thresholds as required.
4. Add the game ID / expected round count to backend schema constraints and validation, then update dashboard labels. Apply a migration to an existing database rather than only modifying the bootstrap script.
5. Add appropriately sized art under assets/, preload it in visuals.js, test mobile layouts, score rules, pause/visibility, result export and analytics before publishing.

## Art

Original Pluggy poses from the user-authorized Drive folder, supplied hammer mascot and six price-sign artworks are preserved. The Power Buy APP badge uses the logo printed on the supplied mascot artwork. AI showroom and product atlas created with built-in ImageGen; prompts in ART-PROMPTS.md. Web assets use AVIF/WebP to load efficiently; no device emoji are used as game props. Background music is original Web Audio synthesis with no third-party track.

## Validation

- Simulated full Catch and Shuffle games, every Buster sign, double-hit lock, pause, score totals and 60 mobile/desktop shuffle geometries.
- PostgreSQL-compatible local database: public table reads denied; non-owner report denied; visit secret checked; invalid results rejected; duplicate results not counted twice; owner totals, presence timeout and filters.
- Browser: responsive 390px layout without horizontal overflow, illustrated rules, game stage, separate audio switches, full Shuffle results, actual PNG download.
- Supabase cloud integration requires the owner's project and must be checked after installation; no live cloud project was available during this release.
