# Version Management Policy

## Branch strategy
- `main`: production-ready code only.
- `feature/*`: new features.
- `fix/*`: normal bug fixes.
- `hotfix/*`: urgent production fixes.

## Commit message convention
Use Conventional Commits:
- `feat: ...`
- `fix: ...`
- `refactor: ...`
- `docs: ...`
- `chore: ...`

Example:
```text
feat(auth): add SMS verification cooldown
```

## Pull Request rules
- Never push direct changes to `main`.
- One PR should solve one focused problem.
- PR must include test/build validation notes.
- PR must not include temporary/build artifacts.

## Versioning (SemVer)
- `vMAJOR.MINOR.PATCH`
- `MAJOR`: breaking change
- `MINOR`: backward-compatible feature
- `PATCH`: backward-compatible bug fix

## Release process
1. Merge approved PRs to `main`.
2. Create and push tag:
   ```bash
   git checkout main
   git pull
   git tag -a v0.1.0 -m "release: v0.1.0"
   git push origin main --tags
   ```
3. GitHub Action `Release On Tag` creates a Release with auto-generated notes.
