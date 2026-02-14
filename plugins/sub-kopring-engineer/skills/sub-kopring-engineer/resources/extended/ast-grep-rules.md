# AST-grep Rule Generation (v3.0, Extended)

> Extracted from verify-protocol.md §3-5. This is an **Extended** protocol — loaded only when ast-grep is installed AND 5+ patterns are cached.

## Activation Conditions

- Pattern cache (`~/.claude/cache/sub-kopring-engineer-patterns.md`) contains 5+ patterns
- User specified `loop 3+` (indicates continuous quality management intent)

## Execution Procedure

1. Preview: `scripts/generate-ast-rules.sh [project-root] --preview`
   - Display list of rules to be generated (no files created)
2. User Confirmation: "다음 AST-grep 규칙을 생성할까요?"
3. Apply: On approval `scripts/generate-ast-rules.sh [project-root] --apply`
   - Creates rule files in `ast-grep-rules/custom/` directory
   - Auto-adds `custom` directory to `sgconfig.yml`

## Generation Targets

| Pattern Type | Generated Rule |
|-------------|----------------|
| Custom Annotations | `@AnnotationName` usage location validation |
| Naming Patterns | `*Suffix` class naming enforcement |
| Base Classes | Inheritance hierarchy consistency validation |

## Notes

- Generated rules are automatically applied during Verify phase
- On rule conflict, existing rules take priority (no overwrite)
- In CI environments, `--apply` flag enables approval-free application
