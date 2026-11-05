Feature: New unauthenticated, unauthorized or CSRF-exempt endpoints cannot appear unreviewed
  WHY THIS FEATURE EXISTS
  Every finding of the October 2026 security review has its own scenario, but those scenarios only
  prove that the places already fixed stay fixed. The review's "Recurring root causes" section
  (docs/security/security_review_2026_10.md) shows the same few mistakes producing most findings:

    * actions excluded from verify_authorized  — H1, H6, H7, H8, M12, M15, L10
    * policy predicates that are just `true`   — C3, H14, H15, H16, M18, M19, M20, M21, M25
    * endpoints that skip sign-in or CSRF      — H2, M1, L10
    * user text printed with `.html_safe`       — the XSS fixed on 2026-11-05 (SG-7)

  Nothing stopped the next new action or predicate from repeating them. These guards read the real
  security surface from the running code (features/security/support/security_surface.rb evaluates
  each controller's callback chain per routed action, and parses every policy with Prism). They
  compare it with a reviewed allowlist under features/security/allowlists/. They fail when:
    * something NEW appears that is not on the list: review it, then add it with a reason; or
    * a listed entry no longer exists: delete it, so the list only ever describes real exceptions.

  Like features/ai/mcp_server/mcp_ontology.feature, this is a drift guard: it should stay green, and
  turning red means "a human needs to look at this change", not "the app is broken".

  # SG-1 — Error case: a routed action that skips Pundit's verify_authorized / verify_policy_scoped.
  #   Why: an exempt action that forgets `authorize` runs for any signed-in user of any firm. That was
  #   H1 (documents#approve), H6 (bulk_actions), H7 (delete_all) and H8 (simple_scenario).
  @security
  Scenario: SG-1 Every action that skips Pundit's verification check is on the reviewed list
    Then the actions without the "authorize" check match the allowlist "verify_authorized_exempt_actions"

  # SG-2 — Error case: a routed action that runs without a signed-in user.
  #   Why: these are the internet-facing endpoints. H2 (SendGrid) and M1 (WhatsApp / DocuSign / Digio)
  #   were unauthenticated webhooks that wrote into any tenant. The H31 note in InvestorKycsController
  #   shows how a `skip_before_action … only:` can quietly widen what is skipped.
  @security
  Scenario: SG-2 Every action reachable without signing in is on the reviewed list
    Then the actions without the "authenticate" check match the allowlist "unauthenticated_actions"

  # SG-3 — Error case: a routed action that skips the CSRF token check.
  #   Why: a cookie-session action without the token can be triggered from another site (L10). New
  #   JSON endpoints tend to add `skip_before_action :verify_authenticity_token` to get a fetch working.
  @security
  Scenario: SG-3 Every action that skips the CSRF check is on the reviewed list
    Then the actions without the "csrf" check match the allowlist "csrf_exempt_actions"

  # SG-4 — Error case: a policy predicate whose whole body is `true`.
  #   Why: C3 (AI portfolio reports: every predicate true), H16 (EntityPolicy#report?), M21
  #   (ExchangeRatePolicy#destroy?), M18, M20 and M25 were all this one line.
  @security
  Scenario: SG-4 Every policy predicate that always allows is on the reviewed list
    Then the policy predicates that are always true match the allowlist "always_true_policy_predicates"

  # SG-7 — Error case: a view prints a non-literal value raw (`x.html_safe`, `raw(x)`, `<%== x %>`).
  #   Why: that is how user-typed text ran as script (stored_and_reflected_xss.feature): notes, fund
  #   details, help text and notification bodies were printed with `.html_safe` so users could format
  #   them. They now go through `safe_rich_text`, which keeps the formatting and drops scripts.
  #   RuboCop cannot read .erb views and the app has no ERB linter, so without this guard the next
  #   `@record.notes.html_safe` would ship unnoticed. Overriding html_safe itself is not an option:
  #   Rails' own helpers, Stimulus data attributes and our scripts all depend on it.
  #   Developer literals like `'<i class="ti ti-plus"></i>'.html_safe` pass automatically.
  @security
  Scenario: SG-7 Every view that prints a non-literal value raw is on the reviewed list
    Then the views' raw output of non-literal values matches the allowlist "raw_output_of_dynamic_values"

  # SG-5 — Edge case: the CSRF-exempt signed-in endpoints in SG-3 (kanban moves, kanban column delete,
  #   grid column order, deal activity actions) are only safe because the session cookie is
  #   SameSite=Lax: the browser does not send it on a cross-site POST.
  #   Why: Lax comes from `load_defaults` (cookies_same_site_protection), not from session_store.rb. A
  #   framework-defaults change or a `same_site: :none` added for an embed would silently make every
  #   one of those endpoints CSRF-able.
  @security
  Scenario: SG-5 The session cookie stays SameSite=Lax or Strict
    Then the session cookie's SameSite protection is "lax" or "strict"

  # SG-6 — Error case: a redirect to another host taken from a request parameter is refused.
  #   Why: documents#download redirects to params[:back_to] and documents#save_and_upload to
  #   params[:redirect_to]. Both are safe only because Rails 8.1's `action_on_open_redirect` is :raise.
  #   Under :log or :notify they become open redirects: a CapHive link that bounces a signed-in user
  #   to a phishing page. That setting comes from framework defaults, so pin it here.
  @security @rack_test
  Scenario: SG-6 A back_to pointing at another host is refused, not followed
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I request a documents download with back_to "https://evil.example/phish"
    Then the redirect to another host is refused

  # SG-6H — Happy path: a same-site back_to still returns the user to where they started.
  @security @rack_test
  Scenario: SG-6H A same-site back_to is still followed
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    When I request a documents download with back_to "/documents"
    Then I am back on "/documents"
