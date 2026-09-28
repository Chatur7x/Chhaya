# Contributing to Chhaya

Thank you for contributing. Chhaya is community open source (MIT).

## Workflow

1. Sync `main`: `git fetch --all --prune && git checkout main && git pull origin main`
2. Create a branch: `git checkout -b <type>-<short-name>`
   (`feat-`, `fix-`, `docs-`, or `part-XX-` for roadmap work)
3. Make small, focused commits: one logical change per commit.
4. Push the branch and open a pull request against `main`.
5. Wait for review. Do not merge your own PRs.

## Commit format

```
<type>: <what> — <why>
```

Example: `fix: validate onion node keys — reject all-zero points`

## Quality gates (must pass before review)

```bash
flutter analyze        # zero issues
flutter test           # all green
cd backend/server && npm run lint && npm test
```

## Rules

- Never commit secrets, `.env` files, keys, or tokens.
- Never commit generated files (`build/`, `dist/`, `.dart_tool/`).
- Never delete a passing test. Fix forward.
- No `print()` in Dart — use `ChhayaLog` from `lib/core/log.dart`.
- No `any` in TypeScript — validate with zod.
- UI changes need screenshots in the PR body.
- Follow the frozen stack in `pubspec.yaml` / `backend/server/package.json`.
  New dependencies require maintainer approval.
