# CapHive Gmail Add-on

Apps Script source for the Gmail add-on. It is a thin host adapter — all matching, dedup,
authorization and persistence live in the Rails app behind `/api/v1/mail/*`, shared with
the Outlook task pane, so an email filed from Gmail and the same email filed from Outlook
produce the same record.

## One project per environment

An Apps Script project holds exactly one copy of the code and one set of script properties.
There is no notion of a staging build and a production build inside a single project. So
each environment in `config/gmail_addins.yml` gets **its own Apps Script project, with its
own script id and its own name in the Gmail side panel**:

| Environment | Host | Name in Gmail |
|---|---|---|
| `staging` | `https://dev.altconnects.com` | CapHive Filing (Staging) |
| `production` | `https://app.caphive.com` | CapHive Filing |
| `production_us` | `https://app.caphive.us` | CapHive Filing (US) |

The names differ deliberately. Both add-ons appear as icons in the same side panel, and
identical names are how a test email ends up filed into production. The card header carries
the same suffix.

`production` and `production_us` are separate servers with separate databases — a user
exists in one of them and a token from one is meaningless at the other — so they are
separate projects too. If the add-on later stores the host per user (a region dropdown)
rather than per project, those two entries collapse into one and a single Marketplace
listing serves both regions.

## Deploying

```bash
npm install -g @google/clasp@^2
clasp login                        # interactive, once per machine
# also once, in a browser: enable the Apps Script API at
# https://script.google.com/home/usersettings

rake gmail:setup[staging]          # build + create-if-needed + push
```

`rake gmail:setup` creates the project on first run, reuses it on every later run, and
prints the project URL and the remaining UI-only steps. Other tasks:

- `rake gmail:build[<env>]` — generate the source only, no push. Useful for inspecting
  exactly what would be deployed.
- `rake gmail:open[<env>]` — print the project URL.

### What gets pushed

`rake gmail:build` assembles a complete project under `addons/gmail/build/<env>/`
(gitignored):

| File | Source |
|---|---|
| `Code.gs` | copied verbatim from `addons/gmail/Code.gs` |
| `Config.gs` | generated from `lib/templates/gmail_config.gs.erb` |
| `appsscript.json` | generated from `lib/templates/gmail_appsscript.json.erb` |

`Code.gs` is byte-identical across every environment. That is the point: a bug fixed
against staging is the same code that reaches production, and the only thing that varies is
the generated config.

**There is no script property to set.** The host is compiled into `Config.gs` at build
time, so a freshly pushed project is already correct. A `CAPHIVE_API_URL` script property
still overrides it, for repointing a deployed add-on during an incident without a push.

The previous build required the property to be set by hand and, when it was missing, fell
back to a hardcoded dev hostname — so a production install could quietly talk to a dev
server.

### Script ids

`addons/gmail/.clasp.<env>.json` records each environment's script id. Gitignored: the
projects belong to whichever Google account created them, so they differ per developer.

To adopt a project someone else created, or one made in the browser:

```bash
SCRIPT_ID=<id> rake gmail:setup[staging]
```

## Installing into a mailbox

clasp can push code and cut a versioned deployment, but installing a Gmail add-on is a UI
action. After `rake gmail:setup`:

1. Open the printed project URL.
2. **Deploy → Test deployments → Install.**
3. Reload Gmail and open a message. The add-on is in the right-hand side panel.

Test deployments only ever install for the script's owner. Reaching clients requires a
Google Workspace Marketplace listing — see "Distribution" in
`docs/technical/mail_addin_review.md`.

## OAuth scopes

Only three, and none of them restricted:

- `gmail.addons.current.message.readonly` — the open message only
- `gmail.addons.execute`
- `script.external_request` — to reach the CapHive API

The previous manifest also requested `gmail.readonly`, full-mailbox read. That is a
**restricted** scope requiring an annual CASA security assessment before the add-on can be
listed, and it was only needed because the action handlers called
`GmailApp.getMessageById()` without first calling `setCurrentMessageAccessToken`. They now
set it, so the broad scope is gone. What remains is *sensitive*, which needs OAuth
verification but no security assessment.

`urlFetchWhitelist` is generated per environment and contains only that environment's host,
so a build cannot call out to anywhere else.

## Sign-in

Sign-in opens `/gmail_addin/oauth_start` in a browser tab, where the normal CapHive session
applies — including SSO and MFA. Rails mints a bearer token and hands it back through Apps
Script's `usercallback`, and `authCallback` stores it in `UserProperties`.

No password is ever typed into a card. CardService has no password input type, so the
previous sign-in card collected the user's CapHive password in a **plaintext, unmasked**
field, which also bypassed SSO entirely and is a standard Marketplace rejection.

## Publishing checklist

- Verify the OAuth consent screen lists only the three scopes above.
- A standard GCP project (not Apps Script's default) is required for a Marketplace listing.
- Privacy policy and terms URLs on a domain verified to you, plus icons, screenshots and a
  demo video showing each scope in use.
