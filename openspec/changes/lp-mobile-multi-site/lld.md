# LLD — lp-mobile-multi-site

## File map

| File | Change |
|---|---|
| `app/packs/core/mobile/controllers/api/mobile/v1/sites_controller.rb` | new — public site list, `sites_json` shared with `/me` |
| `app/packs/core/mobile/controllers/api/mobile/v1/cross_site_links_controller.rb` | new — mints `CrossSiteLink` purpose `mobile_cross_site` |
| `app/packs/core/mobile/controllers/api/mobile/v1/sessions_controller.rb` | `#cross_site`; `:handoff_invalid` → 401 `region_switch_failed` |
| `app/packs/core/mobile/controllers/api/mobile/v1/base_controller.rb` | `#fund_manager_id`; messages `region_unavailable`, `region_switch_failed` |
| `app/packs/core/mobile/services/mobile_sign_in.rb` | `.cross_site(token:, device:)` |
| `app/packs/core/mobile/services/mobile_fund_managers.rb` | new — `list`, `resolve` |
| `app/packs/core/mobile/services/mobile_home_summary.rb`, `mobile_documents.rb` | `fund_manager_id:` narrows by `entity_id` |
| `app/packs/core/mobile/services/mobile_deep_link.rb` | `sender_id` |
| `app/packs/core/notifications/delivery_methods/expo_push.rb` | push `data.region`, `data.fund_manager_id` |
| `config/routes/mobile.rb` | `sites`, `cross_site_links`, `session/cross_site` |
| `mobile/src/api/config.ts`, `client.ts`, `auth/storage.ts`, `auth/session.tsx` | environments, per-site sessions, switch |
| `mobile/src/lib/fund-manager.tsx`, `ui/fund-manager-picker.tsx` | picker |
| `mobile/src/app/(auth)/region.tsx`, `sign-in.tsx`, `(tabs)/*`, `funds/[id].tsx`, `lib/push.ts` | screens |
| `mobile/app.config.js` | one identity; `defaultEnvironment` |
| `.easignore` | patterns without trailing slashes |

## Method contracts

- `MobileFundManagers#list → [{id:, name:}]` — approved `InvestorAccess` entities, `name.downcase` order. One query (`Entity.where(id: subquery).pluck`).
- `MobileFundManagers#resolve(requested) → Integer | nil` — requested when in list, else first, else nil.
- `MobileSignIn.cross_site(token:, device:) → Result` — `:handoff_invalid` (no secret, bad signature/expiry/purpose/destination), `:invalid` (no user / inactive / locked here), `:not_investor`, `:spent` (nonce already claimed), `:session`. Runs on the writing role; nonce claimed last.

## Transactions and concurrency

Two phones redeeming one link: `CrossSiteLink::Nonce.claim` (`Rails.cache.write unless_exist`) lets
exactly one through, as on the website. Session creation reuses `MobileDevice.register!` (user row
lock, device limit).

## Security review

- Link lifetime 5 minutes, single use, signed with `CROSS_INSTANCE_SECRET`, destination-bound,
  purpose-bound (`mobile_cross_site` ≠ website `:login` ≠ `mobile_web`).
- `/sites` is public and returns only region codes, labels and base URLs — what the website's
  sign-in page and region dropdown already reveal.
- `fund_manager_id` only narrows a Pundit-scoped relation; an id without access falls back to the
  first fund manager, never widens.
- The phone stores one token pair per site in the Keychain/Keystore (`WHEN_UNLOCKED_THIS_DEVICE_ONLY`).
