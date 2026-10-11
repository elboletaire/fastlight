# Homebrew

Fastlight is installed with Homebrew from a tap of its own,
[elboletaire/homebrew-tap](https://github.com/elboletaire/homebrew-tap):

```sh
brew install --cask elboletaire/tap/fastlight
```

`tap/` here is that repository's content and the source of truth for the
cask. The tap only ever gets copies of it.

| Path | What |
|---|---|
| `tap/Casks/fastlight.rb` | The cask. `version` and `sha256` name the last release this copy was checked against; the release workflow sets them in the tap. |
| `tap/README.md` | The tap's README. Copied by hand: the workflow only syncs the cask. |
| `../../scripts/update-cask.sh` | Sets `version` and `sha256` in a cask, from a DMG or a checksum. |

## Why a tap, not homebrew/cask

homebrew/cask doesn't take Fastlight yet, on two counts that `brew audit --cask
--new --online` reports:

- **Notability.** A self-submitted cask needs a GitHub repository at least 30
  days old with 90 forks, 90 watchers or 225 stars (30/30/75 when someone else
  submits it). See the [Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy).
- **Gatekeeper.** Casks in homebrew/cask must pass Gatekeeper, and since
  September 2026 those that don't are disabled
  ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks),
  [Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)). An ad-hoc
  signed, un-notarized DMG fails.

A third-party tap has neither requirement. Homebrew still quarantines the
download (`--no-quarantine` is gone), so macOS asks for **Open Anyway** on
the first launch, which the cask's caveats explain.

## One-time setup

1. **Create the tap repository** from `tap/`, public, named
   `homebrew-tap` (Homebrew maps `elboletaire/tap` to
   `elboletaire/homebrew-tap`):

   ```sh
   tmp="$(mktemp -d)"
   cp -R packaging/homebrew/tap/. "$tmp"
   cd "$tmp"
   git init -b main
   git add -A
   git commit -m "fastlight 0.4.0"
   gh repo create elboletaire/homebrew-tap --public \
     --description "Homebrew casks for Fastlight" --source . --push
   ```

2. **Create a token** that can push to it and nothing else: GitHub ›
   Settings › Developer settings › Personal access tokens › Fine-grained
   tokens › Generate new token.
   - Resource owner: `elboletaire`
   - Expiration: a year (and a reminder to renew it)
   - Repository access: Only select repositories › `elboletaire/homebrew-tap`
   - Repository permissions: **Contents: Read and write** (Metadata: Read-only
     comes with it). Nothing else.

3. **Add it to Fastlight** as the `HOMEBREW_TAP_TOKEN` repository secret:

   ```sh
   gh secret set HOMEBREW_TAP_TOKEN --repo elboletaire/fastlight
   ```

4. **Check** that the cask installs: `brew install --cask elboletaire/tap/fastlight`.

Without the secret, the release workflow's `homebrew` job only leaves a
notice and the tap stays where it is.

5. **Check the token**: run the *Homebrew tap* workflow (`homebrew.yml`) with
   the latest tag. When the tap already has that release it pushes nothing,
   but it still fails if the token can't push.

   ```sh
   gh workflow run homebrew.yml --repo elboletaire/fastlight -f tag=v0.5.0
   ```

## Every release

After `release.yml` publishes a `v*` release, its `homebrew` job runs
`homebrew.yml`, which:

1. checks out this repository at the tag and the tap with the token (neither
   keeps credentials in `.git/config`),
2. downloads `Fastlight-<version>.dmg` from the published release,
3. copies `tap/Casks/fastlight.rb` over the tap's cask and runs
   `scripts/update-cask.sh <version> <dmg>` on it,
4. checks that the token can push, then commits `fastlight <version>` to
   the tap and pushes, unless nothing changed (a re-run). The tap is shared
   with other projects' release workflows, so a rejected push rebases onto
   theirs and tries again.

If that step failed (an expired token, say), fix it and run `homebrew.yml`
by hand with the tag: there's no need to re-run the whole release.

So a change to the cask here reaches the tap with the next release. To push
one sooner, or to fix the tap by hand:

```sh
cp packaging/homebrew/tap/Casks/fastlight.rb ../homebrew-tap/Casks/fastlight.rb
scripts/update-cask.sh 0.5.0 Fastlight-0.5.0.dmg ../homebrew-tap/Casks/fastlight.rb
```

Check a cask without touching your own taps with `ruby -c` and, in a scratch
Homebrew (`git clone https://github.com/Homebrew/brew /tmp/brew`, with
`HOME`, `HOMEBREW_CACHE` and `HOMEBREW_TEMP` pointed at temporary
directories), `brew style` and `brew audit --cask --strict --online`.

## Once releases are notarized

When the Developer ID and notarization secrets listed at the top of
`release.yml` are set:

- Drop the "not notarized" and "signed ad hoc" paragraphs from the cask's
  `caveats` (keep the Full Disk Access one). A stable Developer ID also keeps
  the Full Disk Access grant across updates.
- `brew audit --cask --new --online elboletaire/tap/fastlight` no longer
  reports the signature. Once the repository is notable enough, the cask can
  be submitted to homebrew/cask; its autobump then keeps it current, so the
  `homebrew` job and this tap should be retired, with a `tap_migrations.json`
  in the tap pointing `fastlight` at `homebrew/cask`.
