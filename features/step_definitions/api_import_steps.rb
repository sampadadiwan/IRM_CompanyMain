# frozen_string_literal: true

# Steps for features/api/import_pipeline.feature — the Orios onboarding-trial fixes (funds-json-api-hardening
# phase 8, P1–P10). Requests and shared setup come from api_json_steps.rb.
# openspec/changes/funds-json-api-hardening/design.md#worked-examples — the H/E/X IDs in the feature.

# Builds an xlsx from a Cucumber table (first row = headers) and imports it exactly as an upload does:
# ImportUpload.create! then ImportUploadJob.perform_now (the model does not enqueue in test).
def api_import(import_type, owner, table)
  tmp = Tempfile.new(["api_import", ".xlsx"])
  Axlsx::Package.new do |p|
    # {placeholders} in cells are filled like request bodies ({first_investor}, {fund}, ...)
    p.workbook.add_worksheet(name: import_type) { |ws| table.raw.each { |row| ws.add_row(row.map { |c| c.presence && api_fill(c) }) } }
    p.serialize(tmp.path)
  end
  @import_upload = ImportUpload.create!(entity: @entity, owner:, import_type:, name: "#{import_type} import",
                                        user_id: @user.id, import_file: File.open(tmp.path))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
  api_ids[:import_upload] = @import_upload.id
ensure
  tmp&.close
  tmp&.unlink
end

When("I import {string} rows into my fund:") do |import_type, table|
  api_import(import_type, @fund, table)
end

When("I import {string} rows into my firm:") do |import_type, table|
  api_import(import_type, @entity, table)
end

# H22 — the Sidekiq thread left on another locale must not change how text dates are read
When("I import {string} rows into my fund on a thread left in locale {string}:") do |import_type, locale, table|
  previous = I18n.locale
  I18n.locale = locale.to_sym
  api_import(import_type, @fund, table)
ensure
  I18n.locale = previous
end

# E26 — the number of failed rows kept on the upload, made small
Given("an upload keeps at most {int} row errors") do |count|
  stub_const("ImportUtil::ROW_ERRORS_KEPT", count)
end

Then("the capital call {string} has call date {string}") do |name, date|
  expect(CapitalCall.find_by!(name:).call_date).to eq(Date.iso8601(date))
end

Then("the import of {int} row(s) processed {int} and failed {int}") do |total, processed, failed|
  expect([@import_upload.total_rows_count, @import_upload.processed_row_count, @import_upload.failed_row_count])
    .to eq([total, processed, failed]), "status: #{@import_upload.status} errors: #{@import_upload.row_errors}"
end

Then("the import's status is {string}") do |status|
  expect(@import_upload.status).to eq(status)
end

Then("the import's status starts with {string}") do |text|
  expect(@import_upload.status.to_s).to start_with(text)
end

Given("my fund has a running import upload") do
  api_ids[:import_upload] = api_insert_import_upload(entity: @entity, fund: @fund, user: @user, status: nil,
                                                     total_rows_count: 10, processed_row_count: 3)
end

# P7 — exactly the CapitalCommitment form types a scenario names (comma-separated tags)
Given("my firm has CapitalCommitment form types tagged {string}") do |tags|
  FormType.where(entity_id: @entity.id, name: "CapitalCommitment").find_each(&:destroy)
  tags.split(",").map(&:strip).each { |tag| FormType.create!(entity: @entity, name: "CapitalCommitment", tag:) }
end

Then("a commitment with folio {string} exists in my fund") do |folio_id|
  expect(@fund.capital_commitments.where(folio_id:)).to exist
end

# E28 — every importer's save_row takes the four arguments ImportUtil#process_row passes
Then("every importer's save_row accepts the four arguments process_row passes") do
  Rails.application.eager_load!
  wrong = ImportUtil.descendants.filter_map do |klass|
    next unless klass.method_defined?(:save_row) || klass.private_method_defined?(:save_row)

    params = klass.instance_method(:save_row).parameters
    takes_four = params.any? { |type, _| type == :rest } || params.count { |type, _| %i[req opt].include?(type) } >= 4
    required = params.count { |type, _| type == :req }
    "#{klass}#save_row #{params.inspect}" unless takes_four && required <= 4
  end
  expect(wrong).to be_empty, wrong.join("\n")
end

Then("my firm has exactly one settings row with sandbox on") do
  rows = EntitySetting.unscoped.where(entity_id: @entity.id)
  expect(rows.count).to eq(1)
  expect(rows.first.sandbox).to be(true)
end

Then("the API answer at {string} is my firm's settings row id") do |path|
  expect(api_dig(path)).to eq(EntitySetting.find_by!(entity_id: @entity.id).id)
end

# H25 — a duplicate made the way the bug made it; the unique index is lifted for the setup only
Given("my firm has a duplicate settings row from before the fix") do
  conn = ActiveRecord::Base.connection
  index = "index_entity_settings_on_entity_id_unique"
  conn.remove_index(:entity_settings, name: index) if conn.index_exists?(:entity_settings, :entity_id, name: index)
  @kept_setting = @entity.reload.entity_setting || @entity.create_entity_setting!
  @extra_setting_id = EntitySetting.insert!({ entity_id: @entity.id, sandbox: true, created_at: Time.current, updated_at: Time.current },
                                            returning: :id).rows.first.first
end

When("support runs the settings dedupe with EXECUTE=1") do
  Rails.application.load_tasks unless Rake::Task.task_defined?("entities:dedupe_settings")
  ENV["EXECUTE"] = "1"
  Rake::Task["entities:dedupe_settings"].reenable
  Rake::Task["entities:dedupe_settings"].invoke
ensure
  ENV.delete("EXECUTE")
end

Then("only the settings row the app was reading remains, and the unique index is back") do
  expect(EntitySetting.unscoped.where(entity_id: @entity.id).pluck(:id)).to eq([@kept_setting.id])
  expect(ActiveRecord::Base.connection.index_exists?(:entity_settings, :entity_id, name: "index_entity_settings_on_entity_id_unique")).to be(true)
end

# P6 — every remittance of the call has a payment in full, not yet verified
Given("every remittance of the call is paid in full but unverified") do
  # A remittance can only be verified once its call is approved (the trial approved each call first)
  @capital_call.update_column(:approved, true)
  @capital_call.capital_remittances.find_each do |remittance|
    payment = CapitalRemittancePayment.new(capital_remittance: remittance, fund: @fund, entity: @entity,
                                           folio_amount: remittance.folio_call_amount.to_f, payment_date: Time.zone.today)
    expect(CapitalRemittancePaymentCreate.call(capital_remittance_payment: payment)).to be_success
    # Unverified — the state before anyone verifies
    remittance.reload.update_column(:verified, false)
  end
  # Rollups recomputed to match the unverified remittances
  CapitalRemittancesCountersJob.perform_now([@fund.id])
end

# The rollups equal the sums of what they roll up (collected counts only verified remittances)
Then("the fund, call and commitment collected totals equal their verified remittances") do
  verified = CapitalRemittance.where(fund_id: @fund.id, verified: true)
  expect(@fund.reload.collected_amount_cents.to_d).to eq(verified.sum(:collected_amount_cents).to_d)
  expect(@capital_call.reload.collected_amount_cents.to_d).to eq(verified.where(capital_call_id: @capital_call.id).sum(:collected_amount_cents).to_d)
  @fund.capital_commitments.each do |commitment|
    expect(commitment.reload.collected_amount_cents.to_d).to eq(verified.where(capital_commitment_id: commitment.id).sum(:collected_amount_cents).to_d)
  end
end

Then("every remittance of the call is verified") do
  stuck = @capital_call.capital_remittances.where(verified: false).to_a
  # On failure, say why: what a direct verify of the first stuck remittance answers
  why = stuck.first && CapitalRemittanceVerify.call(capital_remittance: stuck.first).then { |r| [r.success?, r[:errors]] }
  expect(stuck).to be_empty, "unverified: #{stuck.map(&:id)} direct verify → #{why.inspect}"
end

Given("the fund's collected total has drifted") do
  @fund.update_column(:collected_amount_cents, 12_345_600)
end

Given("my firm's {string} feature flag starts off") do |flag|
  @entity.permissions.unset(flag.to_sym)
  @entity.save!
end

Then("my firm's {string} feature flag is {word}") do |flag, state|
  expect(@entity.reload.permissions.set?(flag.to_sym)).to be(state == "on")
end

# E33 — every row imported, with the warning status the payment import sets
Given("my fund has an import upload that imported every row with the status {string}") do |status|
  api_ids[:import_upload] = api_insert_import_upload(entity: @entity, fund: @fund, user: @user, status:,
                                                     total_rows_count: 515, processed_row_count: 515, failed_row_count: 0)
end

# X33 — the distribution made by "there is a capital distribution payment for the fund"
Given("I remember that distribution") do
  @remembered_distribution = @record.capital_distribution
  api_ids[:distribution] = @remembered_distribution.id
end

Then("the distribution still belongs to my fund and firm") do
  distribution = @remembered_distribution.reload
  expect([distribution.fund_id, distribution.entity_id]).to eq([@fund.id, @entity.id])
end

Then("my capital call still belongs to my firm") do
  expect(CapitalCall.find(api_ids[:call]).entity_id).to eq(@entity.id)
end
