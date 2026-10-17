# CapHive — LP mobile app

The investor app for CapHive (iOS, Android), built with Expo / React Native.
Spec, design and tasks: `openspec/changes/lp-mobile-app/`. User guide: `docs/user_guides/lp_mobile_app_user_guide.md`.

## Run it locally (web review build)

The app talks to a CapHive Rails server. For a review without real data, seed a throwaway test
database with the fictional demo (never production):

```bash
# from the repo root
RAILS_ENV=test TEST_ENV_NUMBER=mobiledemo bin/rails db:create db:schema:load mobile:seed_demo
MOBILE_WEB_ORIGIN=http://localhost:8081 RAILS_ENV=test TEST_ENV_NUMBER=mobiledemo bin/rails s -p 3999

# from mobile/
EXPO_PUBLIC_API_URL=http://localhost:3999 npx expo start --web --port 8081
```

Open http://localhost:8081 (phone size in DevTools), region **India**, `rahul@sharmafo.example` / `password`.
`MOBILE_WEB_ORIGIN` enables CORS for the web build only (never in production).

## Builds

Full steps for dev phones, testers and the stores: [DEPLOYMENT.md](DEPLOYMENT.md).

`APP_ENV` (set by the EAS profile in `eas.json`) picks the sites in `app.config.js`:
development → local server, staging → dev.altconnects.com/.us, production → app.caphive.com/.us.

```bash
npx eas-cli@latest build --profile development   # dev client for simulators / devices
npx eas-cli@latest build --profile production
```

## Checks

```bash
npx tsc --noEmit
npx eslint src
maestro test e2e/        # needs a simulator and the staging demo data
```

## Design rules

One fixed graphite theme with CapHive orange (`src/constants/theme.ts`), Manrope, Ionicons, and
the building blocks in `src/ui/`. Where the website already has a JSON endpoint the app uses it
with the phone token (`src/api/queries.ts`); see the change's design for the few mobile endpoints.
