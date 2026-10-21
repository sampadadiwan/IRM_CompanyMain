# Spec Delta

## Purpose
One LP mobile app that works against every CapHive environment, switches between regions the way the website does, and always shows exactly one fund manager.

## ADDED Requirements

### Requirement: One app for every environment
Staging and production builds SHALL be the same app (`com.caphive.lp`). The app SHALL list an environment's regions from that environment's `GET /api/mobile/v1/sites`, falling back to a built-in list only when the server cannot answer. Test environments SHALL be hidden from investors until revealed.

#### Scenario: Regions come from the environment
- **WHEN** the app asks an environment for its sites
- **THEN** it lists that deployment's own SITES, so staging never lists a production site

### Requirement: Region switch without signing in again
A user who belongs to two or more regions SHALL be able to switch region from Profile. The current region SHALL mint a single-use, five-minute link with the purpose `mobile_cross_site`, and the target region SHALL turn it into a phone session after checking the user is active and an investor there.

#### Scenario: Switch to US
- **WHEN** Rahul, who belongs to IN and US, switches to US
- **THEN** the US server issues a phone session with no password or code

#### Scenario: Website link refused
- **WHEN** a website region-switch link is presented to the phone API
- **THEN** it is refused with `region_switch_failed`

### Requirement: One fund manager at a time
Home, Documents and Alerts SHALL show exactly one fund manager: the user's last pick on that phone for that region while they still have access to it, otherwise the first by name. The app SHALL never show every fund manager's data together.

#### Scenario: Default to the first
- **WHEN** an investor with Arka Capital and Beta Partners opens Home with no pick
- **THEN** only Arka Capital's funds and To do are shown

#### Scenario: A pick without access
- **WHEN** the requested fund manager is not one the user has access to
- **THEN** the first fund manager is shown instead
