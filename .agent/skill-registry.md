# Antigravity Agent OS ?" Skill Registry & Routing Index

> **Operating Principle**: Maximum capability with minimum necessary context. Load only the minimum sufficient skills on-demand. Never load skills merely because they exist.

---

## Priority Tiers

| Priority Tier | Scope & Purpose | Activation Policy |
| :--- | :--- | :--- |
| **P0 ?" Baseline** | Core reliability, token budgeting, project memory | **Always active** across every task |
| **P1 ?" Core Workflow** | Feature dev, debugging, testing, review, security | **Automatic** when lifecycle phase matches |
| **P2 ?" Technology** | Frameworks, languages, databases (Flutter, Supabase, etc.) | **Automatic** when task touches specific tech |
| **P3 ?" Specialized** | Spec Kit, complex migrations, architecture overhauls | **Selective** only for high-risk/multi-phase tasks |

---

## P0: Always-On Engineering Baseline

| Skill | Purpose | Trigger / Condition | Scope | Overlap / Conflict Resolution |
| :--- | :--- | :--- | :--- | :--- |
| **`gravitas`** | Model-agnostic reliability runtime: scoped recon, minimal edits, evidence verification | Always active on repository changes | Global | **Primary reliability layer**. Overrides generic retry behavior. |
| **`context-budget`** | Strict token management: bounded reads, targeted search, zero redundant queries | Always active across all tool use | Global | Enforces minimum sufficient context across all workflows. |
| **`project-memory`** | Durable project architecture, commands, conventions, pitfalls | Read at task start; updated on durable learnings | Project (`.agent/`) | Single source of durable project knowledge. |

---

## P1: Automatic Core Engineering Workflows

| Skill | Purpose | Trigger / Condition | Priority | Dependencies | Overlap Handling |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`debugging`** | 8-step root cause analysis; reproduce -> isolate -> fix -> verify | Bug reports, error traces, failing tests | P1 | None | Replaces unguided retries. |
| **`feature-development`** | Architecture-aware, incremental feature delivery | New feature, endpoint, or UI addition | P1 | `project-memory` | Standard implementation path. |
| **`testing`** | Targeted test execution & honest evidence reporting | Post-edit verification, test creation | P1 | None | Must run before declaring done. |
| **`code-review`** | 8-point review with strict severity tiers (`CRITICAL`..`NIT`) | PR reviews, pre-merge validation | P1 | Git diff | Objective, evidence-backed only. |
| **`security`** | Audit auth, secrets, SQL injection, RLS, safe I/O | Code touching auth, DB, tokens, endpoints | P1 | None | Activates automatically on sensitive paths. |
| **`brainstorming`** | Explore intent, requirements, and design options | Ambiguous or open-ended requests | P1 | None | Run before heavy implementation plans. |
| **`writing-plans`** | Multi-phase atomic implementation plan authoring | Non-trivial multi-file changes | P1 | `feature-development` | Keep proportional to task complexity. |
| **`executing-plans`** | Disciplined execution of written implementation plan | When an implementation plan is approved | P1 | `writing-plans` | Executes with verification gates. |
| **`test-driven-development`** | Write failing test first, make green, refactor | Critical business logic, algorithms | P1 | `testing` | Used where TDD discipline is required. |
| **`verification-before-completion`**| Final sanity gate and evidence check | Before reporting task completion | P1 | `gravitas` | Mandates actual output verification. |

---

## P2: Technology & Domain Specific (Activated on Matching Tech)

| Skill | Tech / Stack | Purpose | Activation Condition |
| :--- | :--- | :--- | :--- |
| **`flutter-expert`** | Flutter / Dart | Mobile state, ChangeNotifier, widget optimization | Dart/Flutter files (`lib/`, `pubspec.yaml`) |
| **`postgres-best-practices`** | PostgreSQL | Schema design, indexing, queries, RLS policies | SQL files, migrations, database queries |
| **`supabase-automation`** | Supabase | Auth, PostgreSQL functions, Edge Functions, RLS | Supabase migrations, client configs |
| **`android_ui_verification`** | Android / ADB | UI verification on Android emulator/device | Android build/test tasks |
| **`react-best-practices`** | React / Next.js | Modern hook patterns, RSC, Next.js App Router | Web frontend projects |
| **`typescript-expert`** | TypeScript | Strict types, utility types, modern Node/TS | TS/JS projects |
| **`python-patterns`** | Python | Clean architecture, typing, pytest | Python scripts, backend services |
| **`docker-expert`** | Docker / Compose | Containerization, multi-stage builds | Dockerfiles, container configs |

---

## P3: Specialized & High-Stakes (Activated Selectively)

| Skill | Purpose | Activation Condition | Warning |
| :--- | :--- | :--- | :--- |
| **`spec-kit`** | Comprehensive specification engineering | Major multi-month initiatives, complex architecture | Do NOT use for small bugs or routine edits |
| **`gravitas-highstakes`** | High-risk checkpoints (drop table, force push, auth rewrite) | Destructive or irreversible operations | Requires explicit human confirmation |
| **`database-optimizer`** | Deep query profiling and index optimization | Explicit performance bottleneck investigation | High token load ?" targeted use only |
