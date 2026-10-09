# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

> **Both regions must ship together.** Phases 1–6 are ordinary code work on one branch. Phase 7 is
> the two-region rollout and is the only phase that touches a deployed environment.

> **Retrofitted.** This change was planned and implemented under the heavier `spec-driven`
> schema and migrated to `bugfix` afterwards, so there is no phase 1 "Reproduce" the way a new
> bug fix would have. The reproduction is recorded instead in the report's
> [Fails against current code](report.md#verification) line: X1–X7, X14, X15, E2, E4 and X10–X13
> all failed, or had no implementation at all, before this work.

---

## 1. Region registry and configuration

Implements the report's **Fix** rows 3 (`SiteRegistry`, JSON `SITES`, https, boot check) and 4 (region-code normalisation).

- [x] 1.1 Add `app/packs/core/users/services/site_registry.rb` with `.codes`, `.current_code`,
      `.peers`, `.url_for`, `.known?`, `.normalize`, `.validate!` and a non-production-only
      `.reset!`, memoising the parsed `SITES` per process. Verify with
      `bin/rails runner 'p SiteRegistry.codes, SiteRegistry.current_code, SiteRegistry.url_for("us")'`
      printing the deployed codes, the active code and the US base URL with no trailing slash.
- [x] 1.2 Give `SiteRegistry.validate!` the five assertions named in the report's Fix row 3 (`SITES`
      present → parses as a JSON object → every value is an absolute `https` URL → `CURRENT_SITE`
      present → `CURRENT_SITE` is one of the keys), each raising
      `SiteRegistry::ConfigurationError` naming the setting and the offending value. Verify by
      calling it in `bin/rails runner` with each of the five bad values stubbed in `ENV` and
      confirming five distinct messages.
- [x] 1.3 Add `config/initializers/site_registry.rb` calling `SiteRegistry.validate!` so a bad
      value fails the boot. Verify that `SITES='not json' bin/rails runner 'puts 1'` aborts naming
      `SITES`, and that the unmodified app still boots.
- [x] 1.4 Convert `SITES` to https JSON in all six env files (`.env.production.in`,
      `.env.production.us`, `.env.staging.in`, `.env.staging.us`, `.env.development`, `.env.test`),
      **removing the `Local` alias** from each. Verify each file's value parses with
      `ruby -rjson -e 'JSON.parse(ENV.fetch("SITES"))'` and that every URL is `https`.
- [x] 1.5 Update `features/support/env.rb` line 184 so the test-suite `ENV['SITES']` is https JSON
      too. Verify `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/login.feature` still
      passes — an unrelated feature, run to prove the boot check has not broken the suite.
- [x] 1.6 Write `features/misc/site_registry.feature` covering **X11** (malformed region list stops
      the boot check), **X12** (an `http` address stops it) and **X13** (an active region absent from
      the list stops it), using `SiteRegistry.reset!` around every `ENV` change. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/site_registry.feature` and confirm
      it passes before starting phase 2.

---

## 2. Inter-region trust and metrics

Implements the report's **Fix** row 10 (trust fingerprint + hourly check) and the observability half of **Root Cause → why it was hard to see**.

- [x] 2.1 Add `app/packs/core/users/services/cross_site_metrics.rb` registering the
      `caphive_cross_region_handoff_total` counter and `caphive_cross_region_trust` gauge against
      `PrometheusExporter::Client.default`, with every call wrapped so a failure is logged at `warn`
      and swallowed. Verify by running the local exporter, calling
      `CrossSiteMetrics.trust("US", true)` in `bin/rails runner`, and seeing the gauge in
      `curl -s localhost:9394/metrics | grep caphive_cross_region` — this closes
      the report\'s open question 2.
- [x] 2.2 Add `app/packs/core/users/services/cross_site_trust.rb` with `.configured?`,
      `.fingerprint` (HMAC-SHA256 of the fixed `PROBE` string, `nil` when unconfigured),
      `.peer_mismatch?` and `.record(peer_code, matched)` on a 90-minute TTL. Verify in
      `bin/rails runner` that two identical secrets produce one fingerprint and two different
      secrets produce two, and that an unset secret returns `nil` rather than an HMAC of `nil`.
- [x] 2.3 Add `HealthCheckController#cross_site_trust` and its route in `config/routes/misc.rb`
      alongside `replication_check`, returning `200` with `{region:, fingerprint:, configured:}` in
      both the configured and unconfigured cases. Verify with
      `curl -s localhost:3000/health_check/cross_site_trust` that the body carries a fingerprint and
      no part of the secret.
- [x] 2.4 Add `app/packs/core/users/jobs/cross_site_trust_check_job.rb` (`queue_as :sync`, HTTParty
      `timeout: 10`) implementing the four per-peer outcomes (equal, differing, peer unconfigured, unreachable) — equal, differing,
      peer unconfigured, and unreachable (flag untouched, **no** gauge sample). Verify by running it
      in `bin/rails runner` against a WebMock-style stub for each of the four cases and checking the
      cached flag after each.
- [x] 2.5 Register the job in `config/initializers/sidekiq.rb` inside the same non-local guard as the
      existing `Sidekiq::Cron::Job.create` entries, reading `CROSS_SITE_TRUST_CRON` with a default of
      `every 1 hour`. Verify the entry appears in `Sidekiq::Cron::Job.all` under a non-local env and
      is absent in test.
- [x] 2.6 Write `features/login/cross_region_trust.feature` covering **H4** (matching secrets give
      matching fingerprints), **E9** (an unconfigured secret is reported as such, with no
      fingerprint) and **E10** (the response contains no substring of the secret). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/cross_region_trust.feature` and
      confirm it passes before starting phase 3.

---

## 3. Selector, policy and credential issuance

Implements the report's **Fix** rows 4 (normalisation), 5 (`switchable_region_codes`) and 8 (policy), i.e. **Root Cause 3**, **4** and **5**.

- [x] 3.1 Add `User#switchable_region_codes` returning the existing
      `CanonicalFingerprint#normalize_regions_array` output intersected with `SiteRegistry.codes`,
      sorted, and adding no query. Verify in `bin/rails runner` against the four seeded shapes
      (`"IN,US"`, `"IN"`, `" in ,US, us"`, `'["US","IN"]'`) that each returns the expected array.
- [x] 3.2 Rewrite `app/packs/core/base/views/layouts/_sites.html.erb` to render
      `current_user.switchable_region_codes` and to do no splitting, trimming or upcasing of its
      own, keeping the existing `persona#setRegion` wiring and `data: {turbo: false}`. Verify by
      loading a page as each of the four seeded users and reading the rendered `<option>` values.
- [x] 3.3 Tighten `UserPolicy#cross_site_link?` to take the requested region and require it to be in
      `record.switchable_region_codes`, replacing `user.regions.present?`. Verify in
      `bin/rails runner` that it is `true` for Neha + `US`, `false` for Raj + `US`, and `false` for
      anyone + `SG`.
- [x] 3.4 Add `CrossSiteLink::Result` (`.ok`, `.failure` over the closed set
      `:missing, :invalid, :expired, :wrong_region`, raising `ArgumentError` otherwise) and change
      `CrossSiteLink#generate` to take `from:`, to carry `from` in the payload, to use
      `LIFETIME = 5.minutes` and `PURPOSE = :login` constants, and to raise `ArgumentError` unless
      both `site:` and `from:` are `SiteRegistry.known?`. Verify in `bin/rails runner` that a
      generated token is 270-ish characters, contains no `+`, `/` or `=`, and round-trips through
      `Rack::Utils.parse_nested_query("token=#{tok}")` unchanged.
- [x] 3.5 Rewrite `UsersController#cross_site_link` to normalise the requested code through
      `SiteRegistry`, authorise it via the tightened policy, build the redirect from
      `SiteRegistry.url_for` (never from a param), and append both `token` and `from`. Delete the
      `eval(ENV.fetch("SITES", nil))` call and its `rubocop:disable Security/Eval` pair. Verify
      `bundle exec rubocop app/packs/core/users/controllers/users_controller.rb` is clean and that
      `grep -n "Security/Eval" app/packs/core/users/controllers/users_controller.rb` finds nothing.
- [x] 3.6 Add the region-unavailable message (`cross_region.unavailable`) to `config/locales/en.yml`,
      `en-US.yml` and `ja.yml`, and have `cross_site_link` redirect back with it when
      `SiteRegistry.known?` is false. Verify each locale file loads with
      `bin/rails runner 'I18n.available_locales.each { |l| I18n.t("cross_region.unavailable", locale: l) }'`.
- [x] 3.7 Write `features/login/cross_region_issuance.feature` covering **H1** (selector shown for a
      two-region user), **E1** (hidden for a single-region user), **E2** (messy casing normalises and
      the credential embeds `US`), **E3** (an undeployed code is not offered and the stored value is
      untouched), **E4** (a JSON-array regions value yields clean options), **X9** (an undeployed
      destination is refused with no credential and no cross-host redirect) and **X10** (a
      destination outside the user's own regions is refused). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/cross_region_issuance.feature`
      and confirm it passes before starting phase 4.

---

## 4. Verification, single-use consumption and the failure banner

Implements the report's **Fix** rows 1 (5-minute lifetime), 2 (single use), 6 (typed `Result`) and 7 (banner + logging) — **Root Cause 1** and **why it was hard to see**.

- [x] 4.1 Change `CrossSiteLink#verify` and `#peek` to return a `Result` and never raise for any
      input, mapping `MessageVerifier::InvalidSignature` to `:invalid` or `:expired` by inspecting
      whether the expiry stamp is past, and **delete** `CrossSiteLink::VerificationError`. Verify
      `grep -rn "VerificationError" app features` returns nothing, and that
      `#verify(nil)`, `#verify("")` and `#verify("x" * 100_000)` each return a `Result` in
      `bin/rails runner`.
- [x] 4.2 Add `app/packs/core/users/services/cross_site_link/nonce.rb` with `.claim(token)` using
      `Rails.cache.write(key, true, unless_exist: true, expires_in: CrossSiteLink::LIFETIME + 1.minute)`
      and the key `"cross_site_handoff:#{sha256(token)}"`. Verify in `bin/rails runner` that the
      first `claim` returns `true` and every later one `false`, and that the token itself is absent
      from `SolidCache::Entry` — `grep` the stored key for the token value.
- [x] 4.3 Add `app/packs/core/users/services/cross_site_rejection.rb` with `.for(reason:, from:,
      request:)`, `#flash_payload`, `#log_fields` and the `:invalid` → `:secret_mismatch`
      reclassification, resolving `origin_url` only through `SiteRegistry.url_for` and forcing it to
      `nil` for `:secret_mismatch`, `:missing` and `:invalid`. Verify in `bin/rails runner` that a
      `from` of `"../evil.com"` yields `origin_url: nil` and that an unknown reason raises
      `ArgumentError`.
- [x] 4.4 Add the six rejection messages plus the `return_to` label under `cross_region.rejection.*`
      in `config/locales/en.yml`, `en-US.yml` and `ja.yml`, wording them exactly as the
      [proposal's Behavior Rules](report.md) table states. Verify every key resolves
      in all three locales in `bin/rails runner`.
- [x] 4.5 Add `app/packs/core/users/views/devise/sessions/_cross_region_alert.html.erb` and render it
      from `devise/sessions/new.html.erb`, driven by a **Hash** flash entry so the screen's existing
      `flash.each` / `msg.is_a?(String)` loop skips it. Introduce no `html_safe`, `raw` or
      `sanitize`. Verify by setting the flash in `bin/rails console` (or a throwaway route) that the
      banner renders once, not twice, and that the Return-to link is a real anchor.
- [x] 4.6 Rewrite `UsersController#cross_site_login` to run the validation ladder in the
      [design's Pipeline order](report.md), call `Nonce.claim` **after** all other
      checks and **before** `sign_in`, both inside the existing
      `connected_to(role: :writing)` block, replace `find_by!` with `find_by` plus a `:no_account`
      rejection, and route every rejection through `CrossSiteRejection` to
      `new_session_path(User)`. Verify by hand-driving each of the seven reasons in
      `bin/rails console` via an integration session and confirming the redirect target and flash
      each time.
- [x] 4.7 Rewrite `UsersController#redirect_to_subdomain` to use `#peek` (never claiming), to forward
      both `token` and `from` to the next hop, and to route its own failures through
      `CrossSiteRejection`. Verify that a successful peek leaves the credential claimable — the same
      token must still sign in afterwards.
- [x] 4.8 Add one `warn` log line per rejection and one `info` on success, in a greppable key/value shape, and add `token` and `from` to `config.filter_parameters`. Verify with
      `grep -n "filter_parameters" config/initializers/filter_parameter_logging.rb` and by grepping
      `log/development.log` after a hand-driven run to confirm no token value appears.
- [x] 4.9 Update the three existing cross-site scenarios in `features/login/multi_site.feature`: the
      `SITES` stub becomes https JSON, and *"redirect_to_subdomain returns 401 for an invalid token"*
      now expects a redirect to the sign-in screen. Verify
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/multi_site.feature` passes.
- [x] 4.10 Write `features/login/cross_region_login.feature` covering **H2** (full IN→US switch over
      https onto the company site, claimed once, success logged), **H3** (the credential survives
      transport and the middle hop does not consume it), **E5** (no destination site falls back to
      the default), **E6** (clock drift inside the lifetime is tolerated), **E7** (two concurrent
      claims yield one session), **E8** (the claim is shared across the region's servers), **X1**
      (expired, with the Return-to link and the logged reason), **X2** (replay refused, with the
      Return-to link), **X3** (missing, no Return-to link), **X4** (tampered), **X5**
      (wrong region), **X6** (wrong purpose), **X7** (divergent secret, no retry offered), **X8**
      (no account in the destination region), **X14** (no technical detail on any of the six
      rejection pages) and **X15** (the credential appears in no log line). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/cross_region_login.feature` and
      confirm it passes before starting phase 5.

---

## 5. Stored region list housekeeping

Implements the report's **Fix** row 11.

- [x] 5.1 Add `lib/tasks/users_regions.rake` with `users:normalize_regions`, reporting by default and
      writing only with `EXECUTE=1`, iterating
      `User.where.not(regions: [nil, ""]).in_batches(of: 1_000)` selecting only `id` and `regions`,
      and reusing `CanonicalFingerprint#normalize_regions_array`. Verify
      `bundle exec rake users:normalize_regions` lists candidates and changes nothing, then
      `EXECUTE=1 bundle exec rake users:normalize_regions` normalises them and a second run reports
      zero changes.
- [x] 5.2 Make the task print a per-user before/after line and a final count, and never add or remove
      a region from any user — a code with no deployed region stays in the stored value. Verify
      against the seeded Sandeep (`IN,SG`) that his stored value is still `IN,SG` afterwards.
- [x] 5.3 Confirm `bundle exec rubocop lib/tasks/users_regions.rake` is clean, including
      `IRM/RelationBlankPresent` — no `blank?`/`present?` on a relation anywhere in the task.
- [x] 5.4 Write `features/login/cross_region_housekeeping.feature` covering **E11** (messy values
      normalised, reachable regions unchanged), **E12** (a JSON-array value converted), **E13** (a
      second run changes nothing) and **E14** (reporting mode writes nothing). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login/cross_region_housekeeping.feature`
      and confirm it passes before starting phase 6.

---

## 6. Clock synchronisation and alerting

Implements the report's **Fix** row 9 — **Root Cause 2**, the cause that is currently invisible.

- [x] 6.1 Add the four alert rules to `config/initializers/observability/grafana_provision.yml` —
      clock offset (`node_timex_offset_seconds > 30s` for 5 min), clock unsynchronised
      (`node_timex_sync_status == 0` for 10 min), trust divergence (`caphive_cross_region_trust == 0`
      or no sample for 3 h) and hand-off rejection rate — each scoped to both regions' app
      instances. Verify the file still parses with
      `ruby -ryaml -e 'YAML.load_file("config/initializers/observability/grafana_provision.yml")'`
      and that every threshold is below `CrossSiteLink::LIFETIME`.
- [x] 6.2 Add a clock-synchronisation assertion to `config/deploy.rb` in the app-role verification
      phase, reporting any host whose synchronisation service is not running. Verify with a dry
      `cap production_in deploy:check`-style invocation, or by running the assertion's command
      directly against a host with the service stopped.
- [x] 6.3 Write `features/misc/clock_sync_monitoring.feature` as a config guard in the style of
      `features/step_definitions/notification_attachment_size_steps.rb`, covering **X16** (the deploy
      asserts clock synchronisation) and **X17** (a clock-offset rule exists for every app instance
      with a threshold below the credential lifetime). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/clock_sync_monitoring.feature` and
      confirm it passes before starting phase 7.

---

## 7. Two-region rollout and QA

Implements the report's **Risks and Rollout**. Every step is per region: **IN and US are
independent environments** and nothing is copied between them.

- [x] 7.1 Run the whole affected suite green before anything is deployed:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/login features/misc/site_registry.feature features/misc/clock_sync_monitoring.feature`
      plus `bundle exec rubocop`.
- [ ] 7.2 Update `SITES` in both regions' env files on the target hosts (https JSON, no `Local`) and
      confirm each parses on the host before deploying. Verify with
      `ruby -rjson -e 'JSON.parse(ENV.fetch("SITES"))'` on each app host.
- [ ] 7.3 Deploy both regions back to back and confirm each app booted — a `SiteRegistry`
      misconfiguration aborts the boot by design, so a silent start is the pass condition. Verify
      each region's existing `/health_check` responds.
- [ ] 7.4 Compare the trust fingerprints across regions:
      `curl -s https://app.caphive.com/health_check/cross_site_trust` and the `.us` equivalent. They
      **must** match — this answers
      the report\'s open question 1. If they differ, stop the rollout
      and raise it as a separate live defect.
- [ ] 7.5 Provision the Grafana rules in both regions and confirm each of the four rules is present
      and evaluating, and that `caphive_cross_region_trust` and
      `caphive_cross_region_handoff_total` appear on each region's `rails_app` scrape target.
- [ ] 7.6 Run `users:normalize_regions` in reporting mode against each region's database, review the
      output with someone who knows the data, then re-run with `EXECUTE=1` — **separately per
      region**, never once for both.
- [ ] 7.7 Hand the build to QA to run [qa-checklist.md](qa-checklist.md) end to end on the two
      staging sites, including the developer-assisted rows (X11–X13, X16, X17, E9, E10, E6, X7), and
      record the sign-off table. *This task is for QA, not for the implementing agent.*
