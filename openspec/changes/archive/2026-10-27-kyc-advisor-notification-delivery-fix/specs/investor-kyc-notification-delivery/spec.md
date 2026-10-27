# Spec Delta

## Purpose

Defines who receives an InvestorKyc notification email (KYC updated, updates
requested) and when, so that entity employees and GP-side investor advisors with
real access to a KYC reliably get notified, and nobody without access does.

## ADDED Requirements

### Requirement: Notification recipients are limited to those with show access
The system SHALL notify only entity employees and investor advisors (GP-side
employee grants) who are authorized to view the specific KYC, determined by the
KYC's own authorization policy rather than blanket entity membership.

#### Scenario: Employee with fund access is notified
- **WHEN** an investor edits or submits a KYC
- **THEN** an entity employee who has `enable_kycs` and access to the fund behind
  the KYC's capital commitment receives a notification email

#### Scenario: Employee without fund access is not notified
- **WHEN** an investor edits or submits a KYC
- **THEN** an entity employee who lacks access to the fund behind the KYC's
  capital commitment (even if they hold the `investor_kyc_read` permission, since
  that alone does not grant fund access) does not receive a notification email

#### Scenario: Investor advisor with fund access is notified regardless of current switch state
- **WHEN** an investor edits or submits a KYC
- **THEN** a user holding an active investor-advisor employee grant on the KYC's
  entity, with `enable_kycs` on that grant and access to the fund behind the KYC's
  capital commitment, receives a notification email — whether or not they are
  currently switched into that entity

#### Scenario: Investor advisor without fund access is not notified
- **WHEN** an investor edits or submits a KYC
- **THEN** a user holding an investor-advisor employee grant on the KYC's entity
  but without access to the fund behind the KYC's capital commitment does not
  receive a notification email

#### Scenario: Investor advisor of an unrelated entity is not notified
- **WHEN** an investor edits or submits a KYC
- **THEN** a user who holds an investor-advisor employee grant only on a different
  entity does not receive a notification email for this KYC, even if they have
  access to that other entity's own funds

### Requirement: Email delivery recognizes an authorized recipient regardless of their current entity
The email delivery gate SHALL grant delivery to a recipient who holds an active
investor-advisor employee grant on the notified record's entity and is authorized
by that record's own authorization policy to view it, independent of which entity
the recipient is currently switched into. This check is additive to the existing
delivery conditions and MUST NOT suppress email delivery that is already granted by
them.

#### Scenario: Switched-away advisor with access still receives the email
- **WHEN** a notification is generated for a KYC, and the recipient holds an active
  investor-advisor employee grant on the KYC's entity with access to the KYC, but
  the recipient is currently switched into a different entity
- **THEN** the email is delivered to the recipient

#### Scenario: Recipient without a matching grant is unaffected
- **WHEN** a notification is generated for any record, and the recipient holds no
  investor-advisor employee grant on that record's entity
- **THEN** email delivery is decided the same way it was before this requirement
  existed (by current entity membership or investor-access settings)

### Requirement: An investor retains access to their own KYC regardless of other roles they hold
The system SHALL authorize an investor to view their own KYC whenever they belong
to the KYC's investor entity, independent of any other role the authorization
check would otherwise evaluate first (such as an entity-employee role granted to
a corporate or fund-of-funds investor entity by default).

#### Scenario: Corporate or fund-of-funds LP user views their own KYC
- **WHEN** a user belongs to the investor entity that owns a KYC, and that user's
  entity is typed such that they also carry an entity-employee role (e.g. entity
  type `"Company"` or a fund)
- **THEN** the user can view their own KYC

### Requirement: An investor-advisor grant only adds access, never removes it
The system SHALL treat a user's `InvestorAdvisor` grant on a KYC's entity as an
additional way to gain access to that KYC, never as a reason to deny access that
would otherwise be available through another authorization path (an
investor-advisor role, or being the KYC's own investor).

#### Scenario: Grant without employee-level roles does not block other access paths
- **WHEN** a user holds an `InvestorAdvisor` grant on a KYC's entity whose
  allowed roles do not include employee-level access, and that user is
  separately authorized to view the KYC through another path
- **THEN** the user can still view the KYC through that other path

#### Scenario: A grant privileged as company admin is treated as at least as capable as an employee grant
- **WHEN** a user holds an `InvestorAdvisor` grant on a KYC's entity whose
  allowed roles include company-admin-level access but not employee-level
  access, with `enable_kycs` and fund access otherwise satisfied, while
  currently switched into a different entity
- **THEN** the user can view the KYC through that grant

### Requirement: Notification fan-out does not require a capital commitment to already exist
The system SHALL notify an eligible entity employee or investor advisor of a KYC
update even when the KYC has no capital commitments yet, since view-access
fund-scoping does not apply before any fund relationship exists to scope against.

#### Scenario: Employee is notified for a KYC with no capital commitments
- **WHEN** an investor edits or submits a KYC that has no capital commitments
- **THEN** an active entity employee with `enable_kycs` receives a notification
  email, even though they would not yet pass a fund-scoped access check

### Requirement: A recipient is notified at most once per notification event
The system SHALL notify each eligible recipient of a KYC update at most once per
triggering event, even when that recipient is reachable through more than one
recipient path (e.g. both as a home-entity employee and via an investor-advisor
grant).

#### Scenario: Recipient reachable through two paths is notified once
- **WHEN** an investor edits or submits a KYC, and a user is both an active
  home-entity employee and an active investor-advisor grant holder on that same
  entity
- **THEN** that user receives exactly one notification email for the event

### Requirement: Notification fan-out does not block the triggering request
Determining and notifying every eligible recipient for a KYC (entity employees and
entity investor advisors) SHALL happen without making the request that triggered
the notification (an investor's KYC edit or submission) wait for that
determination to complete.

#### Scenario: KYC edit completes without waiting on the notification fan-out
- **WHEN** an investor edits or submits a KYC that has multiple eligible
  notification recipients
- **THEN** the request completes independently of how long authorizing and
  notifying each recipient takes
