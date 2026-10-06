# Spec Delta

## Purpose

Allows the GP to revoke a previously accepted NDA from the Status Dashboard, resetting the investor's access and creating an append-only audit record with an optional reason.

## ADDED Requirements

### Requirement: GP can revoke an accepted NDA
The system SHALL allow a GP to revoke the NDA acceptance of an investor with "Accepted" status from the NDA Status Dashboard.

#### Scenario: GP revokes accepted investor
- **WHEN** the GP clicks "Revoke" next to an accepted investor and confirms the dialog
- **THEN** a new NdaAcceptance record is created with status "revoked," recording the GP user, timestamp, and NDA version
- **THEN** the investor's status on the dashboard changes to "Revoked"

#### Scenario: Revoke action not available for non-accepted investors
- **WHEN** an investor has status Pending, Declined, Exempt, or Revoked
- **THEN** the "Revoke" action is not visible for that investor

### Requirement: Revocation includes optional reason
The system SHALL allow the GP to enter an optional free-text reason when revoking an NDA acceptance, stored on the NdaAcceptance record.

#### Scenario: GP revokes with reason
- **WHEN** the GP revokes an acceptance and enters "Deal terminated" as the reason
- **THEN** the NdaAcceptance record's reason field contains "Deal terminated"
- **THEN** the reason is visible in the NDA Status Dashboard and included in the export

#### Scenario: GP revokes without reason
- **WHEN** the GP revokes an acceptance and leaves the reason field empty
- **THEN** the NdaAcceptance record's reason field is NULL
- **THEN** the dashboard shows no reason for that revocation

### Requirement: Revocation requires confirmation
The system SHALL show a confirmation dialog before revoking, stating the investor name and the consequence (loss of folder access).

#### Scenario: GP cancels revocation
- **WHEN** the GP clicks "Revoke" but clicks "Cancel" on the confirmation dialog
- **THEN** no revocation occurs and the investor's status remains "Accepted"

### Requirement: Revoked investor must re-accept
The system SHALL gate folder access for a revoked investor the same way as a Pending investor — the NDA acceptance screen is shown on next folder visit.

#### Scenario: Revoked investor visits folder
- **WHEN** a user of a revoked investor visits the NDA-gated folder
- **THEN** they see the NDA acceptance screen (same as a first-time visitor)

#### Scenario: Revoked investor re-accepts
- **WHEN** a user of a revoked investor accepts the NDA again
- **THEN** a new NdaAcceptance record is created with status "accepted"
- **THEN** the investor's status returns to "Accepted" on the dashboard

### Requirement: Revocation creates audit trail
The system SHALL preserve the full revocation history as append-only NdaAcceptance records, never deleting or updating existing records.

#### Scenario: Full lifecycle audit trail
- **WHEN** an investor goes through accept → revoke → re-accept
- **THEN** three NdaAcceptance records exist: accepted, revoked, accepted — each with its own timestamp, user, and version
