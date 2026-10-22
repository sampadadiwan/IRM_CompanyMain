# Spec Delta

## Purpose

Decides which client entities have the Ops Assistant and which of their users may use it: switched on
per entity by CapHive, granted per user by the client's admin, and unavailable without the client's own
Anthropic key.

## ADDED Requirements

### Requirement: CapHive switches the assistant on per client entity
The Ops Assistant SHALL be available to an entity only while that entity's Ops Assistant permission is
on. Only a CapHive super user SHALL be able to switch the permission on or off.

#### Scenario: Permission off hides the assistant
- **WHEN** an entity's Ops Assistant permission is off
- **THEN** no user of that entity sees the Ops Assistant menu item, and opening the page directly returns "Not authorized."

#### Scenario: Only a super user can switch it on
- **WHEN** a company admin of the entity tries to switch the Ops Assistant permission on
- **THEN** the change is refused and the permission stays off

### Requirement: The client admin enables the assistant per user with a user permission
A user SHALL be able to use the Ops Assistant only when they are an employee of the entity and both the
entity's and the user's own Ops Assistant permission are on. The user permission SHALL mirror the entity
permission, like CapHive's other per-feature permissions; no new role is introduced. A company admin of
the entity SHALL be able to tick and untick it for their users.

#### Scenario: User permission and entity permission both on
- **WHEN** an employee's Ops Assistant permission is on and the entity's permission is on
- **THEN** the Ops Assistant appears in their menu and the page opens

#### Scenario: User permission off is refused
- **WHEN** an employee whose own Ops Assistant permission is off opens the page directly
- **THEN** they see "Not authorized." and nothing is sent to the assistant

#### Scenario: User permission on but entity permission off
- **WHEN** a user's Ops Assistant permission is on but the entity's has been switched off
- **THEN** the menu item is hidden and the page returns "Not authorized."

#### Scenario: Investors and advisors never get it
- **WHEN** a user whose only access to the entity is as an investor or investor advisor opens the page
- **THEN** they see "Not authorized."

### Requirement: The client's own Anthropic key is required
The assistant SHALL run only with the Anthropic API key stored in the entity's settings. When the key is
missing it SHALL be unavailable, and it SHALL never use a CapHive key instead. The key SHALL be stored
encrypted and SHALL never be shown back in full.

#### Scenario: No key
- **WHEN** a permitted user opens the Ops Assistant and the entity has no Anthropic key
- **THEN** the page shows "Add your Anthropic API key in Entity Settings to use the Ops Assistant." and no question can be sent

#### Scenario: Key refused by Anthropic
- **WHEN** a question is sent and Anthropic rejects the entity's key
- **THEN** the turn ends with "Your Anthropic key was refused. Ask your admin to update it." and no other key is tried

### Requirement: Access is re-checked at every step
The asking user's access SHALL be re-checked when a question is sent, when the turn starts running, when
an approval is clicked, and before an approved action is carried out.

#### Scenario: Permission removed while a card is waiting
- **WHEN** a user's Ops Assistant permission is unticked while one of their approval cards is waiting
- **THEN** clicking Approve is refused with "Not authorized." and nothing is written
