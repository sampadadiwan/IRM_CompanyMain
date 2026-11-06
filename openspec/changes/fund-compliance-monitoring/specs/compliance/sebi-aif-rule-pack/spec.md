# Spec Delta

## Purpose

Defines the content and expected results of the first CapHive rule pack, "SEBI — Alternative Investment Funds", so QA can verify each check's figures against a worked fund before the pack is published.

## ADDED Requirements

### Requirement: SEBI pack classifications
The SEBI pack SHALL offer the classifications Category I, Category II, Category III, Category I — Large Value Fund and Category II — Large Value Fund, and SHALL be published only after counsel review of every check's figures and citations.

#### Scenario: Classifications offered
- **WHEN** a compliance editor attaches the SEBI pack
- **THEN** the five classifications are offered

### Requirement: Single-investee concentration
For Category I and II the pack SHALL test that investment cost in any one investee ≤ 25% of investable funds (corpus − estimated expenses); for Large Value Fund classifications ≤ 50%; for Category III ≤ 10% of NAV. The tested setting is decided by counsel before publishing.

#### Scenario: Exactly 25% passes
- **WHEN** investable funds are ₹200.00 cr and Acme's cost is ₹50.00 cr
- **THEN** the check passes (25.00% ≤ 25%)

#### Scenario: Above 25% breaches
- **WHEN** investable funds are ₹270.00 cr and Acme's cost is ₹72.00 cr
- **THEN** the check is Breach (26.67%)

#### Scenario: Large Value Fund limit
- **WHEN** a Category II — LVF fund has 40% in one investee
- **THEN** the check passes (40% ≤ 50%)

### Requirement: Continuing interest — amount
The pack SHALL test that the sponsor/manager's investment ≥ lower of 2.5% of corpus and ₹5 cr for Category I and II, and lower of 5% of corpus and ₹10 cr for Category III, using the entity's "Sponsor/manager" mapping.

#### Scenario: Cap applies
- **WHEN** corpus is ₹300 cr and the sponsor committed ₹6.00 cr
- **THEN** required = lower of ₹7.50 cr and ₹5.00 cr = ₹5.00 cr and the check passes

#### Scenario: Percentage applies
- **WHEN** corpus is ₹100 cr and the sponsor committed ₹2.00 cr
- **THEN** required = lower of ₹2.50 cr and ₹5.00 cr = ₹2.50 cr and the check is Breach (₹0.50 cr short)

### Requirement: Continuing interest — pro-rata
The pack SHALL test that the sponsor/manager's paid-in ≥ required interest × others' paid-in share (others' paid-in ÷ others' commitments).

#### Scenario: Pro-rata shortfall
- **WHEN** required interest is ₹5.00 cr, others paid ₹132.30 cr of ₹294.00 cr and the sponsor paid ₹2.10 cr
- **THEN** the check is Breach: 132.30 ÷ 294.00 = 45%; 5.00 × 45% = ₹2.25 cr; shortfall ₹0.15 cr

### Requirement: Minimum investment and investor count
The pack SHALL test each investor's commitment ≥ ₹1 cr, or ≥ ₹25 lakh for investors in the "Employees/directors" mapping, and that the scheme has at most 1,000 investors, counted as distinct investors with a non-zero commitment, excluding those fully transferred out (definition to be confirmed by counsel before publishing).

#### Scenario: Employee at ₹25 lakh passes
- **WHEN** an investor in the employees mapping commits ₹25,00,000
- **THEN** the minimum-investment check passes for that investor

#### Scenario: Zero and transferred-out investors not counted
- **WHEN** a scheme has 1,000 investors with non-zero commitments, 3 with zero commitment and 2 fully transferred out
- **THEN** the count is 1,000 and the check passes

#### Scenario: 1,001 investors breaches
- **WHEN** a scheme has 1,001 investors with a commitment
- **THEN** the investor-count check is Breach (1,001 > 1,000)

### Requirement: Investor group concentration
The pack SHALL group investors sharing a beneficial owner in confirmed KYC ownership facts and show Needs review with an enhanced due-diligence duty when any group holds ≥ 50% of scheme commitments.

#### Scenario: Group at exactly 50%
- **WHEN** two investors with a common beneficial owner hold 50.00% of commitments
- **THEN** the check shows Needs review and an enhanced due-diligence duty is created

### Requirement: SEBI duties
The pack SHALL include: investor and investment due diligence for each new investor and each new investment (related parties, land-border countries — the land-border country list ships with the pack); a quarterly SEBI report duty linking to the existing SEBI report screen; and a yearly compliance test report / PPM audit duty requiring evidence.

#### Scenario: Quarterly report duty
- **WHEN** a fund carries the SEBI pack and monitoring is on
- **THEN** a "Quarterly SEBI report" duty is scheduled each quarter with a link to the SEBI report screen

#### Scenario: Yearly duty needs evidence
- **WHEN** the compliance test report duty is marked done without a document
- **THEN** it is refused with "Upload the evidence"
