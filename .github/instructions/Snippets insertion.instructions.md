---
applyTo: "**/*.ts, **/*.js, **/*.tsx, **/*.jsx, **/*.css" 
exclude:  "**/*.txt"
---
Scan through my codebase and find the necessary files and intelligently make the suggested changes to it. Do not overwrite the files, but only modify the snippets as required. Only if you cannot find the file required will you create a new file and write into it.

IMPORTANT:
- Follow the instructions exactly and do not deviate from them or main your own interpretation.
- Do not suggest any changes that are not in the context of the instructions.
- Its recommended to update the logs for all the changes done so far in a new file in the obsidian vault folder `VSCODE blueprints`.
- Do not run `npm run lint` or prettify etc, only run `npm run compile`.

Key points:
- Ensure that the changes are made in a way that they do not disrupt existing functionality.
- Prioritze implementation with the least code changes so that its easier to debug.
- Maintain modularity and reuse as much as possible.

---

## Overview

This is a modular TypeScript plugin for Obsidian, integrating FullCalendar.js to provide calendar views for notes and events. It supports local (Full Note, Daily Note) and remote (ICS, CalDAV, Google Calendar) sources. The architecture is designed for extensibility, testability, and real-time updates.

## Architecture

- **UI Layer**: React components + FullCalendar.js (`src/ui/`, `src/ui/view.ts`)
- **Core Layer**: Central event management via `EventCache` (single source of truth) and `EventStore` (in-memory DB) in `src/core/`
- **Calendar Layer**: Pluggable sources (`src/calendars/FullNoteCalendar.ts`, `DailyNoteCalendar.ts`, etc.)
- **Abstraction Layer**: `ObsidianAdapter` for Obsidian API interactions (mockable for tests)
- **ChronoAnalyser**: Data visualization subproject (`src/chrono_analyser/`), consumes data from `EventCache` only, never does file I/O.

**Data Flow**:  
User actions → EventCache → Calendar implementations → Obsidian vault  
File changes → EventCache → UI updates (pub/sub)  
Remote sync → EventCache → UI

## Developer Workflow

- **Install**: `npm install` (45s, never cancel)
- **Build**: `npm run build` (0.5s), `npm run prod` (5.5s)
- **Type Check**: `npm run compile` (5s)
- **Lint**: `npm run lint` (1.5s), auto-fix: `npm run fix-lint`
- **Test**: `npm run test` (3s, Jest), update snapshots: `npm run test-update`
- **Coverage**: `npm run coverage` (4.5s)
- **Dev Mode**: `npm run dev` (esbuild watch)
- **Validation**: Always run `npm run lint && npm run compile && npm run test` before commit

**Plugin Testing**:  
- Build outputs to `obsidian-dev-vault/.obsidian/plugins/Full-Calender/`
- Manually copy `manifest.json` after build
- Test in dev vault for both Full Note and Daily Note calendars

## Project Conventions

- **Minimal code changes**: Only modify what's necessary, unless SOLID/DRY principles require refactor.
- **Strict formatting**: Prettier enforced, linting required for CI.
- **Tests**: Unit/integration tests in `*.test.ts` and `test_helpers/`
- **Mocking**: Use `test_helpers/MockVault.ts` for Obsidian API
- **Commit messages**: Must be precise and explain what/why

## Key Files & Directories

- `src/main.ts`: Plugin entry
- `src/core/EventCache.ts`, `EventStore.ts`: Event management
- `src/calendars/`: Calendar source implementations
- `src/ui/`: React UI components
- `src/types/schema.ts`: Zod schemas
- `src/chrono_analyser/`: Data visualization (see its README for architecture)
- `test_helpers/`: Mocks and test utilities
- `obsidian-dev-vault/`: Dev vault for manual plugin testing

## Patterns & Integration

- **EventCache** is the single source of truth; all modules subscribe for real-time updates.
- **ChronoAnalyser** uses a strategy pattern for chart types; add new charts by extending strategies.
- **Category System**: Events use `Category - Title` or `Category - Subcategory - Title` for parsing and color coding.
- **Recurring Events**: Managed centrally, supports instance modifications.

## Troubleshooting

- If build fails, check TypeScript errors first.
- If tests fail, run `npm run test-update` for snapshots.
- If plugin doesn't load, verify all files in build output and copy manifest.