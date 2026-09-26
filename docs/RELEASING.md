# Releasing

## Ship a version

```bash
git tag -a v1.0.1 -m "ClaudeBar 1.0.1"
git push origin v1.0.1
```

The tag must look like `vX.Y.Z` (e.g. `v1.2.0`). Anything else, like `v1.2`, fails the build.

The [release workflow](../.github/workflows/release.yml) then, in 1–2 minutes:

1. builds a universal app (Apple Silicon + Intel) with that version
2. publishes a GitHub release with `ClaudeBar.zip` and its SHA-256
3. updates the cask in [LHner1/homebrew-tap](https://github.com/LHner1/homebrew-tap)

## Check it worked

- [Actions](https://github.com/LHner1/claude-bar/actions/workflows/release.yml): the run is green.
- [Releases](https://github.com/LHner1/claude-bar/releases): the new version has `ClaudeBar.zip`.
- [homebrew-tap](https://github.com/LHner1/homebrew-tap/commits/main): a new commit *claude-bar X.Y.Z* from `github-actions[bot]`.
- Locally: `brew update && brew info --cask lhner1/tap/claude-bar` shows the new version.

If the tap wasn't updated, the finished cask is in the run's summary. Copy it to `Casks/claude-bar.rb` in the tap.

## Deploy key for the tap

The workflow pushes to the tap with an SSH deploy key that can write to `homebrew-tap` only.
The private key lives in the `HOMEBREW_TAP_DEPLOY_KEY` secret of this repo. Keys don't expire.

To set it up again (lost key, renamed repo, new tap):

```bash
ssh-keygen -t ed25519 -N "" -C "claude-bar release workflow" -f tap_key
gh repo deploy-key add tap_key.pub --allow-write -R LHner1/homebrew-tap -t "claude-bar release workflow"
gh secret set HOMEBREW_TAP_DEPLOY_KEY -R LHner1/claude-bar < tap_key
rm tap_key tap_key.pub
```

Remove the old key under homebrew-tap → Settings → Deploy keys.
