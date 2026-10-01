# PawSync landing page

The local PawSync page has a compact feature overview, a bottom-right companion preview, and an interactive pet studio. No Paw-Paw artwork, logo, proprietary app code or marketing copy is bundled.

Serve from the PawSync directory:

```sh
python3 scripts/serve_website.py
```

Open `http://127.0.0.1:8767/` (which forwards to `/website/`) or go directly to `http://127.0.0.1:8767/website/`. The preview server disables browser caching so edits appear after reload. This page is local and has not been published.

The pet studio uses all 15 sprite sheets bundled with the native app: nine original PawSync frame pets and six imported OpenPets companions. `python3 scripts/sync_website_pets.py` refreshes the website sheets and small gallery thumbnails from those exact app resources. Visitors can choose a pet, preview the free and paid wardrobe visuals, resize it, switch the preview background, and try wave, walk, jump, work, nap, dance, and click/drag reactions. The browser preview reacts to keydown events only while the page is focused and never reads key contents. It pauses when hidden and respects reduced-motion settings.

The download section shows the actual local development app path rather than inventing a notarized download or checkout. Studio choices are browser-only; they do not change the native app's wardrobe or unlock state. There are no analytics or external asset requests.

The website is a local product preview, not a released download. See `../docs/openpets-feature-report.md` for the broader native feature plan and verification requirements.

Run `node scripts/check_website.mjs` from the repository root with the local server running to verify desktop and mobile layouts, the 15-pet gallery, the favicon, and studio interactions. It saves screenshots under `build/`.
