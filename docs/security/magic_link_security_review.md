# Security Review: `magic_link` / `no_password_login` Flow

**Date:** 2026-04-25  
**Files reviewed:**
- `app/packs/core/users/controllers/users_controller.rb` — `magic_link`, `no_password_login` actions
- `app/packs/core/users/models/user.rb` — `send_magic_link`
- `app/packs/core/users/mailers/user_mailer.rb` — `magic_link` mailer
- `app/packs/core/users/views/user_mailer/magic_link.html.erb` — email template
- `config/initializers/rack_attack.rb` — rate limiting configuration
- `app/packs/core/users/views/devise/sessions/new.html.erb` — login form

**Implementation status:**

| Finding | Status | Implemented in |
|---------|--------|---------------|
| F1 — Throttle parameter mismatch | Open | `rack_attack.rb` — requires ops change |
| F2 — Session-cookie safelist bypass | Open | `rack_attack.rb` — requires ops change |
| F3 — Email enumeration | **Fixed** | `users_controller.rb`, `user_mailer.rb`, `no_account_found.html.erb` |
| F4 — Unvalidated `current_entity_id` | Open | Planned (requires mailer + user.rb refactor) |
| F5 — Debug `puts` crashes background job | **Fixed** | `magic_link.html.erb` |
| F6 — Expiry mismatch | **Fixed** | `user_mailer.rb` (`MAGIC_LINK_TTL`), `magic_link.html.erb` |
| F7 — `redirect_to` phishing | **Fixed** | `users_controller.rb`, `user.rb`, `user_mailer.rb`, `magic_link.html.erb` |

---

## Feature Overview

The passwordless login flow works in two steps:

**Step 1 — `POST /users/magic_link`** (unauthenticated)

```ruby
def magic_link
  @user = User.find_by(email: params[:user][:email]) if params[:user].present?
  @user ||= nil
  if @user.present?
    @user.send_magic_link(params[:current_entity_id], params[:redirect_to])
    redirect_to new_session_path(User, display_status: true),
                notice: "Login link sent, please check your mailbox."
  else
    redirect_to new_session_path(User), notice: "User not found. Please signup."
  end
end
```

The controller looks up the user by email, then calls `send_magic_link`, which passes `current_entity_id` and `redirect_to` to the mailer. The mailer generates a signed, time-limited token and embeds it in a URL sent to the user's email. The token expires in 15 minutes.

**Step 2 — `GET /users/no_password_login`** (unauthenticated)

When the victim clicks the link, `no_password_login` verifies the signed token, signs the user in, and redirects using the embedded `redirect_to`:

```ruby
redirect_to(params[:redirect_to].presence || session[:user_return_to].presence || root_path,
            notice: "Signed in successfully")
```

---

## Findings Summary

| # | Severity | Title |
|---|----------|-------|
| 1 | **High** | Rack::Attack per-email throttle never fires for `/users/magic_link` — wrong parameter key |
| 2 | **High** | Rack::Attack session-cookie safelist exempts all throttles for any authenticated user |
| 3 | **Medium** | User email enumeration via divergent flash messages |
| 4 | **Medium** | Unvalidated `current_entity_id` lets attacker control the subdomain in the victim's magic link |
| 5 | **Medium** | Debug `puts` in email template crashes job when `current_entity_id` is absent — silent email failure |
| 6 | **Medium** | Signed ID expiry mismatch: email claims 5 minutes, token is valid for 15 |
| 7 | **Low** | `redirect_to` parameter embedded in legitimate email enables internal-path phishing |

---

## Finding 1 — High: Per-Email Throttle Never Fires for `/users/magic_link`

### Location
- `config/initializers/rack_attack.rb:76–82`
- `app/packs/core/users/controllers/users_controller.rb:48–58`

### Description

Rack::Attack defines a per-email throttle intended to limit how many magic links a single email address can receive:

```ruby
# rack_attack.rb
throttle('block_bad_sign_ins', limit: 10, period: 30.seconds) do |req|
  if ['/users/magic_link', ...].include?(req.path) && req.post?
    req.params['email'].to_s.downcase.gsub(/\s+/, "").presence
    #          ^^^^^^^^ reads params['email']
  end
end
```

The throttle reads `req.params['email']`. However, the login form sends the email nested under `user[email]`:

```html
<!-- sessions/new.html.erb -->
<input type="hidden" name="current_entity_id" .../>
<input type="email" name="user[email]" .../>   <!-- nested under 'user' -->
```

At the Rack level, `req.params['email']` is `nil` — the email is at `req.params['user']['email']`. Because the key is nil, `.to_s.downcase.presence` returns `nil`, and the throttle block returns `nil`, meaning **no throttle is ever applied per email address for this endpoint**.

The only remaining protection is the IP-based throttle (`logins/ip`: 10 requests per 30 seconds), which is insufficient to prevent distributed enumeration.

### Exploit Scenario

1. Attacker knows the app's login form sends `user[email]`, not `email`.
2. Attacker loops over a list of candidate email addresses and posts each to `POST /users/magic_link`.
3. The `block_bad_sign_ins` throttle returns nil for every request — effectively disabled.
4. The IP throttle allows 10 requests per 30 seconds per IP. With 100 IPs (cheap residential proxy), attacker sends 1,200,000 probes per hour.
5. Responses reveal which emails are registered (Finding 3).

### Fix

Change the throttle key to read from the nested parameter:

```ruby
throttle('block_bad_sign_ins', limit: 10, period: 30.seconds) do |req|
  if ['/users/magic_link', '/users/sign_in', ...].include?(req.path) && req.post?
    # magic_link sends user[email]; sign_in may send email directly.
    # Read both and take whichever is present.
    email = req.params.dig('user', 'email') || req.params['email']
    email.to_s.downcase.gsub(/\s+/, "").presence
  end
end
```

---

## Finding 2 — High: Session-Cookie Safelist Bypasses All Throttles

### Location
- `config/initializers/rack_attack.rb:21–24`

### Description

The Rack::Attack configuration includes a blanket safelist that exempts any request carrying a session cookie from **all** throttles:

```ruby
safelist('logged_in_users') do |req|
  req.cookies[Rails.application.config.session_options[:key]].present?
end
```

The intent is to avoid throttling legitimate logged-in users. However, the session cookie key is just a client-side cookie name — it is present whenever a browser has ever visited the app, regardless of the session's validity, expiry, or the user's privilege level. An attacker who holds any valid (or even stale) session cookie bypasses:

- `logins/ip` (10/30s)
- `block_bad_sign_ins` (10/30s per email)
- `req/ip` (300/5min)

The `magic_link` endpoint is excluded from `authenticate_user!`, so it is accessible to unauthenticated requests. But an attacker with a low-privilege account (or simply a browser that once visited the app) holds a session cookie and can call this endpoint with zero rate limiting.

### Exploit Scenario

1. Attacker has any legitimate account on the platform (even a deactivated one whose cookie persists).
2. Attacker sends requests to `POST /users/magic_link` with arbitrary email addresses from a single IP.
3. The `safelist('logged_in_users')` matches because the session cookie is present.
4. All throttles are bypassed — attacker can make unlimited requests per second.
5. Combining with Finding 3 (divergent messages), the attacker enumerates every registered email with no friction.

### Fix

Remove the blanket safelist or restrict it to not apply on sensitive unauthenticated endpoints:

```ruby
# Option A: Remove the safelist entirely.
# Logged-in users browsing normally will never hit the login throttle
# because they don't POST to /users/sign_in or /users/magic_link.

# Option B: Scope the safelist to exclude sensitive pre-auth paths.
safelist('logged_in_users') do |req|
  sensitive_paths = ['/users/sign_in', '/users/magic_link', '/users/password',
                     '/users/confirmation', '/users/reset_password']
  unless sensitive_paths.include?(req.path)
    req.cookies[Rails.application.config.session_options[:key]].present?
  end
end
```

---

## Finding 3 — Medium: User Email Enumeration via Divergent Flash Messages

### Location
- `app/packs/core/users/controllers/users_controller.rb:54–57`

### Description

The `magic_link` action returns distinguishably different responses depending on whether the submitted email matches a registered account:

```ruby
if @user.present?
  @user.send_magic_link(...)
  redirect_to ..., notice: "Login link sent, please check your mailbox."
else
  redirect_to ..., notice: "User not found. Please signup."
  #                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  #                         This reveals the email does not exist.
end
```

An attacker can trivially distinguish registered from unregistered addresses by comparing the flash notice. This is independent of the rate limiting failures in Findings 1 and 2, but those make bulk enumeration practical.

Additionally, the boolean `@user.present?` guard is evaluated before checking whether the user is active or confirmed. A deactivated user account (`active: false`) would still return "Login link sent" (and actually attempt to deliver an email), leaking that the deactivated account exists.

### Exploit Scenario

1. Attacker submits `user[email]=alice@targetcorp.com` to `POST /users/magic_link`.
2. Response flash says "Login link sent" → alice@targetcorp.com is registered.
3. Attacker submits `user[email]=nobody@targetcorp.com`.
4. Response flash says "User not found" → this email is not in the system.
5. At scale (enabled by Findings 1 & 2), attacker builds a complete list of registered employee emails for phishing or credential-stuffing campaigns.

### Fix

Return the same notice regardless of whether the user was found. To preserve UX, show a generic message:

```ruby
def magic_link
  @user = User.find_by(email: params[:user][:email]) if params[:user].present?
  # Send the link only if the user exists, but always show the same message.
  # This prevents email enumeration by ensuring both branches are indistinguishable.
  @user&.send_magic_link(params[:current_entity_id], params[:redirect_to])
  redirect_to new_session_path(User, display_status: true),
              notice: "If that email is registered, a login link has been sent."
end
```

---

## Finding 4 — Medium: Unvalidated `current_entity_id` Allows Subdomain Manipulation in Magic Link

### Location
- `app/packs/core/users/controllers/users_controller.rb:53`
- `app/packs/core/users/mailers/user_mailer.rb:4`
- `app/packs/core/users/views/user_mailer/magic_link.html.erb:9,17`

### Description

The `magic_link` action forwards `params[:current_entity_id]` directly to the mailer without any validation:

```ruby
# users_controller.rb
@user.send_magic_link(params[:current_entity_id], params[:redirect_to])

# user_mailer.rb
@current_entity = Entity.where(id: params[:current_entity_id]).first if params[:current_entity_id].present?

# magic_link.html.erb
subdomain = @current_entity && !Rails.env.test? ? @current_entity.sub_domain : nil
link_to 'Click To Login', no_password_login_users_url(signed_id:, subdomain:, ...)
```

An unauthenticated attacker can pass any entity's ID. The mailer will look up that entity, take its subdomain, and construct the magic link URL using that subdomain. This means the victim receives a legitimate system email where the "Click To Login" link points to `attacker-chosen-entity.app.domain.com` rather than the victim's own entity's subdomain.

This allows:
- **Misleading email links**: The victim's login link silently redirects to an unexpected entity's domain.
- **Cross-entity landing**: If the victim logs in via the manipulated link on a different subdomain, their session context may land in the wrong entity.
- **Phishing amplification**: A link pointing to a spoofed subdomain (if DNS is misconfigured) could look legitimate.

### Fix

Only accept `current_entity_id` values that the target user is actually a member of. The simplest fix is to derive the entity from the user, not from the request:

```ruby
# users_controller.rb — do not forward current_entity_id from params
def magic_link
  @user = User.find_by(email: params[:user][:email]) if params[:user].present?
  @user&.send_magic_link(params[:redirect_to])  # entity resolved from user record
  redirect_to new_session_path(User, display_status: true),
              notice: "If that email is registered, a login link has been sent."
end

# user.rb
def send_magic_link(redirect_to)
  # Use the user's own entity — never trust caller-supplied entity_id.
  UserMailer.with(id:, entity_id: entity_id, redirect_to:).magic_link.deliver_later
end

# user_mailer.rb
def magic_link
  @user = User.find(params[:id])
  @current_entity = @user.entity  # authoritative, not from params
  # ...
end
```

---

## Finding 5 — Medium: Debug `puts` in Email Template Crashes When `current_entity_id` is Absent

### Location
- `app/packs/core/users/views/user_mailer/magic_link.html.erb:10`

### Description

The email template contains a debug `puts` statement that calls `.id` on `@current_entity` without a nil guard:

```erb
<%
    @current_entity ||= nil
    subdomain = @current_entity && !Rails.env.test? ? @current_entity.sub_domain : nil
    puts "subdomain: #{subdomain}, current_entity: #{@current_entity.id}"
    #                                                ^^^^^^^^^^^^^^^^^^^ NoMethodError if nil
%>
```

When `current_entity_id` is not sent (or is empty), `@current_entity` remains `nil`. The `puts` line then calls `.id` on `nil`, raising `NoMethodError` in Ruby 3.x (Rails 8 requires Ruby 3.2+). Because the email is sent via `deliver_later`, the background job fails silently. The controller has already redirected with "Login link sent, please check your mailbox." but the user receives nothing.

**Security impact beyond the functional breakage:**

1. **Silent authentication denial**: Users on the main domain (no subdomain, so `current_entity_id` defaults to empty) can never receive a magic link, even though they are told it was sent. This is a persistent denial of magic-link authentication for an entire class of users.

2. **Information leakage via logs**: `puts` in production code writes to stdout/application logs in plaintext. Any log aggregation or observability system would record entity IDs, subdomains, and the timing of every magic link request.

### Exploit Scenario

1. A user accesses the login page from the main domain (no subdomain). The hidden `current_entity_id` field renders as empty: `<input type="hidden" name="current_entity_id" value="" />`.
2. User submits the magic link form.
3. Controller calls `@user.send_magic_link("", params[:redirect_to])`.
4. Mailer runs, `@current_entity` stays `nil`, `puts "...: #{@current_entity.id}"` raises `NoMethodError`.
5. Job fails. User sees "Login link sent" but receives no email. They are locked out of magic-link login.
6. Attacker who knows this behavior can target main-domain users to force them into password-based auth, which may be more susceptible to brute force.

### Fix

Remove the `puts` entirely and add a nil guard:

```erb
<%
  subdomain = @current_entity.present? && !Rails.env.test? ? @current_entity.sub_domain : nil
  # Removed debug puts — it logged entity metadata to stdout and crashed when @current_entity was nil.
%>
```

---

## Finding 6 — Medium: Signed ID Expiry Mismatch — Email Claims 5 Minutes, Token Valid for 15

### Location
- `app/packs/core/users/mailers/user_mailer.rb` (subject line)
- `app/packs/core/users/views/user_mailer/magic_link.html.erb:12`

### Description

Two different expiry values are stated for the same token:

```ruby
# user_mailer.rb
mail(subject: "Login Link: Expires in 5 minutes")
```

```erb
<%# magic_link.html.erb %>
signed_id = @user.signed_id(expires_in: 15.minutes)
```

The email tells users the link expires in 5 minutes, but the cryptographic token is actually valid for 15 minutes. This tripling of the stated validity window means:

1. **Intercepted links remain valid longer than users expect.** If a victim forwards the email, screenshots it, or has their inbox compromised, the link is still clickable for up to 10 minutes after the user believes it has expired.
2. **Users who dismiss the email may attempt to re-request** (thinking 5 minutes have passed), generating a second active token for the same account. Both remain valid.
3. **Security policies built around the 5-minute claim** (e.g., incident response runbooks) would underestimate the actual exposure window.

### Fix

Make the stated and actual expiry consistent. For a one-time magic link, 10 minutes is a typical industry standard:

```ruby
# user_mailer.rb
MAGIC_LINK_TTL = 10.minutes

mail(subject: "Login Link: Expires in #{MAGIC_LINK_TTL.in_minutes.to_i} minutes")
```

```erb
<%# magic_link.html.erb %>
signed_id = @user.signed_id(expires_in: UserMailer::MAGIC_LINK_TTL)
```

---

## Finding 7 — Low: `redirect_to` Parameter Propagated Into Legitimate Email — Internal Path Phishing

### Location
- `app/packs/core/users/controllers/users_controller.rb:53`
- `app/packs/core/users/views/user_mailer/magic_link.html.erb:17`
- `app/packs/core/users/controllers/users_controller.rb:142`

### Description

The `magic_link` action accepts `params[:redirect_to]` from the unauthenticated request and propagates it into the email:

```ruby
# controller
@user.send_magic_link(params[:current_entity_id], params[:redirect_to])

# email template
link_to 'Click To Login', no_password_login_users_url(signed_id:, redirect_to: params[:redirect_to])

# no_password_login
redirect_to(params[:redirect_to].presence || session[:user_return_to].presence || root_path, ...)
```

In **Rails 8**, `redirect_to "https://evil.com"` raises `ActionController::Redirecting::UnsafeRedirectError` for external hosts (mitigating a full open redirect). However:

1. Any valid **internal path** is still accepted by `redirect_to`. An attacker can embed `/admin/dangerous-action`, `/users/reset_password`, or any other internal URL into a legitimate system email.
2. The victim receives an email that originated from the legitimate mail server. The "Click To Login" link and the subsequent redirect are both handled by the legitimate domain. The victim has no way to distinguish this from a normal magic link.
3. If `redirect_to` points to a confusing or deceptive internal page (e.g., a page the attacker knows shows misleading content), the victim is landed there immediately after authenticating.

This is lower severity on Rails 8 because cross-origin redirects are blocked, but it is still an abusable primitive, especially in combination with Finding 4.

### Fix

Validate `redirect_to` against an allowlist of safe paths before embedding it:

```ruby
# users_controller.rb
ALLOWED_REDIRECT_PREFIXES = ['/', ''].freeze  # only same-origin paths

def safe_redirect_path(path)
  return nil unless path.present?
  uri = URI.parse(path)
  # Reject anything with a scheme or host (external URLs)
  return nil if uri.scheme.present? || uri.host.present?
  path
rescue URI::InvalidURIError
  nil
end

def magic_link
  @user = User.find_by(email: params[:user][:email]) if params[:user].present?
  redirect_path = safe_redirect_path(params[:redirect_to])
  @user&.send_magic_link(params[:current_entity_id], redirect_path)
  redirect_to new_session_path(User, display_status: true),
              notice: "If that email is registered, a login link has been sent."
end
```

---

## Attack Chain: Email Enumeration at Scale

The findings combine into a concrete, high-impact attack chain:

```
1. Attacker holds any session cookie (existing account or stale cookie).
   → Safelist (Finding 2) bypasses ALL Rack::Attack throttles.

2. Attacker sends POST /users/magic_link with user[email]=<target>.
   → Per-email throttle never fires (Finding 1) — wrong param key.
   → Only IP throttle applies, bypassed by the session cookie safelist.

3. Flash message "User not found" vs "Login link sent" reveals registration status.
   → Finding 3.

4. At scale: attacker enumerates entire corporate email directory with no friction.
   Result: complete list of platform users for phishing, credential stuffing, or
   targeted social engineering attacks.
```

---

## Fix Priority

| Priority | Finding | Change |
|----------|---------|--------|
| 1 (immediate) | F5 — crashes job | Remove `puts`, add nil guard in email template |
| 2 | F1 — throttle key mismatch | Fix `req.params['email']` → `req.params.dig('user','email') \|\| req.params['email']` |
| 3 | F2 — safelist bypass | Exclude pre-auth endpoints from `logged_in_users` safelist |
| 4 | F3 — enumeration | Return identical flash for found/not-found |
| 5 | F4 — entity_id manipulation | Derive entity from `@user.entity`, not from params |
| 6 | F6 — expiry mismatch | Align subject and token TTL to a single constant |
| 7 | F7 — redirect_to | Validate `redirect_to` with `safe_redirect_path` before forwarding |
