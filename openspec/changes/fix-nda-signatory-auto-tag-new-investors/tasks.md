# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Fix controller auto-tag scoping (folder-scoped)

- [ ] 1.1 In `app/packs/core/nda_configs/controllers/nda_configs_controller.rb`, modify `auto_tag_default_signatories(nda_config)` (line 214):
  - Replace `InvestorAccess.where(entity_id: nda_config.entity_id, approved: true)` with a folder-scoped query
  - Use `Investor.owner_access_rights(@folder, nil).pluck(:id)` to get investor IDs with folder-level access
  - Then query `InvestorAccess.where(entity_id: nda_config.entity_id, investor_id: investor_ids, approved: true).order(:created_at).group_by(&:investor_id)`
  - Keep the existing `each_value` loop that tags the oldest user per investor
  - **Why:** The current entity-wide query tags signatories for investors who don't even have access to the folder

- [ ] 1.2 Write `features/core/nda_signatory_auto_tag.feature` — Phase 1 scenarios:
  - H3: NDA creation only tags folder-access investors (not entity-wide)
  - E3: Entity-level investor without folder access is not tagged
  - Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_signatory_auto_tag.feature` and confirm green before starting phase 2.

## 2. Add after_commit callback on InvestorAccess

- [ ] 2.1 In `app/packs/core/investor_accesses/models/investor_access.rb`, add the callback registration (after line 179, near existing `after_commit`):
  - `after_commit :auto_tag_nda_signatory_if_needed, on: [:create, :update], if: :approved?`
  - **Why:** Catches all creation paths (UI, CSV import, admin panel, console)

- [ ] 2.2 In the same file, add the private method `auto_tag_nda_signatory_if_needed`:
  - Query `NdaConfig.where(entity_id: entity_id, enabled: true, owner_type: 'Folder')` to find candidate NDA configs
  - For each NDA config, check if the investor has an `AccessRight` on that folder: `AccessRight.exists?(owner_type: 'Folder', owner_id: nda_config.owner_id, entity_id: entity_id)` with investor match (`access_to_investor_id: investor_id` OR category match)
  - Check if investor already has a signatory: `NdaSignatory.where(nda_config_id:).where(user_id: InvestorAccess.where(investor_id: investor_id, entity_id: entity_id, approved: true).select(:user_id)).exists?`
  - If no signatory exists, create one: `NdaSignatory.create(nda_config: nda_config, user_id: user_id, tagged_by_id: granted_by || user_id)`
  - Rescue `ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid` for idempotency
  - **Why:** New investors added after NDA setup get zero signatories; their LPs see the "blocked" page

- [ ] 2.3 Add Phase 2 scenarios to `features/core/nda_signatory_auto_tag.feature`:
  - H1: New investor access created as approved → signatory auto-tagged
  - H2: Unapproved access toggled to approved → signatory auto-tagged
  - E1: No auto-tag when folder has no NDA
  - E2: No duplicate signatory when investor already has one
  - X1: Race condition (duplicate create) handled gracefully
  - Write step definitions in `features/step_definitions/nda_signatory_auto_tag_steps.rb`
  - Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_signatory_auto_tag.feature` and confirm green.

## 3. Rubocop and regression

- [ ] 3.1 Run `bundle exec rubocop app/packs/core/investor_accesses/models/investor_access.rb app/packs/core/nda_configs/controllers/nda_configs_controller.rb` — fix any offenses
- [ ] 3.2 Run existing NDA Cucumber tests to verify no regressions:
  - `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_enhancements.feature features/core/nda_expiry_versioning.feature features/core/nda_notifications.feature`
  - Confirm all pass
