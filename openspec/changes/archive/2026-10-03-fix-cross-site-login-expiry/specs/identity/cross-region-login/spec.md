# Spec Delta

## Purpose

Lets a user who belongs to more than one regional deployment move from one region's site to another
without re-entering a password, by carrying a short-lived, single-use hand-off credential between the
two regions, and defines how every outcome of that hand-off — success and each distinct failure — is
surfaced to the user and recorded for support.

## ADDED Requirements

### Requirement: Region switch entry point

The application SHALL offer a region selector to any signed-in user whose profile lists more than one
region, and SHALL hide it otherwise. The selector SHALL offer only region codes that both appear on
the user's profile and correspond to a region present in the deployment's region list. Region codes
SHALL be compared and displayed after trimming surrounding whitespace and upper-casing, so that
inconsistently stored values resolve to the same region.

#### Scenario: Multi-region user sees the selector

- **WHEN** a signed-in user whose profile lists two regions loads any page
- **THEN** the region selector is rendered with one option per listed region and the active region
  pre-selected

#### Scenario: Single-region user sees no selector

- **WHEN** a signed-in user whose profile lists exactly one region loads any page
- **THEN** no region selector is rendered

#### Scenario: Inconsistent casing and spacing still resolves

- **WHEN** a user's profile records their regions as `IN, us`
- **THEN** the selector offers `IN` and `US`, and choosing `US` starts a switch to the US region

#### Scenario: Undeployed region code is not offered

- **WHEN** a user's profile lists a region code that is not a key in the deployment's region list
- **THEN** that code is omitted from the selector, and the user's stored profile value is left
  unchanged

#### Scenario: Region list stored as a JSON array

- **WHEN** a user's profile stores its region list as a JSON array rather than a comma-separated
  string
- **THEN** the selector offers the same regions as it would for the equivalent comma-separated value,
  and no malformed option is produced

### Requirement: Hand-off credential issuance

On a region switch request, the origin region SHALL issue a hand-off credential that carries the
user's email address, the fixed purpose of cross-region login, the destination region code, and the
origin region code. The credential SHALL be cryptographically signed with the secret shared by the
regions, SHALL expire 5 minutes after issuance, and SHALL be safe to carry unescaped in a URL query
string. The destination region code SHALL be normalised before it is embedded. A switch request
naming a region absent from the deployment's region list, or absent from the requesting user's own
normalised region list, SHALL be refused before any credential is issued — the requested destination
SHALL NOT be trusted merely because the requester has some region access.

#### Scenario: Credential issued for a valid destination

- **WHEN** a signed-in multi-region user requests a switch to a deployed region
- **THEN** a signed hand-off credential carrying their email, the login purpose, and the normalised
  origin and destination region codes is issued with a 5-minute expiry, and the user is redirected to
  the destination region carrying it

#### Scenario: Unknown destination refused without a credential

- **WHEN** a switch is requested for a region code that is not in the deployment's region list
- **THEN** no credential is issued, no redirect to another host occurs, and the user remains on the
  origin region with a message that the region is unavailable

#### Scenario: Destination outside the requester's own regions is refused

- **WHEN** a user whose profile lists only `IN` submits a switch request naming destination `US`,
  which is a deployed region
- **THEN** no credential is issued, no redirect to another host occurs, and the request is refused as
  not permitted

#### Scenario: Credential survives URL transport unaltered

- **WHEN** an issued credential is placed in a URL query string and read back after standard query
  parsing
- **THEN** it is byte-for-byte identical to the issued value and still verifies

#### Scenario: Destination region code is normalised at issuance

- **WHEN** a switch is requested with a destination value of `" us "`
- **THEN** the credential embeds `US`, and it verifies on the region whose active region code is `US`

### Requirement: Secure destination addressing

The deployment's region list SHALL be configuration data in a declarative format that the
application parses rather than evaluates as code. Every address in it SHALL use the `https` scheme.
The application SHALL fail to start when the region list is absent, unparseable, contains a non-https
address, or does not contain the deployment's own active region code. All reads of the region list and
of the active region code SHALL go through a single accessor, so that no two call sites can disagree
about which regions exist.

#### Scenario: Switch redirect uses https

- **WHEN** a hand-off redirect to another region is issued
- **THEN** its address uses the `https` scheme, so that no additional scheme-upgrade redirect is
  needed before the destination region is reached

#### Scenario: Malformed region list prevents startup

- **WHEN** the application starts with a region list that cannot be parsed
- **THEN** startup fails with an error naming the region list setting, rather than starting and
  failing later on a switch

#### Scenario: Insecure address prevents startup

- **WHEN** the application starts with a region list containing an `http` address
- **THEN** startup fails with an error naming the offending region

#### Scenario: Active region missing from the list prevents startup

- **WHEN** the application starts with an active region code that is not a key in the region list
- **THEN** startup fails with an error naming both values

### Requirement: Destination site resolution

On arrival at the destination region, the hand-off SHALL first resolve which company site the user
belongs to in that region and redirect to it, falling back to the region's default site when the
user's company has no site configured there. This resolution step SHALL read the hand-off credential
without consuming it, because the browser has not yet reached the site that will establish the
session.

#### Scenario: User redirected to their company site

- **WHEN** a hand-off arrives at the destination region for a user whose company has a site there
- **THEN** the browser is redirected to that company site's sign-in hand-off address, carrying the
  same unconsumed credential

#### Scenario: Company without a site falls back to the default

- **WHEN** a hand-off arrives for a user whose company has no site configured in the destination
  region
- **THEN** the browser is redirected to the region's default site, carrying the same unconsumed
  credential

#### Scenario: Resolution does not consume the credential

- **WHEN** site resolution completes and the browser proceeds to the resolved site
- **THEN** the credential is still unused, and the sign-in step accepts it

#### Scenario: Unknown user is refused at resolution

- **WHEN** a hand-off arrives naming an email address with no account in the destination region
- **THEN** no session is established, and the user is sent to the destination region's sign-in screen
  with a message that no account was found for them there

### Requirement: Single-use credential consumption

A hand-off credential SHALL establish a session exactly once. The sign-in step SHALL atomically claim
the credential before establishing the session, such that concurrent presentations of the same
credential result in exactly one session and every other presentation being refused as already used.
The claim SHALL be visible to every application server serving the destination region, and SHALL be
retained at least until the credential's expiry.

#### Scenario: First use establishes the session

- **WHEN** a valid, unexpired, unused credential is presented to the sign-in step
- **THEN** the named user is signed in on the destination region and redirected to its home page

#### Scenario: Second use is refused

- **WHEN** a credential that has already established a session is presented again within its
  5-minute lifetime
- **THEN** no session is established and the outcome is the already-used failure

#### Scenario: Concurrent uses yield one session

- **WHEN** the same credential is presented twice simultaneously
- **THEN** exactly one presentation establishes a session and the other is refused as already used

#### Scenario: Claim is shared across the region's servers

- **WHEN** a credential is consumed by one application server and then presented to a different
  application server in the same region
- **THEN** it is refused as already used

### Requirement: Hand-off validation and distinct failure reasons

The sign-in step SHALL reject a credential that is missing, unparseable, incorrectly signed, expired,
already used, issued for a different purpose, or issued for a region other than the arriving region.
Each rejection SHALL be attributed to exactly one distinct reason: `missing`, `invalid`, `expired`,
`already_used`, `wrong_region`, or `secret_mismatch`. Distinguishing an incorrectly signed credential
caused by a divergent shared secret from one caused by tampering SHALL be reported as
`secret_mismatch` only when the regions' secret fingerprints are known to differ, and as `invalid`
otherwise.

#### Scenario: Missing credential

- **WHEN** the sign-in address is requested with no credential in the query string
- **THEN** the rejection reason is `missing`

#### Scenario: Expired credential

- **WHEN** a correctly signed credential is presented more than 5 minutes after issuance
- **THEN** the rejection reason is `expired`

#### Scenario: Tampered credential

- **WHEN** a credential whose signature does not match its contents is presented and the regions'
  secret fingerprints agree
- **THEN** the rejection reason is `invalid`

#### Scenario: Divergent shared secret

- **WHEN** a credential fails signature verification and the regions' secret fingerprints are known
  to differ
- **THEN** the rejection reason is `secret_mismatch`

#### Scenario: Credential for another region

- **WHEN** a credential embedding destination region `IN` is presented to the region whose active
  region code is `US`
- **THEN** the rejection reason is `wrong_region`

#### Scenario: Credential minted for another purpose

- **WHEN** a correctly signed credential carrying a purpose other than cross-region login is
  presented
- **THEN** the rejection reason is `invalid` and no session is established

#### Scenario: Clock drift within the lifetime is tolerated

- **WHEN** the issuing and verifying regions' clocks differ by less than the credential lifetime and
  the credential is presented promptly
- **THEN** it verifies and establishes a session

### Requirement: Failed switch recovery

A rejected hand-off SHALL send the user to the destination region's existing sign-in screen with an
alert that states, in non-technical language, that the switch could not be completed and gives the
reason-specific phrase. When the origin region can be determined from the credential, the alert SHALL
include a link to that region's home page. The alert SHALL NOT expose the credential, a server
identifier, or an internal error name. A `secret_mismatch` rejection SHALL NOT invite the user to
retry, because retrying cannot succeed.

#### Scenario: Expired switch offers a way back

- **WHEN** a switch to the US region is rejected as `expired` and the credential names `IN` as its
  origin
- **THEN** the user lands on the US sign-in screen with an alert saying the hand-off link had expired
  and a link back to the India region's home page

#### Scenario: Already-used switch offers a way back

- **WHEN** a switch is rejected as `already_used`
- **THEN** the alert says the link had already been used and offers the same link back to the origin
  region

#### Scenario: Unreadable credential omits the back link

- **WHEN** a switch is rejected as `missing` or `invalid`, so no origin region can be read
- **THEN** the alert says the switch could not be completed and contains no "return to" link, and the
  sign-in form remains usable

#### Scenario: Configuration failure does not invite a retry

- **WHEN** a switch is rejected as `secret_mismatch`
- **THEN** the alert reports a configuration problem and asks the user to sign in, and does not
  suggest trying the switch again

#### Scenario: No technical detail is shown

- **WHEN** any rejection is rendered
- **THEN** the page contains no credential value, no host or server name, and no internal error class
  name

### Requirement: Hand-off observability

Every rejected hand-off SHALL be recorded with its distinct reason, the destination region, the
identity of the application server that handled it, and the subject's email address when it can be
read. A successful hand-off SHALL be recorded with the subject's email address and both region codes.
No record SHALL contain the credential value in full.

#### Scenario: Rejection is recorded with its reason

- **WHEN** a hand-off is rejected for any reason
- **THEN** a log entry records that reason, the destination region, the handling server, and the
  subject's email address when readable

#### Scenario: Success is recorded

- **WHEN** a hand-off establishes a session
- **THEN** a log entry records the subject's email address and the origin and destination region codes

#### Scenario: Credential never appears in a record

- **WHEN** any hand-off outcome is recorded
- **THEN** no log entry contains the credential value

### Requirement: Inter-region trust verification

Each region SHALL publish a non-reversible fingerprint of the shared inter-region secret on its
health-check surface, such that two regions' fingerprints are equal if and only if their secrets are
equal. The endpoint SHALL NOT disclose the secret or any value from which it can be recovered, and
SHALL report an explicit unconfigured state rather than a fingerprint when the secret is absent.

#### Scenario: Matching secrets produce matching fingerprints

- **WHEN** two regions configured with the same shared secret are each queried
- **THEN** both return the same fingerprint

#### Scenario: Divergent secrets produce differing fingerprints

- **WHEN** two regions configured with different shared secrets are each queried
- **THEN** their fingerprints differ

#### Scenario: Secret is not recoverable from the response

- **WHEN** the endpoint is queried
- **THEN** the response contains only a fixed-length fingerprint and no portion of the secret

#### Scenario: Unconfigured secret is reported explicitly

- **WHEN** the endpoint is queried on a region with no shared secret configured
- **THEN** it reports the secret as unconfigured rather than returning a fingerprint

### Requirement: Clock synchronisation assurance

Because the credential's validity is judged by comparing an absolute expiry stamped by the origin
region against the destination region's own clock, every application server SHALL run clock
synchronisation, and operations SHALL be alerted when any server's clock offset grows large enough to
threaten hand-offs. The alert threshold SHALL be below the credential lifetime, so that drift is
reported before it starts rejecting switches.

#### Scenario: Deployment asserts clock synchronisation

- **WHEN** the application is deployed to a server whose clock synchronisation service is not running
- **THEN** the deployment reports that server as failing the check

#### Scenario: Drift is alerted before it breaks switches

- **WHEN** an application server's clock offset exceeds the alert threshold
- **THEN** an operations alert fires naming that server, while switches are still succeeding

### Requirement: Stored region list housekeeping

Existing user profiles SHALL have their stored region list normalised once — trimmed, upper-cased and
de-duplicated, with a JSON-array value converted to the stored string form — without adding or
removing any region from any user's access. The housekeeping SHALL be repeatable with no further
effect and SHALL report what it changed before changing anything.

#### Scenario: Inconsistent values normalised

- **WHEN** housekeeping runs against a profile whose region list is `" in ,US, us"`
- **THEN** the profile's region list becomes `IN,US` and the set of regions the user can reach is
  unchanged

#### Scenario: JSON array converted

- **WHEN** housekeeping runs against a profile whose region list is the JSON array `["US","IN"]`
- **THEN** the profile's region list becomes `IN,US`

#### Scenario: Repeat run changes nothing

- **WHEN** housekeeping runs a second time
- **THEN** no profile is modified

#### Scenario: Dry run reports without writing

- **WHEN** housekeeping runs in reporting mode
- **THEN** it lists the profiles it would change and modifies none of them
