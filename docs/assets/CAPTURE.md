# Capturing the README assets

The README references three image assets in this directory:

| File | What it shows | Used in README |
|---|---|---|
| `golden-path.gif` | A 60-90s screen capture of the worker-to-investigator-to-verifier flow | Top of README, under the badges |
| `dashboard.png` | The investigator dashboard with KPIs, trend chart, overdue actions | "Try it in 5 minutes" section |
| `incident-detail.png` | An incident detail page with timeline, witnesses, attachments, CA tab | "Try it in 5 minutes" section |

The image references in `README.md` are currently inside an HTML comment block. After you drop the files in, uncomment that block and the images will render on GitHub.

## How to capture

### 1. Bring the stack up and sign in as a worker

```bash
./scripts/bootstrap.sh
```

Wait for the green "stack is ready" banner. Open http://localhost:5173 and sign in as `worker@acme.demo` / `password`.

### 2. Golden path GIF

Use the Playwright golden-path spec (`frontend/tests/e2e/golden-path.spec.ts`) as a script. Walk it manually in the browser at ~1.5x speed so the GIF is engaging:

1. Worker logs in, submits an incident with a photo and one witness
2. Sign out, sign in as `investigator@acme.demo`
3. Investigator triages, assigns a corrective action with a 7-day SLA
4. Investigator marks the incident under-investigation
5. Sign out, sign in as the action-owner; mark the CA done, attach evidence
6. Sign back in as investigator; verify the CA, close the incident
7. Open the incident detail and click through to versions to show audit history

Record with `vhs` (preferred — reproducible, scriptable), QuickTime (Cmd+Shift+5), OBS, or `peek` (Linux).

Compress to under 5MB:

```bash
ffmpeg -i raw.mov -vf "fps=12,scale=900:-1:flags=lanczos" -loop 0 docs/assets/golden-path.gif
```

### 3. Dashboard screenshot

Sign in as `investigator@acme.demo`. The dashboard view is the landing page. Capture at 1440x900 with the trend chart visible and at least three overdue actions in the table.

```bash
# Native macOS:  Cmd+Shift+4, drag selection, save as docs/assets/dashboard.png
```

### 4. Incident detail screenshot

Sign in as `investigator@acme.demo`. Open any incident from the list — `INC-0012` is a good example because it has multiple witnesses, two attachments, and one CA already assigned.

Capture at 1440x900 with the right-rail timeline visible.

## After capturing

Open `README.md` and uncomment the `<!-- README assets: -->` block (search for that comment). The image references inside will then render.
