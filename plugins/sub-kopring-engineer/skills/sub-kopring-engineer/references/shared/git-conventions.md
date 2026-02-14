# Git Conventions

## Branch Naming

| Branch | Purpose |
|--------|---------|
| `main` | Production deployment |
| `sandbox` | Sandbox environment |
| `develop` | Development branch (merges into main, sandbox) |
| `feature/*` | New feature development |
| `refactor/*` | Refactoring |
| `fix/*` | Bug fixes |
| `chore/*` | Configuration, dependencies, etc. |
| `migration/*` | Data migration |
| `test/*` | Test-related |

---

## Commit Message

### Regular Commits
```
[{ISSUE_NUMBER}] {type}: {message}
```

### When There Is No Issue Number
```
[NONE-ISSUE] {type}: {message}
```

### Hotfix
```
[HOTFIX] {message}
```

### Release
```
[RELEASE] {message}
```

### Type

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Refactoring (no functional changes) |
| `chore` | Build, configuration, dependencies, etc. |
| `docs` | Documentation changes |
| `test` | Adding/modifying tests |

---

## Pull Request

### PR Template Structure
```markdown
## Summary
<1-3 bullet points>

## Test plan
[Test checklist]
```

### PR Title
Use the same format as commit messages:
```
[{ISSUE_NUMBER}] {type}: {message}
```
