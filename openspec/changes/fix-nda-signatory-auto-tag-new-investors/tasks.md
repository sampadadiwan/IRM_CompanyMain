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

## 3. Add after_commit callback on AccessRight

- [ ] 3.1 In `app/packs/core/access_rights/models/access_right.rb`, add the callback registration (near existing `after_commit` callbacks):
  - `after_commit :auto_tag_nda_signatory_for_folder, on: [:create, :update], if: :folder_with_investor?`
  - **Why:** Covers the GP workflow where AccessRight is granted AFTER the investor already has approved InvestorAccess — the InvestorAccess callback alone misses this path

- [ ] 3.2 In the same file, add the `folder_with_investor?` guard method:
  - Returns true when `owner_type == 'Folder'` AND (`access_to_investor_id.present?` OR `access_to_category.present?`)
  - **Why:** Non-folder AccessRights (Fund, Deal, etc.) and user-level AccessRights should not trigger NDA auto-tag

- [ ] 3.3 In the same file, add the `auto_tag_nda_signatory_for_folder` private method:
  - Find NDA config: `NdaConfig.find_by(owner_type: 'Folder', owner_id: owner_id, enabled: true)`
  - Resolve investors: direct (`access_to_investor_id`) or category-based (`entity.investors.where(category: access_to_category)`)
  - For each investor, find approved InvestorAccess users and check if signatory exists
  - If no signatory, tag the oldest approved user: `NdaSignatory.create!(nda_config:, user_id:, tagged_by_id:)`
  - Rescue `RecordNotUnique` / `RecordInvalid` for idempotency
  - **Why:** Mirrors the InvestorAccess callback logic but triggered from the other direction

- [ ] 3.4 Add Cucumber scenarios to `features/core/nda_signatory_auto_tag.feature`:
  - H5: Folder AccessRight granted → investor with approved access → signatory auto-tagged
  - H6: Category AccessRight granted → multiple matching investors auto-tagged
  - E4: AccessRight granted but investor has no approved InvestorAccess → no auto-tag
  - Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_signatory_auto_tag.feature` and confirm green.

## 4. Rubocop and regression

- [ ] 4.1 Run `bundle exec rubocop app/packs/core/investor_accesses/models/investor_access.rb app/packs/core/nda_configs/controllers/nda_configs_controller.rb app/packs/core/access_rights/models/access_right.rb` — fix any offenses
- [ ] 4.2 Run existing NDA Cucumber tests to verify no regressions:
  - `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_enhancements.feature features/core/nda_expiry_versioning.feature features/core/nda_notifications.feature`
  - Confirm all pass
