# Maestro flows — LP mobile app

One flow per app-only worked example in `openspec/changes/lp-mobile-app/design.md#worked-examples`
(server rows are Cucumber, in `features/mobile/`). Each flow starts with `# <ID> — …`.

Run against a dev build on a simulator, with the staging region seeded by `bin/rails mobile:seed_demo`:

    maestro test mobile/e2e/

Not yet run: the build machine has no iOS/Android simulator. The same screens were checked with
Playwright against the Expo web build (see the change's tasks).
