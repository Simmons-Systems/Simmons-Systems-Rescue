<!-- Thanks for the PR! See CONTRIBUTING.md for the full guide. -->

## Summary

<!-- 1–3 sentences. What does this PR change and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Docs / tooling only
- [ ] Refactor (no behaviour change)
- [ ] Breaking change (describe migration)

## Checklist

- [ ] `pre-commit run --all-files` is clean
- [ ] `./tests/shellcheck.sh` passes
- [ ] Build scripts dry-run (`bin/build-rescue-usb.sh --dry-run --output /tmp/test.img`) still produces a valid image, if you touched them
- [ ] README and docs updated if public behavior changed
- [ ] `CHANGELOG.md` entry added under `[Unreleased]`
