Here’s a structured brainstorm of **requirements, edge cases, and error scenarios** for your multi-region SaaS login experience:

---

## 🔑 Core Requirements

1. **User Synchronization**

   * Each region (India, US) has its own DB.
   * Users must exist in both DBs to support cross-login.
   * Sync must ensure:

     * Consistent identifiers (same `user_id` or a globally unique ID).
     * Same or mapped roles/permissions across DBs.
     * Handling updates (email, name, roles).
   * Decide **how to sync**:

     * **Option A**: One region as source of truth, push updates to others.
     * **Option B**: Centralized Identity Service (auth DB separate from app DBs).
     * **Option C**: Event-driven replication (user create/update triggers sync jobs).

2. **Topbar Dropdown (Region Switcher)**

   * Appears only if a user has access to more than one region.
   * Dropdown options: “India” / “US”.
   * Current region should be visually indicated.

3. **Cross-Region Login**

   * Selecting another region triggers auto-login to the other app.
   * Achieved by:

     * Backend generating a **magic link** for the target region.
     * Browser redirects to that link.
     * Target app consumes the link → logs the user in.
   * Magic links must:

     * Be short-lived (e.g., 30s–2m expiry).
     * Be one-time use.
     * Contain cryptographically signed claims (user ID, timestamp, region).

4. **Permissions & Role Consistency**

   * If a user has access in one region but not another:

     * Dropdown must only show available regions.
   * Permissions must be region-specific but consistent in logic.

---

## ⚠️ Edge Cases

1. **User Exists in One DB but Not the Other**

   * Should dropdown show the region? (probably not).
   * Or show but error on click? (bad UX).

2. **Stale User Sync**

   * User updated in India DB (e.g., email changed).
   * Sync lag → mismatch in US DB → login failure or profile inconsistency.

3. **Permission Mismatch**

   * User has `admin` role in India but only `viewer` in US.
   * When switching, UI/UX must reflect reduced privileges without confusion.

4. **Token/Magic Link Expiry**

   * If user takes too long between dropdown click and redirect.
   * Need a clear error + retry mechanism.

5. **Already Logged In**

   * If user is already logged into the other region in another tab/session:

     * Redirect should skip magic link and reuse active session.
     * Or gracefully re-authenticate.

6. **Multiple Browser Tabs**

   * User switches region in one tab.
   * Another tab is still on old region → might cause confusion or partial session conflicts.

7. **Network Latency / Failures**

   * Redirect fails midway (e.g., DNS between regions).
   * User stuck on intermediate “switching” screen.

8. **Logout Behavior**

   * Does logging out of one region log the user out of all?
   * Or do sessions remain isolated?

---

## ❌ Error Scenarios

1. **Invalid or Tampered Magic Link**

   * Must show “Invalid or expired link” error.
   * Should not leak details (like which region failed).

2. **User Not Permissioned in Target Region**

   * Must fail gracefully:

     * Option A: Don’t show dropdown option at all.
     * Option B: Show option but display “Access not granted”.

3. **Clock Skew**

   * If one server’s clock drifts, magic links may appear expired immediately.

4. **Region App Down**

   * If US app is down, dropdown → redirect will fail.
   * Need fallback messaging: “Region temporarily unavailable”.

5. **Partial Sync**

   * If sync job failed for a subset of attributes (e.g., missing password hash).
   * Must ensure that only magic-link login is allowed (not standard login).

6. **Security Concerns**

   * Magic links must expire quickly.
   * Must prevent replay attacks.
   * Must be scoped to intended region only.

---

✅ **In summary:**

* The key piece is a reliable **user sync strategy** and **secure magic-link login across regions**.
* The UX should prioritize **predictability**: don’t show regions the user can’t access, always give clear feedback on errors, and handle expiry gracefully.
* Operationally, watch for sync failures, downtime, and permission mismatches.

---



Let’s walk through the **full lifecycle** of how a user logged into **US** can seamlessly log into **India** using the `CrossSiteLink` service.

---

## 🌐 Flow: US → India login with `CrossSiteLink`

### 1. User is logged into US site

* The user has an active session in **US**.
* In the top bar, they select **“Switch to India”**.

---

### 2. US app generates a cross-instance link

* The US server calls the service:

  ```ruby
  token = CrossSiteLink.new.generate(
    user.email,
    purpose: "login",
    expires_in: 5.minutes
  )
  ```

* This produces a **signed token** containing:

  ```json
  {
    "email": "user@example.com",
    "purpose": "login"
  }
  ```

* The token is cryptographically signed with `CROSS_INSTANCE_SECRET` and expires in 5 minutes.

* The US app redirects the user to:

  ```
  https://india.myapp.com/sso?token=XYZ
  ```

---

### 3. India app receives the token

* The India app hits `SsoController#login` with `params[:token]`.

* It calls:

  ```ruby
  payload = CrossSiteLink.new.verify(params[:token], purpose: "login")
  ```

* Verification checks:

  * Token signature matches (`CROSS_INSTANCE_SECRET`).
  * Token not expired.
  * Purpose == `"login"`.

* If valid, payload is returned:

  ```json
  { "email": "user@example.com", "purpose": "login" }
  ```

---

### 4. India app finds the user

* The India DB has the same user by **email** (even if the primary key is different).
* It resolves:

  ```ruby
  user = User.find_by!(email: payload["email"])
  ```

---

### 5. User is signed in

* India app calls:

  ```ruby
  sign_in(user)
  ```
* Session/cookies are established locally in India.
* The user is now logged in without re-entering credentials.

---

## ✅ Guarantees

* **Unforgeable**: Token cannot be created or modified without `CROSS_INSTANCE_SECRET`.
* **Time-bound**: Token only valid for a short window (30 seconds).
* **Purpose-scoped**: A login token cannot be reused for another purpose.
* **Email-based mapping**: Works even if primary keys differ between DBs.

---

So in one line:
➡️ The **US app signs the user’s email** into a short-lived, purpose-bound token → **India app verifies it** with the same secret → **logs in the user** by email lookup.

---

```mermaid
sequenceDiagram
    participant User
    participant US_App as US App
    participant India_App as India App

    User->>US_App: Logged in, clicks "Switch to India"
    US_App->>US_App: Generate token with CrossSiteLink (email + purpose + expiry, signed with CROSS_INSTANCE_SECRET)
    US_App-->>User: Redirect to https://india.caphive.com/sso?token=XYZ
    User->>India_App: Open /sso?token=XYZ
    India_App->>India_App: Verify token with CrossSiteLink (check signature, expiry, purpose)
    alt Token valid
        India_App->>India_App: Find user by email from payload
        India_App->>India_App: sign_in(user)
        India_App-->>User: Logged into India App
    else Token invalid/expired
        India_App-->>User: Show "Invalid or expired link"
    end
  ```


## Global Domains


Move from a **single global domain (`app.caphive.com`)** to a **multi-region, multi-tenant domain structure** with region-specific subdomains. Let’s break this down clearly.

---

## 🌍 Current Setup

* **Single app domain:**
  `app.caphive.com` → LB (India region).
* **Client subdomains:**
  `client1.caphive.com`, `client2.caphive.com` → resolve to same LB in India.
* Effectively: all traffic (global + client subdomains) routes to India infra.

---

## 🆕 Target Setup

### Regional Domains

* `us.caphive.com` → LB in **US region**.
* `india.caphive.com` → LB in **India region**.

These become your **entry points** for app users.

### Client Subdomains

* Clients are tied to a region:

  * `client1.india.caphive.com` → LB in India.
  * `client2.us.caphive.com` → LB in US.

This makes client tenancy explicit in the DNS.
➡️ No more ambiguity — a client’s region is encoded in the hostname.

---

## 🏗 How DNS mapping will look

* **Top-level (infra domains):**

  * `us.caphive.com` → CNAME to `us-lb.amazonaws.com` (example).
  * `india.caphive.com` → CNAME to `india-lb.amazonaws.com`.

* **Client subdomains (regionalized):**

  * `client1.india.caphive.com` → CNAME → `india-lb.amazonaws.com`.
  * `client2.us.caphive.com` → CNAME → `us-lb.amazonaws.com`.

---

## ⚙️ Implications

1. **Tenant resolution logic**

   * When a request comes in at `client1.india.caphive.com`, your app knows:

     * Tenant = `client1`
     * Region = `india`
   * Same for US tenants.
   * This removes the guesswork of “which DB to use”.

2. **SSL/TLS Certificates**

   * You’ll need wildcard certs per region:

     * `*.india.caphive.com`
     * `*.us.caphive.com`
   * Or one SAN cert covering all (depends on your cert mgmt strategy).

3. **User login experience**

   * If you introduce SSO / cross-instance login, you’ll need a **cross-domain auth flow** (`us.caphive.com` → `india.caphive.com`).
   * This is where your earlier `CrossSiteLink` work comes in.

4. **Client communication**

   * Existing clients (`client1.caphive.com`) will need to update bookmarks / integrations.
   * You might keep `client1.caphive.com` around temporarily as a **CNAME → client1.india.caphive.com** for backward compatibility.

---

## 📌 Next Steps

1. **DNS**:

   * Create `us.caphive.com` and `india.caphive.com` → point each to regional LB.
   * Create client subdomains (`client1.india.caphive.com`, …) mapped accordingly.

2. **App logic**:

   * Parse subdomain (`client1`) and region (`india`) from `request.host`.
   * Route request to correct DB/tenant.

3. **Auth/SSO**:

   * Implement your cross-instance login using `CrossSiteLink` for seamless switching.

---

```mermaid

flowchart TD
    subgraph DNS["🌍 DNS (caphive.com)"]
        A1[us.caphive.com] -->|CNAME| LB_US
        A2[india.caphive.com] -->|CNAME| LB_IN
        C1[client1.india.caphive.com] -->|CNAME| LB_IN
        C2[client2.us.caphive.com] -->|CNAME| LB_US
    end

    subgraph US_Region["🇺🇸 US Region"]
        LB_US[Load Balancer us-lb.amazonaws.com]
        APP_US1[App Server 1]
        APP_US2[App Server 2]
        DB_US[(US DB)]
        LB_US --> APP_US1
        LB_US --> APP_US2
        APP_US1 --> DB_US
        APP_US2 --> DB_US
    end

    subgraph India_Region["🇮🇳 India Region"]
        LB_IN[Load Balancer india-lb.amazonaws.com]
        APP_IN1[App Server 1]
        APP_IN2[App Server 2]
        DB_IN[(India DB)]
        LB_IN --> APP_IN1
        LB_IN --> APP_IN2
        APP_IN1 --> DB_IN
        APP_IN2 --> DB_IN
    end

```



Here’s a clean **deployment note** you can keep for your team 👇

---

# 🚀 Multi-Region Deployment with Capistrano + Rails Credentials

## Problem

* Currently: one `deploy/production.rb` and one `config/credentials/production.yml.enc`.
* Need: multiple regions (**US** + **India**) with different infra, DBs, and secrets.
* Challenge: still want a seamless, consistent Capistrano workflow.

---

## Solution: Treat Each Region as a Separate Stage

### 1. Capistrano Stage Files

Create per-region stage files:

```bash
deploy/production_us.rb
deploy/production_india.rb
```

Example:

```ruby
# deploy/production_us.rb
server "us-app-server-1", user: "deploy", roles: %w{app db web}
set :rails_env, "production_us"
set :branch, "main"
```

```ruby
# deploy/production_india.rb
server "in-app-server-1", user: "deploy", roles: %w{app db web}
set :rails_env, "production_india"
set :branch, "main"
```

---

### 2. Rails Credentials per Region

Generate credentials:

```bash
rails credentials:edit --environment production_us
rails credentials:edit --environment production_india
```

This creates:

```
config/credentials/production_us.yml.enc
config/credentials/production_india.yml.enc
```

Rails will load the correct file automatically based on `Rails.env`.

---

### 3. Deploy Commands

* Deploy to US:

  ```bash
  cap production_us deploy
  ```
* Deploy to India:

  ```bash
  cap production_india deploy
  ```

---

### 4. Secrets & Shared Config

* **Shared secrets** (e.g. `CROSS_INSTANCE_SECRET`) → must be identical across regions.
* **Region-specific secrets** (DB\_HOST, S3 buckets, etc.) → live in each region’s credentials.

---

## ✅ Result

* Two independent but consistent deploy flows.
* Each region has isolated infra + DB + secrets.
* Shared secrets explicitly duplicated where needed.
* Future-proof: add more regions by just adding another stage + credentials file.

---


## TODOs

* Deployment
* Domain mapping
* Sync Users across instances
* Auto login to approved sites