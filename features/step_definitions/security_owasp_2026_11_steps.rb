# Step definitions for features/security/owasp_review_2026_11.feature — the Critical and High fixes of the
# OWASP Top 10 review (docs/security/owasp_top10_review_2026_11.md), each with the production-shaped values next
# to it that must keep working.
#
# Reused from elsewhere: "there is a user … for an entity …" (features/common.rb), "there is a fund … for the
# entity" (fund.rb), "the log filter hides / keeps the values of:" (security_auth_b_steps.rb).
#
# Everything here runs in-process against models, policies and services; nothing renders a browser page.

# The ENV values a step changes, restored after the scenario
After do
  (@owasp_saved_env || {}).each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  FileUtils.rm_rf(@owasp_tmp_root) if @owasp_tmp_root
end

# Sets ENV[key] for this scenario only (the After hook above restores it)
def owasp_set_env(key, value)
  @owasp_saved_env ||= {}
  @owasp_saved_env[key] = ENV.fetch(key, nil) unless @owasp_saved_env.key?(key)
  ENV[key] = value
end

##############################################################################
# C1 — formula denylist
##############################################################################

# C1-1 — every listed formula is refused by ApplicationRecord.safe_eval! (it never evaluates anything)
Then("the OWASP formula guard refuses:") do |table|
  table.hashes.each do |row|
    expect { ApplicationRecord.safe_eval!(row["formula"], context: "owasp C1") }
      .to raise_error(ApplicationRecord::UnsafeEvalError), "#{row['formula']} was not refused"
  end
end

# C1-H — every listed formula passes safe_eval! unchanged
Then("the OWASP formula guard accepts:") do |table|
  table.hashes.each do |row|
    expect(ApplicationRecord.safe_eval!(row["formula"], context: "owasp C1")).to eq(row["formula"])
  end
end

##############################################################################
# C2 — Calculation fields named by id
##############################################################################

# A form type for the entity with one Calculation field and one ordinary text field. Saved without validation:
# the Calculation field's own validations (support-only, sandbox) are not what these scenarios test
Given("the entity has an {string} form type with a Calculation field {string}") do |name, field_name|
  @owasp_form_type = FormType.create!(name:, entity: @entity, tag: "OWASP")
  @owasp_calc_field = @owasp_form_type.form_custom_fields.build(name: field_name, field_type: "Calculation",
                                                                meta_data: "investor_name.to_s")
  @owasp_calc_field.save!(validate: false)
  @owasp_text_field = @owasp_form_type.form_custom_fields.build(name: "nickname", field_type: "TextField")
  @owasp_text_field.save!(validate: false)
end

# C2-1 — the id of the stored Calculation field, with new meta_data and no field_type (as a crafted PATCH sends)
Then("a non-support user may not submit the Calculation field by id without its type") do
  fields = [{ "id" => @owasp_calc_field.id.to_s, "meta_data" => "Rails.application.credentials" }]
  expect(@user.support?).to be(false)
  # As in production: the rule lets every user through in development and test (Rails.env.local?)
  allow(Rails.env).to receive(:local?).and_return(false)
  expect(FormType.calculation_change_allowed?(@user, fields, @owasp_form_type)).to be(false)
end

# C2-H — the fields the editor actually renders for a non-support user: never the Calculation one
Then("a non-support user may submit the form type's other fields") do
  allow(Rails.env).to receive(:local?).and_return(false)
  fields = [{ "id" => @owasp_text_field.id.to_s, "field_type" => "TextField", "label" => "Nick name" },
            { "name" => "new_field", "field_type" => "TextField" }]
  expect(FormType.calculation_change_allowed?(@user, fields, @owasp_form_type)).to be(true)
end

# C2-H — support (here a user with the support role) may change it
Then("a support user may submit the Calculation field by id") do
  @user.add_role(:support)
  fields = [{ "id" => @owasp_calc_field.id.to_s, "meta_data" => "investor_name.to_s.upcase" }]
  expect(FormType.calculation_change_allowed?(@user.reload, fields, @owasp_form_type)).to be(true)
end

##############################################################################
# C3 / H8 — import file names and zip symlinks
##############################################################################

# An unzipped-upload folder under tmp/ with the given files, a secret file next to (outside) it, and a symlink in
# it to that secret file
Given("an OWASP import upload folder with files {string} and a symlink {string} to a file outside it") do |files, link|
  @owasp_tmp_root = Rails.root.join("tmp", "owasp_c3_#{SecureRandom.hex(4)}").to_s
  @owasp_dir = File.join(@owasp_tmp_root, "unzip")
  FileUtils.mkdir_p(@owasp_dir)
  files.split(",").map(&:strip).each do |name|
    path = File.join(@owasp_dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "content of #{name}")
  end
  # The file an attacker wants: one level above the upload folder
  File.write(File.join(@owasp_tmp_root, "secret.txt"), "secret")
  File.symlink(File.join(@owasp_tmp_root, "secret.txt"), File.join(@owasp_dir, link))
end

Given("the OWASP upload folder also has a symlink {string} to {string}") do |link, target|
  File.symlink(File.join(@owasp_dir, target), File.join(@owasp_dir, link))
end

# An import operation instance, for calling its instance helpers without running the operation
def owasp_import_util
  ImportKycDocs.allocate
end

# C3-1 — find_case_insensitive_file (the importers' entry point) returns nil for each name
Then("the import file path for these names is refused:") do |table|
  table.hashes.each do |row|
    expect(owasp_import_util.send(:find_case_insensitive_file, @owasp_dir, row["name"])).to be_nil, "#{row['name']} was not refused"
  end
end

# C3-H — each name resolves to a path inside the folder; "exists" says whether that file is there
Then("the import file path for these names stays inside the folder:") do |table|
  base = File.realpath(@owasp_dir)
  table.hashes.each do |row|
    path = owasp_import_util.send(:find_case_insensitive_file, @owasp_dir, row["name"])
    expect(path).not_to be_nil, "#{row['name']} was refused"
    expect(File.expand_path(path)).to start_with(base + File::SEPARATOR)
    expect(File.exist?(path)).to eq(row["exists"] == "yes"), "#{row['name']}: exists? was #{File.exist?(path)}"
  end
end

When("the import removes escaping symlinks from the folder") do
  ImportServiceBase.allocate.send(:remove_escaping_symlinks, @owasp_dir)
end

Then("the OWASP upload folder has no {string}") do |name|
  expect(File.symlink?(File.join(@owasp_dir, name)) || File.exist?(File.join(@owasp_dir, name))).to be(false)
end

Then("the OWASP upload folder still has {string} and {string}") do |first, second|
  [first, second].each { |name| expect(File.exist?(File.join(@owasp_dir, name))).to be(true), "#{name} is gone" }
end

##############################################################################
# C4 / C5 — stored attribute paths
##############################################################################

Then("these attribute paths are refused:") do |table|
  table.hashes.each { |row| expect(SafeAttributePath.valid?(row["path"])).to be(false), "#{row['path']} was allowed" }
end

Then("these attribute paths are allowed:") do |table|
  table.hashes.each { |row| expect(SafeAttributePath.valid?(row["path"])).to be(true), "#{row['path']} was refused" }
end

# Investors of the entity, each with its own investor entity (the factory's pattern elsewhere)
Given("there are {int} OWASP investors for the entity") do |count|
  @owasp_investors = Array.new(count) do |i|
    FactoryBot.create(:investor, entity: @entity, investor_name: "OWASP Investor #{i + 1}",
                                 investor_entity: FactoryBot.create(:entity, entity_type: "Investor"))
  end
end

Given("another firm has {int} OWASP investor(s)") do |count|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "OWASP Other Firm")
  count.times do |i|
    FactoryBot.create(:investor, entity: other, investor_name: "OWASP Other Investor #{i + 1}",
                                 investor_entity: FactoryBot.create(:entity, entity_type: "Investor"))
  end
end

Given("the first OWASP investor has custom fields {string}") do |pairs|
  fields = pairs.split(";").to_h { |pair| pair.split("=", 2) }
  @owasp_investors.first.update_column(:json_fields, fields)
end

# C4-2 — exactly what RansackTableRow does for a non-custom_fields key
When("the grid cell {string} is read for the first OWASP investor") do |key|
  @owasp_cell = SafeAttributePath.read(@owasp_investors.first, key, context: "grid column")
end

Then("the grid cell value is blank") do
  expect(@owasp_cell).to be_nil
end

Then("there are still {int} OWASP investors for the entity") do |count|
  expect(Investor.where(entity_id: @entity.id).count).to eq(count)
end

Then("the grid cell {string} for the first OWASP investor reads {string}") do |key, value|
  expect(SafeAttributePath.read(Investor.find(@owasp_investors.first.id), key).to_s).to eq(value)
end

Then("the grid cell {string} for the first OWASP investor reads its name") do |key|
  expect(SafeAttributePath.read(@owasp_investors.first, key)).to eq(@owasp_investors.first.investor_name)
end

# C4-4 — only the key's own validation is asserted (the model's other rules are not what this tests)
def owasp_grid_column(key)
  GridViewPreference.new(owner: @owasp_form_type, entity_id: @entity.id, key:, name: key, label: key)
end

Then("a grid column with key {string} cannot be saved for the form type") do |key|
  pref = owasp_grid_column(key)
  pref.valid?
  expect(pref.errors[:key]).not_to be_empty
end

Then("a grid column with key {string} can be saved for the form type") do |key|
  pref = owasp_grid_column(key)
  pref.valid?
  expect(pref.errors[:key]).to be_empty, pref.errors.full_messages.join(", ")
end

# C5-1 — only the attachment_password validation is asserted
def owasp_custom_notification(path)
  CustomNotification.new(entity_id: @entity.id, subject: "Notice", body: "Body", password_protect_attachment: true,
                         attachment_password: path)
end

Then("a custom notification with PDF password field {string} cannot be saved") do |path|
  notification = owasp_custom_notification(path)
  notification.valid?
  expect(notification.errors[:attachment_password]).not_to be_empty
end

Then("a custom notification with PDF password field {string} can be saved") do |path|
  notification = owasp_custom_notification(path)
  notification.valid?
  expect(notification.errors[:attachment_password]).to be_empty, notification.errors.full_messages.join(", ")
end

##############################################################################
# H1 — no secret keys in browser JavaScript
##############################################################################

Then("no file under {string} contains an OpenAI secret key") do |dir|
  offenders = Rails.root.glob("#{dir}/**/*.js").select { |f| File.read(f, mode: "rb").match?(/\bsk-(proj-)?[A-Za-z0-9_-]{20,}/) }
  expect(offenders).to be_empty, "secret key found in: #{offenders.join(', ')}"
end

##############################################################################
# H3 — sub_domain in sign-in links
##############################################################################

Then("the entity cannot change its sub_domain to:") do |table|
  table.hashes.each do |row|
    entity = Entity.find(@entity.id)
    expect(entity.update(sub_domain: row["sub_domain"])).to be(false), "#{row['sub_domain']} was accepted"
    expect(entity.errors[:sub_domain]).not_to be_empty
  end
end

Then("the entity can change its sub_domain to:") do |table|
  table.hashes.each do |row|
    entity = Entity.find(@entity.id)
    expect(entity.update(sub_domain: row["sub_domain"])).to be(true), entity.errors.full_messages.join(", ")
    expect(entity.safe_sub_domain).to eq(row["sub_domain"])
  end
end

# As the 395 production investor entities whose generated sub_domain predates the rule
Given("the entity's sub_domain was stored as {string} before the rule") do |value|
  @entity.update_column(:sub_domain, value)
end

Then("the entity can still save a new name {string}") do |name|
  entity = Entity.find(@entity.id)
  expect(entity.update(name:)).to be(true), entity.errors.full_messages.join(", ")
end

Then("the entity's safe sub_domain is blank") do
  expect(Entity.find(@entity.id).safe_sub_domain).to be_nil
end

##############################################################################
# H4 — PDF renderer asset host
##############################################################################

Given("the deployment host is {string} with base domain {string}") do |host, base|
  owasp_set_env("HOST", host)
  owasp_set_env("BASE_DOMAIN", base)
end

# pdf_host_trusted? is the decision; trusted_pdf_host also trusts every host in development and test
Then("the PDF asset host check gives:") do |table|
  table.hashes.each do |row|
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create("HTTP_HOST" => row["host"])
    expect(controller.send(:pdf_host_trusted?, row["host"])).to eq(row["trusted"] == "yes"), row["host"]
  end
end

##############################################################################
# H5 — KPI name in SQL
##############################################################################

Given("the entity has a KPI form type with a field {string} whose meta data is {string}") do |name, meta|
  @owasp_kpi_form_type = FormType.create!(name: "KpiReport", entity: @entity, tag: "OWASP")
  @owasp_kpi_form_type.form_custom_fields.build(name:, field_type: "TextField", meta_data: meta).save!(validate: false)
end

# custom_form_field reads kpi_report.form_type; an unsaved report pointing at the form type is enough
def owasp_kpi(name)
  Kpi.new(name:, entity_id: @entity.id, kpi_report: KpiReport.new(entity_id: @entity.id, form_type: @owasp_kpi_form_type))
end

Then("the KPI named {string} uses a {string} custom field") do |name, field_type|
  field = owasp_kpi(name).custom_form_field
  expect(field).not_to be_persisted
  expect(field.field_type).to eq(field_type)
end

Then("the KPI named {string} uses the {string} custom field") do |name, field_name|
  expect(owasp_kpi(name).custom_form_field.name).to eq(field_name)
end

##############################################################################
# H6 — document template merge fields
##############################################################################

# The merge field evaluated exactly as Sablon does, with "investor" in the context
def owasp_template_field(expression)
  Sablon::Expression.parse(expression).evaluate({ "investor" => @owasp_investors.first })
end

Then("the template field {string} renders blank") do |expression|
  expect(owasp_template_field(expression)).to be_nil
end

Then("the template field {string} renders {string}") do |expression, value|
  expect(owasp_template_field(expression).to_s).to eq(value)
end

Then("the template field {string} renders the investor's name") do |expression|
  expect(owasp_template_field(expression)).to eq(@owasp_investors.first.investor_name)
end

##############################################################################
# H7 — fund formula imports
##############################################################################

def owasp_import_policy(user, import_type, persisted: false)
  upload = ImportUpload.new(owner: @fund, entity_id: @fund.entity_id, import_type:, user_id: user.id)
  upload.id = 1 if persisted # update? and destroy? are asked of saved uploads
  ImportUploadPolicy.new(user, upload)
end

# The usual import rule (enable_import_uploads + rights on the fund) is not what H7 changes, so it is taken as met
# here; the scenario isolates the support-only rule on top of it
Then("a {string} upload to the fund is refused for the user although other uploads would be allowed") do |type|
  allow_any_instance_of(ImportUploadPolicy).to receive(:upload_allowed?).and_return(true)
  policy = owasp_import_policy(@user, type)
  expect(@user.support?).to be(false)
  expect(policy.create?).to be(false)
end

Then("a {string} upload to the fund follows the usual import rule for the user") do |type|
  policy = owasp_import_policy(@user, type)
  expect(policy.create?).to eq(policy.upload_allowed?)
end

Then("an existing {string} upload to the fund can still be edited under the usual import rule") do |type|
  policy = owasp_import_policy(@user, type, persisted: true)
  expect(policy.update?).to eq(policy.upload_allowed?)
  expect(policy.destroy?).to eq(policy.upload_allowed?)
end

Then("a {string} upload to the fund follows the usual import rule for a support user") do |type|
  @user.add_role(:support)
  support = User.find(@user.id)
  policy = owasp_import_policy(support, type)
  expect(support.support?).to be(true)
  expect(policy.create?).to eq(policy.upload_allowed?)
end

##############################################################################
# N1 — Calculation fields through the custom field import
##############################################################################

# An unsaved upload is enough: the guard reads only uploaded_by_support? (support_user_id and the user's roles)
Given("a custom field import of the form type uploaded by the user") do
  @owasp_import_upload = ImportUpload.new(owner: @owasp_form_type, entity_id: @entity.id, user: @user,
                                          import_type: "FormCustomField")
end

When("the custom field import was uploaded by support signed in as the user") do
  support = FactoryBot.create(:user, entity: @entity)
  support.add_role(:support)
  @owasp_import_upload.support_user_id = support.id
end

# One table row → the import's row hash and the field it updates ("calc" / "text" name the scenario's stored
# fields, blank is a new field), then the guard exactly as save_row runs it, as in production (not local)
def owasp_custom_field_row_guard(row)
  allow(Rails.env).to receive(:local?).and_return(false)
  field = { "calc" => @owasp_calc_field, "text" => @owasp_text_field }[row["id"]] || FormCustomField.new
  data = { "Id" => field.id&.to_s, "Name" => row["name"], "Field Type" => row["field_type"], "Metadata" => row["metadata"].presence }
  ImportFormCustomField.allocate.send(:guard_calculation_change!, field, data, @owasp_import_upload)
end

Then("these custom field import rows are refused:") do |table|
  table.hashes.each do |row|
    expect { owasp_custom_field_row_guard(row) }.to raise_error(/only be added or changed by CapHive support/), row.inspect
  end
end

Then("these custom field import rows are accepted:") do |table|
  table.hashes.each { |row| expect { owasp_custom_field_row_guard(row) }.not_to raise_error, row.inspect }
end

# The controller's strong parameters, applied to a posted value
Then("the import upload form does not accept {string}") do |attribute|
  params = ActionController::Parameters.new(import_upload: { attribute => "1", name: "x" })
  controller = ImportUploadsController.new
  controller.params = params
  expect(controller.send(:import_upload_params).keys).not_to include(attribute)
end
