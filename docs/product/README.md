# Product Docs

This directory is intentionally generic and mostly empty in Harness v0.

When a user provides a project spec, derive smaller product contract files here
instead of keeping one large spec as the living plan. Name files by the product
domains that actually exist in that spec, for example `overview.md`,
`billing.md`, `workflows.md`, `permissions.md`, or `api-conventions.md`.

Do not create domain files before the spec just to fill the folder. Empty
structure is healthier than fake product truth.

## Current Product Contracts

| File | Covers |
| --- | --- |
| [overview.md](overview.md) | What the product is: spec → ABAP → SAP via MCP-RFC bridge; components; constraints |
| [spec-to-abap-workflow.md](spec-to-abap-workflow.md) | The end-to-end workflow: intake, read-before-write, push, validation ladder, human-owned steps, SAP risk mapping |
| [sap-systems.md](sap-systems.md) | Target systems/profiles, write policy, bridge prerequisites |
| [abap-conventions.md](abap-conventions.md) | Naming, packages, authoring and change-safety rules for generated ABAP |
| `docs/sap-knowledge/` + `.claude/skills/` + `.claude/agents/` | Agent-facing SAP module knowledge, the packaged skills driving the spec-to-abap pipeline, and read-only analysis subagents |

## Update Rule

When behavior changes:

1. Update the affected product doc.
2. Update or create the story packet.
3. Update durable proof status with `scripts/bin/harness-cli story add` or
   `scripts/bin/harness-cli story update`.
4. Record a decision if the change affects architecture, scope, risk, or a
   previously settled product rule.
