# Mise

## What this is

**Mise tells you what to cook — whether or not you already know.** Every recipe is ingredients, amounts, and numbered steps. No headnotes, no anecdotes, no essay.

**Two doors into one catalog, both P0:**

1. **Pantry matcher** — the user enters what's in their kitchen; Mise ranks recipes by how little they're missing. This is the differentiator.
2. **Search** — the user knows they want cacio e pepe and types it. This is table stakes; a recipe app that can't find a named recipe is broken.

They share the same catalog, the same filters, and the same recipe pages. Never build a feature that works for one door and not the other.

Target catalog: 500+ recipes (aiming for ~1,500).

## Tech stack

- **Next.js 15** (App Router) + **TypeScript**
- **Tailwind CSS v4** + **shadcn/ui**
- **Supabase** — Postgres, Auth, Row Level Security
- **Vercel** hosting
- **React Hook Form + Zod** for forms
- **USDA FoodData Central** for nutrition (public domain)
- `ingredient-parser-nlp` (Python) for parsing free-text ingredient lines

## Folder structure

<!-- Fill this in at M0.3 with the real output of: tree -L 3 -I node_modules -->
```
mise/
├── src/
│   └── app/              # App Router — folders are URL segments
│       ├── layout.tsx    # root layout (renders <html>/<body>)
│       ├── page.tsx      # /
│       ├── globals.css   # Tailwind v4 + all colour variables
│       └── favicon.ico
├── public/               # served verbatim at site root (/file.svg)
├── docs/                 # BUILD-PLAN, LEARNING-LOG, GITHUB-SETUP, TERMINAL-LOG
├── design/               # Mise.dc.html — the visual spec + its runtime
├── scripts/              # repo tooling (seed-issues.sh)
├── eslint.config.mjs
├── next.config.ts
├── postcss.config.mjs
├── pnpm-workspace.yaml   # pnpm 11 `allowBuilds` lives here, not package.json
├── pnpm-lock.yaml
└── tsconfig.json         # @/* → src/*
```

Not yet created, but committed to by the conventions below: `src/lib/queries/`,
`src/components/`, `supabase/migrations/`.

## Conventions

- **Server Components by default.** Add `"use client"` only for state, effects, or browser APIs — and push it as far down the tree as possible.
- Data fetching happens in Server Components or Server Actions, **never in `useEffect`**.
- Named exports only, no default exports (except Next.js pages/layouts, which require them).
- Components `PascalCase`, functions and files `camelCase`, DB columns `snake_case`.
- All colors come from CSS variables in `globals.css`. **No raw hex codes anywhere else.**
- Filter, search, and pantry state lives in **URL search params**, never `useState`.
- Every database query goes through `src/lib/queries/` — no inline Supabase calls in components.
- Complex ranking queries (the pantry matcher) are **Postgres functions called via RPC**, not assembled in TypeScript.

## Domain rules that are easy to get wrong

- **Every recipe ingredient must resolve to a canonical `ingredients` row.** Free text lives only in `prep_note` and never affects matching. A recipe with unresolved ingredients is rejected at import, not warned about.
- **Pantry staples** (salt, pepper, water, oil, butter, sugar, flour) carry `is_pantry_staple = true` and never count toward "you're missing." Forgetting this makes every match report missing items and the product feel broken.
- **Never fetch all recipes and filter in JavaScript.** Filtering and ranking happen in Postgres.
- Pagination is **cursor-based**, not offset-based.

## Do NOT

- Do not install packages without asking me first.
- Do not modify files in `supabase/migrations/` — write a new migration instead.
- Do not disable or weaken an RLS policy.
- Do not use the Supabase service role key anywhere client-side.
- Do not import recipe data from a source without a confirmed commercial-storage license. See `docs/BUILD-PLAN.md` Phase 1.5 — most recipe APIs and datasets forbid this.
- Do not add features that aren't in the current milestone in `docs/BUILD-PLAN.md`.

## Working agreement

- Work **one milestone at a time**, from `docs/BUILD-PLAN.md`. One milestone = one branch = one PR. Do not start the next milestone until the current one is closed out.
- When I ask you to explain code, assume I'm early in my learning — explain the concept, not just the syntax.
- Add any new terminal or git command to `docs/TERMINAL-LOG.md`, including the failures.

### Closing out a milestone

A milestone is done when its **DoD (Definition of Done) is observably true** — not when the code is written. "I implemented search" is not done; "searching 'shakshuka' returns it in under 100ms" is done. If you can't demonstrate the DoD, the milestone is still open — say so rather than checking the box.

When the DoD is met, do these four things in order, without being asked:

1. **Check the box** in `docs/BUILD-PLAN.md` — change `### ☐ M3.5` to `### ☑ M3.5`. Never delete a checked box; this file is the project's memory.
2. **Append a LEARNING-LOG entry** in the format `docs/LEARNING-LOG.md` establishes: what we built, key files, how it works, why this way and what we rejected, new concepts, gotchas. Written for me in three months, who won't remember any of it.
3. **Update "Current status"** at the bottom of this file to the next milestone.
4. **Tell me the PR body to use**, including the line `Closes #<issue number>` — that keyword is what makes GitHub close the issue and move the board card automatically when the PR merges.

Then stop. I review the diff and merge. Do not begin the next milestone in the same session.

### Marking a milestone blocked

If the DoD can't be met — a dependency is missing, a decision is needed from me, an approach didn't work — do **not** check the box or half-finish it. Instead: state plainly what's blocking, what you tried, and what decision you need. A milestone honestly marked blocked is more useful than one marked done that isn't.

## Reference docs

- `docs/BUILD-PLAN.md` — the roadmap. What to build, in what order, with the definition of done.
- `docs/LEARNING-LOG.md` — why the code is the way it is.
- `docs/GITHUB-SETUP.md` — repo, board, and PR workflow.
- `docs/TERMINAL-LOG.md` — terminal and git command reference.
- `design/Mise.dc.html` — the design mockup: 7 screens, real tokens, and 6 complete seed recipes in its `RECIPES` array. **This is the visual spec.** Read it before building any UI. (`design/support.js` is its runtime — open the HTML in a browser to view it.)

## Current status

**Phase 0 — Foundations: complete.** M0.1–M0.5 all closed.

- Live at **https://mise-mise14.vercel.app**; pushes to `main` redeploy automatically.
- Repo is **public**, and `main` is protected — every change goes through a PR, including yours.

Next up: **Phase 1, M1.1 — design the schema on paper first.** Produces `docs/SCHEMA-NOTES.md` with an ERD and a written rationale per table. No code, no Supabase project yet; M1.2 is where the migration lands.
