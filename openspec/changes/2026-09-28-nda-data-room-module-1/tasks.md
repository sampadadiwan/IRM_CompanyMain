# Tasks — nda-data-room-module-1

## 1. Data model

- [ ] 1.1 Add migration creating `nda_configs` table (owner_type string not null, owner_id bigint not null — polymorphic, entity_id FK, enabled boolean default true, nda_document_data text, validity_type string(20) default "until_revoked", validity_days integer, validity_date date, acceptance_method string(20) default "click_through", contact_email string(255), notification_emails text, version integer default 1, created_by_id bigint, updated_by_id bigint, deleted_at datetime, timestamps; indexes: unique composite on [owner_type, owner_id], entity_id, deleted_at). Follow local schema-drift procedure (restore `schema.rb`/`schema_test.rb`, hand-insert table, `db:clean_schema`). Verify: `git diff db/schema.rb` shows only the new table.
- [ ] 1.2 Add `NdaConfig` model in `app/packs/core/nda_configs/models/`: `belongs_to :owner, polymorphic: true`, belongs_to entity/created_by/updated_by, `FileUploader::Attachment(:nda_document)`, `include Trackable.new`, `VALIDITY_TYPES`/`ACCEPTANCE_METHODS`/`VALIDITY_DAY_OPTIONS` constants, all validations (validity_type/acceptance_method inclusion, conditional validity_days/validity_date, contact_email format, notification_emails array format, nda_document required when enabled, validity_date must be future), `set_entity_from_owner` before_validation (sets `entity_id` from `owner.entity_id`). Verify: `bin/rails runner` creates and validates a record in a rolled-back transaction.
- [ ] 1.3 Add `WithNda` concern in `app/packs/core/nda_configs/models/concerns/with_nda.rb`: encapsulates `has_one :nda_config, as: :owner, class_name: "NdaConfig", dependent: :destroy` and `nda_required?` (returns `nda_config&.enabled? || false`). Follows `WithDataRoom`/`WithFolder`/`WithAccessRights` pattern. Any model needing NDA includes this concern.
- [ ] 1.4 Add `include WithNda` to `Folder`. Add `in_data_room?` (memoized, checks self or ancestors for `data_room_root?`), and `data_room_root?` (`name == "Data Room" && parent&.system?`). These two methods are folder-specific and stay on Folder, not in the concern. Verify: `bin/rails runner` on a known Data Room folder returns true for `in_data_room?` and false for a Fund folder; `nda_required?` available via concern.

## 2. Policy

- [ ] 2.1 Add `NdaConfigPolicy` in `app/packs/core/nda_configs/policies/`: new?, create?, edit?, update? all delegate to `manageable?` which requires `user.curr_role_company?`, `record.owner&.in_data_room?` (for Folder owners), and `FolderPolicy.new(user, record.owner).update?`. Verify: `bin/rails runner` with a GP user on a Data Room folder returns true; with an LP user returns false; with a GP on a non-Data Room folder returns false.

## 3. Controller and routes

- [ ] 3.1 Add routes: singular nested `resource :nda_config` under folders (controller: "nda_configs", only: new/create/edit/update). Verify: `bin/rails routes | grep nda_config` shows the four routes.
- [ ] 3.2 Add `NdaConfigsController` in `app/packs/core/nda_configs/controllers/`: before_action `set_owner` (resolves owner from route params — `folder_id` for folders; verifies entity matches current user), before_action `set_nda_config` for edit/update. Actions: `new` (builds or loads config, authorizes, renders modal), `create` (builds, sets created_by/updated_by, authorizes, saves or re-renders), `edit` (authorizes, renders modal), `update` (authorizes, sets updated_by, updates or re-renders). Turbo Stream responses: replace `nda_settings_modal` frame (modal content) and Turbo Stream replace `folder_{id}` `<li>` element (lock icon update, no Turbo Frame on the tree). Verify: dev server — GP can open NDA Settings modal from Actions dropdown on a Data Room folder.

## 4. Views

- [ ] 4.1 Add NDA Settings modal partial `_settings_modal.html.erb` in `app/packs/core/nda_configs/views/nda_configs/`: Turbo Frame (`nda_settings_modal`), Bootstrap 5 modal, two tabs (Settings active, Status disabled placeholder). Settings tab contains the form with all fields.
- [ ] 4.2 Add NDA Settings form partial `_settings_form.html.erb`: Require NDA radio buttons (Yes/No), NDA document file upload with preview, validity type radios with conditional sub-fields (fixed period dropdown, specific date picker), acceptance method radios with descriptions (e-sign disabled if no provider), contact email text input, notification recipients multi-email input. Wire Stimulus controller targets.
- [ ] 4.3 Add "NDA Settings" item to Documents Actions dropdown in `documents/_index.html.erb`: gated by `@folder&.in_data_room?` and `policy(NdaConfig.new(owner: @folder)).new?`, links to edit (if config exists) or new (if not), uses `data: { turbo_frame: "nda_settings_modal" }`. Verify: dev server — item appears for Data Room folders, hidden for Fund folders, hidden for LP users.
- [ ] 4.4 Add lock icon to folder tree in `folders/_tree_view.html.erb`: when `folder.nda_required? && current_user.curr_role_company?`, render `<i class="ti ti-lock text-warning">` with tooltip "NDA required". Ensure `includes(:nda_config)` on the folder query for eager loading. Verify: dev server — lock icon appears after saving NDA config, disappears after disabling, not visible as LP.
- [ ] 4.5 Add Turbo Stream response templates in `app/packs/core/nda_configs/views/nda_configs/`: `create.turbo_stream.erb` and `update.turbo_stream.erb` — replace modal frame + replace folder caret for lock icon + flash message.

## 5. Stimulus controller

- [ ] 5.1 Add `nda_settings_controller.js` in `app/javascript/controllers/`: targets for fields container, fixedPeriod sub-field, specificDate sub-field, fileInfo display. Actions: `toggleEnabled` (show/hide fields based on Yes/No), `toggleValidity` (show/hide sub-fields based on validity type), `fileSelected` (display filename and size). Verify: dev server — toggling form fields works without server round-trip, file selection shows filename.

## 6. Cucumber coverage

- [ ] 6.1 `features/data_room/nda_configuration.feature`: NDA Settings visible in Actions dropdown for Data Room folders; hidden for non-Data Room folders; hidden for LP users; modal opens on click; form toggle hides/shows fields.
- [ ] 6.2 Scenarios: create NDA config with all fields (enabled, PDF upload, validity = fixed period 90 days, click-through, contact email, notification emails); verify record created with correct attributes; lock icon appears in folder tree.
- [ ] 6.3 Scenarios: update existing config (change validity type from until_revoked to specific_date); verify updated_by set; values pre-filled on reopen.
- [ ] 6.4 Scenarios: disable NDA (toggle to No); record retained with enabled=false; lock icon removed; re-enable shows preserved settings.
- [ ] 6.5 Scenarios: validation errors — save without document when enabled; invalid contact email; invalid notification email; past specific date; no validity_days for fixed_period.
- [ ] 6.6 Scenarios: policy denials — LP user denied; GP on non-Data Room folder denied; GP without folder update rights denied.
- [ ] 6.7 Scenarios: `in_data_room?` — true for Data Room root, true for sub-folder, false for Fund folder, false for entity root. `nda_required?` — true when enabled, false when disabled, false when no config.
- [ ] 6.8 Hand full Cucumber command to the user to run; record results.

## 7. Wrap-up

- [ ] 7.1 Verify eager loading: folder tree query uses `includes(:nda_config)` to avoid N+1.
- [ ] 7.2 Verify no Turbo Frame ID collisions with existing modals on the Documents page.
- [ ] 7.3 /code-review gate before marking the module complete.
