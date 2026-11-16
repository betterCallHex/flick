## Checking a change in the running app

Run it with `scripts/drive.sh` (muted, in the background, its own data) and drive it with `agent-desktop`; `scripts/drive.sh stop` before you finish. See the Build section of `README.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for betterCallHex/flick, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
