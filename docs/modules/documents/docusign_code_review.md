# DocuSign Integration — Code Review & Improvements

This document covers bugs, security issues, and design improvements found in the current DocuSign integration. See `esigning.md` for the overall e-signing architecture.

---

## Table of Contents

1. [Critical Bugs](#critical-bugs)
2. [Security Issues](#security-issues)
3. [Data Quality Issues](#data-quality-issues)
4. [Design & Reliability Issues](#design--reliability-issues)
5. [Fix Checklist](#fix-checklist)
6. [File Reference](#file-reference)

---

## Critical Bugs

### 1. `get_docusign_access_token` — dead code with a runtime crash

**File:** `app/packs/core/investor_kycs/services/docusign/jwt_auth.rb:63`

```ruby
# BUG: `token` here is a JWT *string* (the output of JWT.encode),
# not a token object. `.access_token` and `.expires_in` do not exist on it.
store_access_token_in_redis(redis, 'docusign_access_token', token.access_token, token.expires_in.to_i - 60)
```

`get_docusign_access_token` is dead code — nothing calls it; the live path goes through `check_jwt_token`. However, if it is ever wired up it crashes immediately. The method should be deleted; `check_jwt_token` already covers JWT token acquisition correctly.

**Fix:** Delete `get_docusign_access_token` entirely.

---

### 2. `handle_api_error` — arity mismatch in Trailblazer operation

**File:** `app/packs/core/investor_kycs/services/docusign/docusign_esigning.rb:23,28`

```ruby
def handle_errors(ctx, **)
  handle_api_error if ctx[:error].is_a?(DocuSign_eSign::ApiError)  # called with 0 args
  ...
end

def handle_api_error(ctx, **)  # expects ctx — will raise ArgumentError
  error = JSON.parse ctx[:error].response_body
  ...
end
```

`handle_api_error` is called with zero arguments but defined with `(ctx, **)`. This raises `ArgumentError` on every DocuSign API error — precisely the path the method is meant to protect.

**Fix:**

```ruby
def handle_errors(ctx, **)
  handle_api_error(ctx) if ctx[:error].is_a?(DocuSign_eSign::ApiError)
  ctx[:errors] = [ctx[:errors].to_s, ctx[:error]&.full_message].join(', ')
  false
end

def handle_api_error(ctx, **)
  error = JSON.parse(ctx[:error].response_body)
  ctx[:error_code]    = ctx[:error].code || error['errorCode']
  ctx[:error_message] = error['error_description'] || error['message']
  Rails.logger.error "DocuSign Error: #{ctx[:error_code]} - #{ctx[:error_message]}"
end
```

Note: the original used instance variables (`@error_code`, `@error_message`) which are discarded after the method returns. They should be stored in `ctx` instead.

---

### 3. No-op debug line left in `download`

**File:** `app/packs/core/investor_kycs/models/concerns/docusign_esign_helper.rb:128`

```ruby
def download(doc)
  envelope_api = create_envelope_api(args)
  doc.id          # ← does nothing; leftover from debugging
  envelope_api.get_document(ACCOUNT_ID, doc.id, doc.provider_doc_id)
end
```

**Fix:** Delete the `doc.id` line.

---

## Security Issues

### 4. RSA private key written to disk and never deleted

**File:** `jwt_auth.rb:85-88`

```ruby
tmp_file = Tempfile.new(['docusign_rsa_key', '.pem'])
tmp_file.write(DocusignEsignHelper::DOCUSIGN_RSA_PRIVATE_KEY)
tmp_file.close
rsa_pk = tmp_file.path.to_s
# tmp_file is never unlinked — private key persists in /tmp
```

The DocuSign SDK requires a file path for the RSA key, but the tempfile is never cleaned up. The private key leaks to disk and lives until the OS cleans `/tmp`.

**Fix:** Delete the tempfile in an `ensure` block:

```ruby
tmp_file = Tempfile.new(['docusign_rsa_key', '.pem'])
begin
  tmp_file.write(DocusignEsignHelper::DOCUSIGN_RSA_PRIVATE_KEY)
  tmp_file.close
  rsa_pk = tmp_file.path.to_s
  token = api_client.request_jwt_user_token(
    DocusignEsignHelper::DOCUSIGN_INTEGRATION_KEY,
    DocusignEsignHelper::DOCUSIGN_USER_ID,
    rsa_pk,
    3600,
    @scope
  )
ensure
  tmp_file.unlink
end
```

---

### 5. `debug_output $stdout` fires in all environments

**File:** `docusign_esign_helper.rb:6`

```ruby
class DocusignEsignHelper
  include HTTParty
  debug_output $stdout   # unconditionally pipes all HTTP traffic to stdout
```

All HTTP requests — including those containing auth tokens and document data — are logged to stdout in production.

**Fix:**

```ruby
debug_output $stdout if Rails.env.development?
```

The `attr_accessor :debug` on line 7 already suggests this was intended to be conditional.

---

### 6. No webhook HMAC verification

**File:** `documents_controller.rb` (signature_progress action)

DocuSign Connect supports HMAC-SHA256 signing on each webhook delivery. The current implementation accepts any POST without verifying the signature, making the endpoint susceptible to forged events (e.g., a fake `envelope-completed` that triggers downloading a non-signed document).

**Fix:** Add HMAC verification using the Connect HMAC key from credentials:

```ruby
def valid_docusign_webhook?
  hmac_key = Rails.application.credentials[:DOCUSIGN_CONNECT_HMAC_KEY]
  return true if hmac_key.blank?  # not configured → allow (for migration period)

  payload_digest = request.headers['X-DocuSign-Signature-1']
  return false if payload_digest.blank?

  computed = Base64.strict_encode64(
    OpenSSL::HMAC.digest('sha256', hmac_key, request.raw_post)
  )
  ActiveSupport::SecurityUtils.secure_compare(computed, payload_digest)
end
```

---

## Data Quality Issues

### 7. Signer name displayed as their email address

**File:** `docusign_signing_via_email_service.rb:92`

```ruby
signer.name = esign.email   # DocuSign shows "Dear john@example.com"
```

DocuSign displays `signer.name` in the signing email and on the completed certificate. Using the email address as the name looks unprofessional.

**Fix:** Use `esign.name` if the column exists, with email as fallback:

```ruby
signer.name = esign.name.presence || esign.email
```

If `ESignature` does not have a `name` column, add one (or derive it from the linked `User` record via `esign.user&.full_name`).

---

### 8. Hardcoded sandbox OAuth host

**File:** `jwt_auth.rb:16` and `jwt_auth.rb:39`

```ruby
# In initialize:
@api_client = create_initial_api_client(host: "account-d.docusign.com", ...)

# In get_docusign_access_token JWT body:
aud: 'account-d.docusign.com',
```

`account-d.docusign.com` is DocuSign's **demo/sandbox** endpoint. Production uses `account.docusign.com`. If these are not toggled, JWT tokens issued in production will fail.

**Fix:** Read from credentials:

```ruby
DOCUSIGN_AUTH_HOST = Rails.application.credentials.fetch(:DOCUSIGN_AUTH_HOST, 'account-d.docusign.com')

@api_client = create_initial_api_client(host: DOCUSIGN_AUTH_HOST, ...)
```

---

### 9. JWT `exp` set to 6000 seconds (exceeds DocuSign's 3600 limit)

**File:** `jwt_auth.rb:43` (inside the dead `get_docusign_access_token`)

```ruby
exp: current_time + 6000,  # 100 minutes — DocuSign rejects tokens > 3600 seconds
```

DocuSign's JWT grant rejects tokens with an expiry beyond 3600 seconds. The live `check_jwt_token` path correctly passes `3600` to the SDK, but if `get_docusign_access_token` were ever used it would be rejected.

---

## Design & Reliability Issues

### 10. Tempfile not unlinked in `DocusignSigningViaEmailService`

**File:** `docusign_signing_via_email_service.rb:36-52`

```ruby
tmpfile = @doc.file.download
data = File.read(tmpfile.path)
...
tmpfile.close  # closed but never unlinked — leaks disk space
```

**Fix:**

```ruby
tmpfile = @doc.file.download
begin
  data = File.read(tmpfile.path)
  ...
ensure
  tmpfile.close
  tmpfile.unlink
end
```

---

### 11. `cancel_esign` marks local records cancelled even when the API call fails

**File:** `docusign_esign_helper.rb:133-148`

```ruby
def cancel_esign(doc)
  cancel_docusign_api(doc)                      # rescues quietly on ApiError
  doc.e_signatures.each { |e| e.update(status: "cancelled") }
  doc.update(esign_status: "cancelled")         # runs even if API failed
end
```

If `cancel_docusign_api` rescues an `ApiError`, the envelope stays open in DocuSign, but local records are marked as cancelled. Signers still receive signing emails but IRM thinks the document is cancelled.

**Fix:** Return a boolean from `cancel_docusign_api` and guard:

```ruby
def cancel_esign(doc)
  return unless cancel_docusign_api(doc)  # abort if API failed

  doc.e_signatures.each { |e| e.update(status: "cancelled") }
  doc.update(esign_status: "cancelled")
end

def cancel_docusign_api(doc)
  envelope_api = create_envelope_api(args)
  env = DocuSign_eSign::Envelope.new(status: 'voided', voided_reason: 'Cancelled by Administrator')
  envelope_api.update(args[:account_id], doc.provider_doc_id, env)
  true
rescue DocuSign_eSign::ApiError => e
  handle_error(e)
  false
end
```

---

### 12. Fragile webhook provider detection

**File:** `esign_helper.rb:38-46`

```ruby
if params.dig('data', 'envelopeId').present? && params.dig('data', 'accountId').present?
  helper = DocusignEsignHelper.new
elsif params.dig('payload', 'document', 'id').present?
  helper = DigioEsignHelper.new
```

Provider is guessed from payload shape. Any change to a provider's payload schema silently misroutes or drops webhooks.

**Fix:** Encode the provider in the webhook URL:

```
POST /documents/signature_progress?provider=docusign
POST /documents/signature_progress?provider=digio
```

```ruby
def self.update_signature_progress(params, provider: nil)
  helper = case provider&.downcase
           when 'docusign' then DocusignEsignHelper.new
           when 'digio'    then DigioEsignHelper.new
           else detect_provider_from_params(params)  # backward-compat fallback
           end
  helper&.update_signature_progress(params)
end
```

---

### 13. Unused credential constant

**File:** `docusign_esign_helper.rb:12`

```ruby
DOCUSIGN_ACCESS_TOKEN = Rails.application.credentials[:DOCUSIGN_SECRET_KEY]
```

This constant is defined but never referenced anywhere. The JWT flow fetches tokens dynamically. Remove to avoid confusion with the live auth mechanism.

---

### 14. Raw Redis connection per `JwtCreator` instantiation

**File:** `jwt_auth.rb:18`

```ruby
@redis = Redis.new   # new TCP connection on every JwtCreator.new call
```

**Fix:** Use `Redis.current` (the shared Rails Redis instance) or the Rails cache store:

```ruby
def check_jwt_token
  Rails.cache.fetch('docusign_access_token', expires_in: 59.minutes) do
    fetch_fresh_token
  end
end
```

This also eliminates the manual `store_access_token_in_redis` / `redis.get` plumbing.

---

## Fix Checklist

| # | Severity | File | Fix |
|---|----------|------|-----|
| 1 | High | `jwt_auth.rb` | Delete dead `get_docusign_access_token` method |
| 2 | High | `docusign_esigning.rb` | Fix `handle_api_error` call to pass `ctx`; store in `ctx` not ivar |
| 3 | Low  | `docusign_esign_helper.rb` | Delete no-op `doc.id` line in `download` |
| 4 | High | `jwt_auth.rb` | `ensure tmp_file.unlink` after JWT token fetch |
| 5 | Med  | `docusign_esign_helper.rb` | Gate `debug_output $stdout` on `Rails.env.development?` |
| 6 | Med  | `documents_controller.rb` | Add HMAC webhook signature verification |
| 7 | Low  | `docusign_signing_via_email_service.rb` | Use `esign.name` instead of `esign.email` for signer name |
| 8 | High | `jwt_auth.rb` | Read auth host from credentials, not hardcoded sandbox URL |
| 9 | Low  | `jwt_auth.rb` | Delete `exp: current_time + 6000` (dead code) |
| 10 | Low  | `docusign_signing_via_email_service.rb` | `ensure` block to close and unlink tempfile |
| 11 | Med  | `docusign_esign_helper.rb` | Guard local cancellation on API success |
| 12 | Med  | `esign_helper.rb` | Use `?provider=` query param instead of payload sniffing |
| 13 | Low  | `docusign_esign_helper.rb` | Remove unused `DOCUSIGN_ACCESS_TOKEN` constant |
| 14 | Low  | `jwt_auth.rb` | Replace raw `Redis.new` with `Rails.cache` |

---

## File Reference

| File | Purpose |
|------|---------|
| `app/packs/core/investor_kycs/services/docusign/jwt_auth.rb` | JWT token creation and Redis caching |
| `app/packs/core/investor_kycs/services/docusign/api_creator.rb` | DocuSign API client factory (shared module) |
| `app/packs/core/investor_kycs/services/docusign/docusign_esigning.rb` | Trailblazer operation: send + update |
| `app/packs/core/investor_kycs/services/docusign/docusign_signing_via_email_service.rb` | Builds and sends DocuSign envelope |
| `app/packs/core/investor_kycs/models/concerns/docusign_esign_helper.rb` | High-level DocuSign operations (send, cancel, update, download) |
| `app/packs/core/investor_kycs/models/concerns/docusign_esign_utils.rb` | Low-level envelope/recipient API calls |
| `app/packs/core/investor_kycs/models/helper/esign_helper.rb` | Provider-agnostic factory and webhook router |
| `app/packs/core/documents/jobs/esign_job.rb` | Background job: send document |
| `app/packs/core/documents/jobs/esign_update_job.rb` | Background job: poll status for one document |
