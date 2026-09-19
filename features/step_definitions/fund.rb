include CurrencyHelper
include ActionView::Helpers::SanitizeHelper

# Then('{string} has {string} "{string}" access to the fund_ratios') do |arg1,truefalse, accesses|
#   args_temp = arg1.split(";").to_h { |kv| kv.split("=") }
#   @user = if User.exists?(args_temp)
#     User.find_by(args_temp)
#   else
#     FactoryBot.build(:user)
#   end
#   key_values(@user, arg1)
#   @user.save!
#   puts "##### Checking access to fund_ratios for funds with rights #{@fund.access_rights.to_json}"
#   accesses.split(",").each do |access|
#     @fund.fund_ratios.each do |fr|
#       puts "##Checking access #{access} on fund_ratios from #{@fund.name} for #{@user.email} as #{truefalse}"
#       Pundit.policy(@user, fr).send("#{access}?").to_s.should == truefalse
#     end
#   end
# end

# ── Transfer Fund Units: new step definitions ─────────────────────────────────

# Runs a transfer with an arbitrary integer ratio (as stored in the DB, i.e. 0–100 or out-of-range)
# and stores @result for the shared "I should get the error" assertion step.

# Performs a 100 % transfer to drain all units from the from-commitment so the
# next transfer attempt finds nothing to move.

# Verifies that no account entries on either commitment were touched by the transfer.

# Performs a 50 % transfer and excludes the first account entry on the from-commitment
# from pro-rating so we can assert full-copy vs. pro-rated behaviour separately.

# The excluded entry should be copied to the to-commitment at its full original amount,
# and the from-commitment entry should remain unchanged.

# All non-excluded entries should be split by the transfer ratio.

# Verifies that the counter-culture cached totals match the actual sum of fund unit records.

# ── End Transfer Fund Units step definitions ───────────────────────────────────

# Given the distribution is approved

Given('I am at the funds page') do
  visit(funds_url)
end
When('I create a new fund {string}') do |arg1|
  @fund = FactoryBot.build(:fund)
  key_values(@fund, arg1)

  click_on("New Fund")
  fill_in('fund_name', with: @fund.name)
  select(@fund.currency, from: "fund_currency")
  # fill_in('fund_currency', with: @fund.currency)
  fill_in('fund_unit_types', with: @fund.unit_types) if @fund.entity.permissions.enable_units?
  click_on("Next")
  find('trix-editor').click.set(@fund.details)
  click_on("Save")
end
Then('an fund should be created') do
  db_fund = Fund.last
  db_fund.name.should
  @fund.name
  strip_tags(db_fund.details)
  @fund.details

  @fund = db_fund
end
When('I am at the fund details page') do
  visit(fund_url(@fund))
end
Then('I should see the fund details on the details page') do
  find(".show_details_link").click
  expect(page).to have_content(@fund.name)
  @fund.unit_types&.split(",")&.each do |unit_type|
    expect(page).to have_content(unit_type)
  end
  expect(page).to have_content(strip_tags(@fund.details))
end
Then('I should see the fund in all funds page') do
  visit(funds_path)
  expect(page).to have_content(@fund.name)
  # expect(page).to have_content(money_to_currency @fund.collected_amount)
end
Given('there is a fund {string} for the entity') do |arg|
  @fund = FactoryBot.build(:fund, entity_id: @user.entity_id)
  key_values(@fund, arg)
  @fund.save
  puts "\n####Fund####\n"
  puts @fund.to_json
end
Given('there is a feeder fund {string} of the fund') do |name|
  @feeder_fund = FactoryBot.create(:fund, entity_id: @fund.entity_id, name:, currency: @fund.currency, master_fund: @fund)
  puts "\n####Feeder Fund####\n"
  puts @feeder_fund.to_json
end
Given('the investors are added to the fund') do
  @user.entity.investors.each do |inv|
    ar = AccessRight.create(owner: @fund, access_type: "Fund", metadata: "Investor",
                            access_to_investor_id: inv.id, entity: @user.entity)

    puts "\n####Granted Access####\n"
    puts ar.to_json
  end
end
Then('the investors must receive email with subject {string} with the document {string} attached') do |subject, document_name|
  # sleep((2)
  Investor.find_each do |inv|
    next if inv.emails.blank?

    inv.emails.each do |email|
      puts "# checking email #{subject} sent for #{email} for investor #{inv}"
      open_email(email)
      puts "from #{current_email.from}, to #{current_email.to}, subject #{current_email.subject}"
      @custom_notification ||= nil
      if @custom_notification.present?
        expect(current_email.subject).to include @custom_notification.subject
        expect(current_email.body).to include @custom_notification.body
      else
        expect(current_email.subject).to include subject
      end

      @cc_email ||= nil
      if @cc_email
        puts " Checking cc email #{@cc_email} for #{email}"
        expect(current_email.cc).to include @cc_email
      end

      # ✅ Check for attachment
      next if document_name.blank?

      puts "Checking for attachment #{document_name} for #{email}"
      attachment_filenames = current_email.attachments.map(&:filename)
      expect(attachment_filenames.select { |filename| filename.include?(document_name) || filename.downcase.include?(document_name.downcase) }).to be_present, "Expected attachment #{document_name}, but got #{attachment_filenames.inspect}"
    end
  end
end
Given('Given I upload {string} file for {string} of the fund') do |file, tab|
  @import_file = file
  visit(fund_path(@fund))
  click_on(tab)
  # sleep((0.5)
  click_on("Upload / Download") if page.has_button?("Upload / Download")
  click_on("Upload")

  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(8) # JS direct-upload to /upload endpoint; larger window for parallel load
  click_on("Save")
  expect(page).to have_content("Import Upload:", wait: 15)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should
  ImportUpload.last.status.should == "Completed"
end
Then('the fund must have the counter caches updated') do
  @fund.reload
  @fund.collected_amount_cents.should
  CapitalCommitment.sum(:collected_amount_cents)
  @fund.committed_amount_cents.should == CapitalCommitment.sum(:committed_amount_cents)
end
Then('the funds are updated with remittance numbers') do
  Fund.find_each do |f|
    f.reload
    f.call_amount_cents.should
    f.capital_remittances.sum(:call_amount_cents)
    f.collected_amount_cents.should == f.capital_remittances.verified.sum(:collected_amount_cents)
  end
end
Given('my firm is an investor in the fund') do
  @investor = FactoryBot.create(:investor, entity: @fund.entity, investor_entity: @user.entity)
  puts "\n####Fund Investor####\n"
  puts @investor.to_json

  ar = AccessRight.create!(owner: @fund, access_type: "Fund",
                           access_to_investor_id: @investor.id, entity: @fund.entity)

  InvestorAccess.create!(entity: @investor.entity, investor: @investor,
                         first_name: @user.first_name, last_name: @user.last_name,
                         email: @user.email, granter: @user, approved: true)

  puts "\n####Granted Access####\n"
  puts ar.to_json

  @fund.reload
end
Then('I should be able to see my investor kycs') do
  @user.reload

  visible_kycs = []
  invisible_kycs = []
  InvestorKyc.includes(:investor).find_each do |kyc|
    visit(investor_kyc_path(kyc))
    @investor = kyc.investor

    puts "checking kyc for #{@investor.investor_name}"

    if Pundit.policy(@user, kyc).show?
      puts "KYC #{kyc.investor.investor_name} Visible to #{@user.email}"
      expect(page).to have_content(kyc.investor.investor_name)
      expect(page).to have_content(InvestorKyc.kyc_types[kyc.kyc_type])
      expect(page).to have_content(kyc.bank_account_number)
      expect(page).to have_content(kyc.full_name) if kyc.full_name.present?
      visible_kycs << kyc
    else
      puts "KYC #{kyc.investor.investor_name} Not Visible to #{@user.email}"
      expect(page).not_to have_content(@investor.investor_name)
      expect(page).not_to have_content(InvestorKyc.kyc_types[kyc.kyc_type])
      expect(page).not_to have_content(kyc.bank_account_number)
      expect(page).not_to have_content(kyc.full_name) if kyc.full_name.present?
      invisible_kycs << kyc
    end
  end

  puts "Visible KYC: #{visible_kycs.map { |k| k.investor.investor_name }} for User #{@user.email}"
  puts "Invisible KYC: #{invisible_kycs.map { |k| k.investor.investor_name }} for User #{@user.email}"
end
Then('all the investor advisors should be able to receive notifications for the folios they represent') do
  InvestorAdvisor.find_each do |investor_advisor|
    visible_kycs = []
    invisible_kycs = []

    # For each investor access, check if the advisor is notified for each capital commitment
    InvestorAccess.approved.where(email: investor_advisor.email).find_each do |investor_access|
      investor = investor_access.investor
      investor.capital_commitments.each do |cc|
        notif_emails = investor.notification_users(cc).pluck(:email)
        notif_emails.include?(investor_advisor.email).should == true
      end

      investor.capital_remittances.each do |cr|
        investor.notification_users(cr).pluck(:email).include?(investor_advisor.email).should == true
      end

      investor.capital_distribution_payments.each do |cdp|
        investor.notification_users(cdp).pluck(:email).include?(investor_advisor.email).should == true
      end

      investor.investor_kycs.each do |kyc|
        if Pundit.policy(investor_advisor.user, kyc).show?(across_all_entities: true)
          kyc.notification_users.pluck(:email).include?(investor_advisor.email).should == true
          visible_kycs << kyc
        else
          kyc.notification_users.pluck(:email).include?(investor_advisor.email).should == false
          invisible_kycs << kyc
        end
      end
    end

    puts "Visible KYC: #{visible_kycs.map { |k| k.investor.investor_name }} for Investor Advisor #{investor_advisor.email}"
    puts "Invisible KYC: #{invisible_kycs.map { |k| k.investor.investor_name }} for Investor Advisor #{investor_advisor.email}"
  end
end
Then('all the investor advisors should be able to switch to the investors they represent and view their details') do
  InvestorAdvisor.find_each do |investor_advisor|
    puts "Switching to Investor Advisor #{investor_advisor.email} for entity #{investor_advisor.entity.name}"
    investor_advisor.switch(investor_advisor.user)
    investor_advisor.user.reload

    CapitalCommitment.find_each do |cc|
      if Pundit.policy(investor_advisor.user, cc).show?
        # All capital commitments should belong to the investor advisor's entity
        cc.investor.investor_entity_id.should
        investor_advisor.entity.id
        puts "Capital Commitment #{cc.investor.investor_name}, #{cc.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      next unless cc.investor.investor_entity_id != investor_advisor.entity.id

      # If the capital commitment does not belong to the investor advisor's entity, it should not be visible
      Pundit.policy(investor_advisor.user, cc).show?.should
      puts "Capital Commitment #{cc.investor.investor_name}, #{cc.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
    end

    CapitalRemittance.find_each do |cr|
      if Pundit.policy(investor_advisor.user, cr).show?
        # All capital remittances should belong to the investor advisor's entity
        cr.investor.investor_entity_id.should
        investor_advisor.entity.id
        puts "Capital Remittance #{cr.investor.investor_name}, #{cr.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      next unless cr.investor.investor_entity_id != investor_advisor.entity.id

      # If the capital remittance does not belong to the investor advisor's entity, it should not be visible
      Pundit.policy(investor_advisor.user, cr).show?.should
      puts "Capital Remittance #{cr.investor.investor_name}, #{cr.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
    end

    CapitalDistributionPayment.find_each do |cdp|
      if Pundit.policy(investor_advisor.user, cdp).show?
        # All capital distribution payments should belong to the investor advisor's entity
        cdp.investor.investor_entity_id.should
        investor_advisor.entity.id
        puts "Capital Distribution Payment #{cdp.investor.investor_name}, #{cdp.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      next unless cdp.investor.investor_entity_id != investor_advisor.entity.id

      # If the capital distribution payment does not belong to the investor advisor's entity, it should not be visible
      Pundit.policy(investor_advisor.user, cdp).show?.should
      puts "Capital Distribution Payment #{cdp.investor.investor_name}, #{cdp.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
    end

    InvestorKyc.find_each do |kyc|
      if Pundit.policy(investor_advisor.user, kyc).show?(across_all_entities: false)
        # All investor KYC should belong to the investor advisor's entity
        kyc.investor.investor_entity_id.should
        investor_advisor.entity.id
        puts "Investor KYC #{kyc.investor.investor_name}, #{kyc.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      next unless kyc.investor.investor_entity_id != investor_advisor.entity.id

      # If the investor KYC does not belong to the investor advisor's entity, it should not be visible
      Pundit.policy(investor_advisor.user, kyc).show?(across_all_entities: false).should
      puts "Investor KYC #{kyc.investor.investor_name}, #{kyc.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
    end
  end
end
Then('the user goes to the fund e-signature report') do
  @template_dup = @commitment_template.dup
  @template_dup.assign_attributes(sent_for_esign: true, owner: @fund.capital_commitments.last)
  @template_dup.save!
  ESignature.create!(user: @user, entity: @fund.entity, document: @template_dup, status: "failed")
  visit(fund_path(@fund))
  click_on("Reports")
  sleep(0.5)
  find("#basic_reports").hover
  sleep(0.5)
  click_on("eSignatures Report")
  # sleep((2)
end
Then('the user should see all esign report for all docs sent for esign') do
  esign = ESignature.last
  doc = esign.document
  expect(page).to have_content(doc.name)
  expect(page).to have_content(doc.owner_tag)
end
When('the fund document details must be setup right') do
  @fund.data_room_folder.name.should
  @fund.data_room_folder.owner.should

  @document.owner.should
  @document.folder.name.should
  @document.folder.full_path.should == "/Funds/#{@fund.name}/Data Room"
end
When('I visit the fund details page') do
  visit(fund_path(@fund))
end
When('I click on fund documents tab') do
  # sleep((1)
  find("#documents_tab").click
end
Then('when the exchange rate changes') do
  foreign_currencies = @fund.capital_commitments.joins(:fund).where("folio_currency != funds.currency").pluck(:folio_currency).uniq
  foreign_currencies.each do |fc|
    # Change the exchange rate for the foreign_currencies randomly
    exchange_rate = ExchangeRate.where(from: fc, to: @fund.currency, latest: true).last.dup
    exchange_rate.rate += (rand(10) - rand(10) + 0.1)
    exchange_rate.save
  end
end
Given('the last investor has a user {string}') do |args|
  cr = CapitalRemittance.first
  investor = cr.investor
  user = FactoryBot.create(:user, entity: investor.investor_entity, whatsapp_enabled: true)
  user1 = FactoryBot.create(:user, entity: investor.investor_entity)
  # A dialable number, not "321" — User#phone_must_be_dialable rejects the latter on
  # create. The digits are arbitrary; only that there is a third user matters here.
  FactoryBot.create(:user, entity: investor.investor_entity, phone: "9000000321")

  key_values(user, args)
  user.save!

  [user, user1].each do |u|
    user.add_role :investor_advisor
    AccessRight.create(entity_id: investor.investor_entity_id, owner: @fund, access_to_investor_id: investor.id, metadata: "Investor", user_id: u.id)
    ia = InvestorAccess.create(entity: investor.entity, investor: investor,
                               first_name: u.first_name, last_name: u.last_name,
                               email: u.email, granter: u, approved: true)
    ia.update_columns(approved: true)
  end
end
Then('the imported data must have the form_type updated') do
  @import_upload = ImportUpload.last
  @import_upload.imported_data.find_each do |row|
    form_type = @import_upload.entity.form_types.where(name: row.class.name).first
    next if form_type.blank?

    puts "Checking form_type for #{row.class.name}"
    row.form_type_id.should
    form_type.id
    form_type.form_custom_fields.each do |fcf|
      # Ensure that the data json fields are exactly the same as the form custom fields name
      puts "Checking #{fcf.name} in imported data #{row.custom_fields[fcf.name]}"
      row.custom_fields[fcf.name].should_not be_nil
    end
  end
end
Then('I should get the error {string}') do |message|
  if message.present? && message != "nil"
    @result.success?.should
    @result[:error].should == message
  else
    @result.success?.should == true
  end
end
Given('I upload fund documents {string}') do |zip|
  @import_file = zip
  visit(fund_path(@fund))
  click_on("Import")
  # sleep((2)
  click_on("Import Documents")
  # sleep((2)
  fill_in('import_upload_name', with: "Commitments and Distribution Docs Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  # sleep((2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep((4)
end
Given('Given import file {string} for {string}') do |file, type|
  # Some types require form types to be present before import
  if ["InvestorKyc"].include?(type)
    FormType.where(entity: @entity, name: "IndividualKyc", tag: "Default").first_or_create!
    FormType.where(entity: @entity, name: "NonIndividualKyc", tag: "Default").first_or_create!
  elsif FormType::MULTIPLE_FORM_TYPES_ALLOWED.include?(type)
    FormType.where(entity: @entity, name: type, tag: "Default").first_or_create!
  end

  @import_file = file
  owner = @fund || @entity
  iu = ImportUpload.create!(entity: @entity, owner:, import_type: type, name: "Import #{type}", user_id: @user.id, import_file: File.open(File.absolute_path("./public/sample_uploads/#{file}")))
  ImportUploadJob.perform_now(iu.id)
  iu.reload
  # binding.pry if iu.failed_row_count > 0
  iu.failed_row_count.should == 0
end
# Same as the step above, but for imports where we expect row failures (eg fail fast tests), so no assertion on failed_row_count
Given('Given import file {string} for {string} expecting failures') do |file, type|
  @import_file = file
  owner = @fund || @entity
  @import_upload = ImportUpload.create!(entity: @entity, owner:, import_type: type, name: "Import #{type}", user_id: @user.id, import_file: File.open(File.absolute_path("./public/sample_uploads/#{file}")))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
end
Then('the import upload should be stopped with {string} processed and {string} failed rows') do |processed, failed|
  @import_upload.processed_row_count.should == processed.to_i
  @import_upload.failed_row_count.should == failed.to_i
  # The fail fast status message must be preserved, not overwritten with Completed
  @import_upload.status.should include("stopped")
end
Given('the fund snapshot is created') do
  # Need to ensure that the fund has the entity permission to enable snapshots
  es = @fund.entity
  es.permissions.set(:enable_snapshots)
  es.save
  # Create the fund snapshot
  FundSnapshotJob.perform_now(fund_id: @fund.id)
  puts "Checking fund snapshot for #{@fund.id}"
  Fund.with_snapshots.where(orignal_id: @fund.id).count.should
  fs = Fund.with_snapshots.where(orignal_id: @fund.id, snapshot: true).first
  fs.should_not
  nil
  fs.snapshot_date.should
  Time.zone.today

  @fund.aggregate_portfolio_investments.each do |api|
    AggregatePortfolioInvestment.with_snapshots.where(orignal_id: api.id).count.should == 2
    puts "Checking aggregate portfolio investment snapshot for #{api.id}"
    api_s = AggregatePortfolioInvestment.with_snapshots.where(orignal_id: api.id, snapshot: true).first
    api_s.should_not be_nil
    api_s.snapshot_date.should == Time.zone.today

    api.portfolio_investments.each do |pi|
      PortfolioInvestment.with_snapshots.where(orignal_id: pi.id).count.should == 2
      puts "Checking portfolio investment snapshot for #{pi.id}"
      pi_s = PortfolioInvestment.with_snapshots.where(orignal_id: pi.id, snapshot: true).first
      pi_s.should_not be_nil
      pi_s.snapshot_date.should == Time.zone.today
    end
  end
end
Given('I log in as the first user') do
  @user = User.first
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end
Given('the dashboard widgets must have the data in the sheet') do
  file = File.open("./public/sample_uploads/dashboard_widgets.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h

    widget = DashboardWidget.where(dashboard_name: row_data["Dashboard Name"].strip, widget_name: row_data["Widget Name"].strip, tags: row_data["Tags"].strip).first
    binding.pry if widget.nil?
    puts "Checking import of #{widget.widget_name} in dashboard #{widget.dashboard_name} at position #{widget.position}"

    widget.dashboard_name.should
    row_data["Dashboard Name"].strip
    widget.widget_name.should
    row_data["Widget Name"].strip
    # widget.position.should == row_data["Position"].to_i
    widget.tags.should
    row_data["Tags"].strip
    widget.metadata.should == row_data["Metadata"].strip.delete("\t") if row_data["Metadata"].present?
    widget.size.should
    row_data["Size"]
    widget.enabled.should
    row_data["Enabled"].to_s.strip.downcase
    widget.display_name.should
    row_data["Display Name"]
    widget.display_tag.should
    row_data["Display Tag"]
    widget.name.should
    row_data["Name"]
    widget.show_menu.should == (row_data["Show Menu"].to_s.strip.downcase == "true")
  end
end
Given('I update the fund custom fields {string}') do |custom_fields|
  @fund ||= @capital_call.fund
  custom_fields.split(",").each do |cf|
    k, v = cf.split(":").map(&:strip)
    @fund.json_fields[k] = v
  end
  @fund.save!
end
Given('I go to fund page') do
  @fund ||= Fund.last
  visit(fund_url(@fund))
end
Given('I go to fund page with debug mode enabled') do
  @fund ||= Fund.last
  visit(fund_url(@fund, debug: true))
end

# ── Fund Commitment Adhoc Notification steps ─────────────────────────────────

# Creates a fund-level CustomNotification wired to the adhoc_fund_notification mailer method
Given('there is an adhoc custom notification for the fund with subject {string}') do |subject|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    enabled: true
  )
end

# "<div><br></div>" is what the Trix editor saves when left empty - a non-empty string, so it
# passes CustomNotification's body presence validation, but sanitizes down to nothing. This is
# the email-side equivalent of the blank whatsapp field: NotificationExtensions#custom_notification_body_present?
# should stop the :email deliver_by from ever enqueuing, rather than falling back to some default body.
Given('there is an adhoc custom notification for the fund with a blank body and subject {string}') do |subject|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: "<div><br></div>",
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    enabled: true
  )
end

# Body uses {{placeholder}} tokens resolved per-commitment by CapitalCommitmentMailer::PLACEHOLDERS
Given('there is an adhoc custom notification for the fund with placeholders and subject {string}') do |subject|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: "Dear {{investor_name}}, your commitment to {{fund_name}} of {{committed_amount}} is confirmed. Unsupported: {{not_a_real_placeholder}}.",
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    enabled: true
  )
end

# KYC-mode counterpart to the placeholder step above — body uses {{investor_name}}, {{fund_name}},
# {{kyc_full_name}} tokens, resolved by FundInvestorKycMailer::PLACEHOLDERS instead of
# CapitalCommitmentMailer::PLACEHOLDERS.
Given('there is an adhoc kyc custom notification for the fund with placeholders and subject {string}') do |subject|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: "Dear {{investor_name}}, thank you for completing KYC with {{fund_name}}. Recorded name: {{kyc_full_name}}. Unsupported: {{not_a_real_placeholder}}.",
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_kyc_notification",
    enabled: true
  )
end

# Same but with attachment_names so the mailer picks up docs from each commitment
Given('there is an adhoc custom notification for the fund with subject {string} and attachment_names {string}') do |subject, attachment_names|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    attachment_names: attachment_names.presence,
    enabled: true
  )
end

# Same but with an explicit latest_doc_only, so a scenario can verify multiplicity independent of pattern type
Given('there is an adhoc custom notification for the fund with subject {string} and attachment_names {string} and latest_doc_only {string}') do |subject, attachment_names, latest_doc_only|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    attachment_names: attachment_names.presence,
    latest_doc_only: latest_doc_only == "true",
    enabled: true
  )
end

# Same but with an explicit show_details_link, so a scenario can verify the "View Commitment"
# link on the shared adhoc_notification template (rendered by adhoc_fund_notification) is gated by this flag
Given('there is an adhoc custom notification for the fund with subject {string} and show_details_link {string}') do |subject, show_details_link|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    show_details_link: show_details_link == "true",
    enabled: true
  )
end

# "notify_via" here is the Gherkin-readable name for what's actually just a different
# email_method value: "investor_kyc" -> "adhoc_kyc_notification" (FundInvestorKycMailer),
# anything else -> "adhoc_fund_notification" (CapitalCommitmentMailer). There is no
# separate notify_via field/column — this step just picks which mailer/iteration path runs.
Given('there is an adhoc custom notification for the fund with subject {string} and attachment_names {string} and notify_via {string}') do |subject, attachment_names, notify_via|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: notify_via == "investor_kyc" ? "adhoc_kyc_notification" : "adhoc_fund_notification",
    attachment_names: attachment_names.presence,
    enabled: true
  )
end

# Same but with an explicit show_details_link instead of attachment_names, so a scenario can
# verify the "View KYC" link on the shared adhoc_notification template (rendered by
# adhoc_kyc_notification) in investor_kyc mode
Given('there is an adhoc custom notification for the fund with subject {string} and notify_via {string} and show_details_link {string}') do |subject, notify_via, show_details_link|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: notify_via == "investor_kyc" ? "adhoc_kyc_notification" : "adhoc_fund_notification",
    show_details_link: show_details_link == "true",
    enabled: true
  )
end

# Same but with password_protect_attachment/attachment_password and no attachment_names — used
# together with "the custom notification has document ... " above, so a scenario can verify
# ApplicationMailer#pw_protect_attach_file also runs on @custom_notification.documents (the
# directly-linked branch, distinct from the attachment_names-resolved one)
Given('there is an adhoc custom notification for the fund with subject {string} and password_protect_attachment {string} and attachment_password {string}') do |subject, password_protect_attachment, attachment_password|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    password_protect_attachment: password_protect_attachment == "true",
    attachment_password: attachment_password.presence,
    enabled: true
  )
end

# Same but with password_protect_attachment/attachment_password, so a scenario can verify
# ApplicationMailer#pw_protect_attach_file actually runs pdftk on attachment_names-resolved docs
Given('there is an adhoc custom notification for the fund with subject {string} and attachment_names {string} and password_protect_attachment {string} and attachment_password {string}') do |subject, attachment_names, password_protect_attachment, attachment_password|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    attachment_names: attachment_names.presence,
    password_protect_attachment: password_protect_attachment == "true",
    attachment_password: attachment_password.presence,
    enabled: true
  )
end

# Same but with an explicit attachment_mandatory, so a scenario can verify a recipient
# missing a required document is skipped instead of receiving the email without it —
# see ApplicationMailer#missing_mandatory_attachment_names / #record_notification_skip.
Given('there is an adhoc custom notification for the fund with subject {string} and attachment_names {string} and attachment_mandatory {string}') do |subject, attachment_names, attachment_mandatory|
  @custom_notification = CustomNotification.create!(
    entity: @fund.entity,
    owner: @fund,
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: Faker::Lorem.sentence,
    email_method: "adhoc_fund_notification",
    attachment_names: attachment_names.presence,
    attachment_mandatory: attachment_mandatory == "true",
    enabled: true
  )
end

# Links the fund's first two capital commitments (regardless of investor) to a single,
# freshly-created InvestorKyc — mirrors the existing "The multiple commitments have the
# same investor kycs linked" step (features/step_definitions/capital_commitment.rb:323),
# but scoped to exactly the first two commitments so scenarios have a deterministic,
# named handle (@shared_investor_kyc) to assert against afterwards.
Given('the first two commitments share the same investor kyc') do
  first_two = @fund.capital_commitments.order(:id).limit(2)
  investor = first_two.first.investor
  kyc = InvestorKyc.new(
    investor: investor, entity: @fund.entity, verified: true,
    completed_by_investor: true, submission_status: "verified", full_name: investor.investor_name
  )
  # InvestorKyc has many required fields (kyc_type, bank details, etc.) unrelated to what
  # this scenario is testing — save(validate: false) is the existing precedent for building
  # a minimal KYC fixture (see capital_commitment.rb's own investor-kyc-linking steps).
  kyc.save(validate: false)
  @shared_investor_kyc = kyc
  first_two.each { |cc| cc.update!(investor_kyc_id: kyc.id) }
end

# Gives the shared kyc's two commitments distinct cc overrides — proves
# FundInvestorKycNotifier#email_data combines every linked commitment's cc rather than
# picking just one (an investor can hold multiple commitments to the same fund sharing
# one KYC, each with its own cc).
And('the first two commitments have ccs {string} and {string}') do |cc1, cc2|
  first_two = @fund.capital_commitments.order(:id).limit(2).to_a
  [[first_two.first, cc1], [first_two.second, cc2]].each do |cc, email|
    cc.properties[:cc] = email
    cc.save
  end
end

# Overrides the shared investor kyc's full_name, which the step above sets equal to
# investor_name by default — placeholder scenarios need the two distinct so a passing
# assertion can't be coincidence of {{kyc_full_name}} and {{investor_name}} matching.
And('the shared investor kyc has full name {string}') do |full_name|
  @shared_investor_kyc.update_column(:full_name, full_name)
end

# Uploads a real file as a document directly on the shared InvestorKyc (via WithFolder's
# documents association) so an "adhoc_kyc_notification" notification's attachment_names can
# find it — analogous to "the first commitment has document ..." but for the KYC-mode owner.
And('the shared investor kyc has document {string} with file {string}') do |doc_name, file_name|
  create_investor_kyc_document(@shared_investor_kyc, doc_name, file_name)
end

# Same, but for @investor_kyc (set by "a InvestorKyc is created with details ...") — used by
# the Entity-level notify_kyc_required / kyc_required_reminder preview scenarios.
And('the investor kyc has document {string} with file {string}') do |doc_name, file_name|
  create_investor_kyc_document(@investor_kyc, doc_name, file_name)
end

def create_investor_kyc_document(investor_kyc, doc_name, file_name)
  Document.create!(
    entity: investor_kyc.entity,
    name: doc_name,
    owner: investor_kyc,
    folder: investor_kyc.document_folder,
    user: @user,
    file: File.new("public/sample_uploads/#{file_name}", "r")
  )
end

# Links the first commitment to a freshly-created InvestorKyc with a known PAN, so a
# CustomNotification's attachment_password (e.g. "investor_kyc.PAN") resolves to a real,
# assertable value via document.owner (the commitment) -> investor_kyc -> PAN.
And('the first commitment has an investor kyc with PAN {string}') do |pan|
  cc = @fund.capital_commitments.order(:id).first
  investor = cc.investor
  kyc = InvestorKyc.new(
    investor: investor, entity: @fund.entity, verified: true,
    completed_by_investor: true, submission_status: "verified", full_name: investor.investor_name,
    PAN: pan
  )
  # save(validate: false) mirrors "the first two commitments share the same investor kyc" above —
  # InvestorKyc has many required fields unrelated to what this scenario is testing.
  kyc.save(validate: false)
  cc.update!(investor_kyc_id: kyc.id)
end

# Links the first commitment to a freshly-created InvestorKyc with a distinct full_name/folio_id,
# so DocumentMailer's kyc_full_name/folio_id/committed_amount placeholders (which fall back to
# document.capital_commitment.investor_kyc when a document is owned by the commitment rather
# than the KYC directly) resolve to real, assertable values.
And('the first commitment has an investor kyc with full_name {string} and folio_id {string}') do |full_name, folio_id|
  @capital_commitment = @fund.capital_commitments.order(:id).first
  kyc = InvestorKyc.new(
    investor: @capital_commitment.investor, entity: @fund.entity, verified: true,
    completed_by_investor: true, submission_status: "verified", full_name: full_name
  )
  kyc.save(validate: false)
  @capital_commitment.update!(investor_kyc_id: kyc.id, folio_id: folio_id)
end

# Uploads a real file directly on the CustomNotification itself (its own WithFolder :documents
# association, distinct from attachment_names-resolved docs) — exercises the
# @custom_notification.documents.each branch of ApplicationMailer#attach_custom_notification_documents
And('the custom notification has document {string} with file {string}') do |doc_name, file_name|
  Document.create!(
    entity: @custom_notification.entity,
    name: doc_name,
    owner: @custom_notification,
    folder: @custom_notification.document_folder,
    user: @user,
    file: File.new("public/sample_uploads/#{file_name}", "r")
  )
end

# Uploads a real file as a document on the first commitment so attachment_names can find it
And('the first commitment has document {string} with file {string}') do |doc_name, file_name|
  cc = @fund.capital_commitments.order(:id).first
  Document.create!(
    entity: cc.entity,
    name: doc_name,
    owner: cc,
    folder: cc.document_folder,
    user: @user,
    file: File.new("public/sample_uploads/#{file_name}", "r")
  )
end

# Same as "the first commitment has document ..." but marks the document as generated
# (owner_tag: "Generated") and approved — proves an approved generated document still attaches
# normally, unlike its unapproved counterpart below. See Document#exclude_generated_unapproved.
And('the first commitment has a generated document {string} with file {string} that is approved') do |doc_name, file_name|
  cc = @fund.capital_commitments.order(:id).first
  Document.create!(
    entity: cc.entity,
    name: doc_name,
    owner: cc,
    folder: cc.document_folder,
    user: @user,
    owner_tag: "Generated",
    approved: true,
    file: File.new("public/sample_uploads/#{file_name}", "r")
  )
end

# Same as above but on the second commitment and left unapproved — proves
# documents_matching_attachment_name treats a generated-but-unapproved document as absent, so
# it can trigger missing_mandatory_attachment_names exactly like a genuinely missing document.
And('the second commitment has a generated document {string} with file {string} that is not approved') do |doc_name, file_name|
  cc = @fund.capital_commitments.order(:id).second
  Document.create!(
    entity: cc.entity,
    name: doc_name,
    owner: cc,
    folder: cc.document_folder,
    user: @user,
    owner_tag: "Generated",
    approved: false,
    file: File.new("public/sample_uploads/#{file_name}", "r")
  )
end

# Same as above but backdates created_at, so a scenario can deterministically control which of
# several matching documents is "the newest" (latest_doc_only picks by created_at desc)
And('the first commitment has document {string} with file {string} created {int} days ago') do |doc_name, file_name, days|
  cc = @fund.capital_commitments.order(:id).first
  doc = Document.create!(
    entity: cc.entity,
    name: doc_name,
    owner: cc,
    folder: cc.document_folder,
    user: @user,
    file: File.new("public/sample_uploads/#{file_name}", "r")
  )
  doc.update_column(:created_at, days.to_i.days.ago)
end

# Asserts each commitment investor's email has exactly `count` attachments — used to verify
# latest_doc_only=false attaches every matching document instead of just the newest
And('the notification email has {int} documents attached') do |count|
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      filenames = current_email.attachments.map(&:filename)
      puts "## Attachments for #{user.email}: #{filenames.inspect}"
      expect(filenames.size).to eq(count), "Expected #{count} attachment(s) but got #{filenames.inspect}"
    end
  end
end

# Negative counterpart to "the notification email has the document {string} attached" — used to
# prove latest_doc_only=true excludes older matches, not just that the newer one happens to match
And('the notification email does not have the document {string} attached') do |doc_name|
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      filenames = current_email.attachments.map(&:filename)
      puts "## Attachments for #{user.email}: #{filenames.inspect}"
      expect(filenames.any? { |f| f.include?(doc_name) }).to be(false),
                                                              "Expected no attachment containing '#{doc_name}' but got #{filenames.inspect}"
    end
  end
end

# Trigger with no commitment_ids → nil → FundNotificationJob sends to all commitments
When('the adhoc notification is triggered for all commitments') do
  @fund.adhoc_notification(@custom_notification.id)
end

# Trigger with only the first commitment's id
When('the adhoc notification is triggered for the first commitment only') do
  first_cc = @fund.capital_commitments.order(:id).first
  @fund.adhoc_notification(@custom_notification.id, commitment_ids: [first_cc.id])
end

# Same as "for all commitments" but threads @user (the company_admin created via "there is a
# user ...") through as triggered_by_user_id — proves SkippedNotificationReportJob emails this
# specific admin instead of falling back to the entity's company admins.
When('the adhoc notification is triggered by the admin for all commitments') do
  @fund.adhoc_notification(@custom_notification.id, triggered_by_user_id: @user.id)
end

# Runs the report inline, scoped to the scenario's @custom_notification — mirrors how
# ApplicationMailer#record_notification_skip schedules it for real (Cucumber's :inline ActiveJob
# adapter already runs every enqueued job synchronously, so this just invokes the job directly
# like any other step) — see SkippedNotificationReportJob.
When('the skipped notification report runs') do
  SkippedNotificationReportJob.new.perform(@custom_notification.id)
end

# Trigger with no investor_kyc_ids → nil → FundNotificationJob (for an "adhoc_kyc_notification"
# email_method) sends to every unique investor_kyc linked to the fund
When('the adhoc notification is triggered for all investor kycs') do
  @fund.adhoc_notification(@custom_notification.id)
end

# Trigger with just the shared investor_kyc's id — proves the picker's selection also dedupes
When('the adhoc notification is triggered for the shared investor kyc only') do
  @fund.adhoc_notification(@custom_notification.id, investor_kyc_ids: [@shared_investor_kyc.id])
end

# Every commitment's notification_users should have received the email
Then('all commitment investors receive the notification email') do
  @fund.capital_commitments.each do |cc|
    recipients = cc.investor.notification_users(cc)
    puts "## Commitment #{cc} — #{recipients.count} recipient(s)"
    expect(recipients).not_to be_empty, "notification_users is empty for commitment #{cc} — check InvestorAccess / AccessRight setup"
    recipients.each do |user|
      open_email(user.email)
      puts "## Checking email for #{user.email}: #{current_email&.subject.inspect}"
      expect(current_email).not_to be_nil, "No email delivered to #{user.email}"
      expect(current_email.subject).to include @custom_notification.subject
    end
  end
end

# Every commitment's notification_users should have received the email, cc'd to the
# commitment-level cc address (proves FundCommitmentNotifier#email_data forwards
# CapitalCommitment#cc via additional_ccs, not just entity_setting.cc/InvestorAccess#cc).
Then('all commitment investors receive the notification email cc\'d to {string}') do |cc_email|
  @fund.capital_commitments.each do |cc|
    recipients = cc.investor.notification_users(cc)
    expect(recipients).not_to be_empty, "notification_users is empty for commitment #{cc}"
    recipients.each do |user|
      open_email(user.email)
      expect(current_email).not_to be_nil, "No email delivered to #{user.email}"
      expect(current_email.cc).to include(cc_email),
                                  "Expected cc #{cc_email} on email to #{user.email}, got #{current_email.cc.inspect}"
    end
  end
end

# Only the first commitment's users should have received the email
Then('only the first commitment investor receives the notification email') do
  first_cc = @fund.capital_commitments.order(:id).first
  recipients = first_cc.investor.notification_users(first_cc)
  puts "## First commitment #{first_cc} — #{recipients.count} recipient(s)"
  expect(recipients).not_to be_empty, "notification_users is empty for first commitment #{first_cc}"
  recipients.each do |user|
    open_email(user.email)
    puts "## Checking email for #{user.email}: #{current_email&.subject.inspect}"
    expect(current_email).not_to be_nil, "No email delivered to #{user.email}"
    expect(current_email.subject).to include @custom_notification.subject
  end
end

# The second commitment's users must NOT have received any email
And('the second commitment investor does not receive a notification email') do
  second_cc = @fund.capital_commitments.order(:id).second
  second_cc.investor.notification_users(second_cc).each do |user|
    open_email(user.email)
    puts "## Checking no email for #{user.email}: #{current_email&.subject.inspect}"
    expect(current_email).to be_nil, "Unexpected email '#{current_email&.subject}' delivered to #{user.email}"
  end
end

# Proves ApplicationMailer#record_notification_skip actually marked the Noticed::Notification
# for the second commitment's recipient(s), rather than just silently dropping the send.
And('the second commitment investor\'s notification is recorded as skipped with a reason mentioning {string}') do |doc_name|
  second_cc = @fund.capital_commitments.order(:id).second
  second_cc.investor.notification_users(second_cc).each do |user|
    notification = Noticed::Notification.where(recipient: user).where.not(skip_reason: nil).order(created_at: :desc).first
    expect(notification).not_to be_nil, "No skipped Notification found for #{user.email}"
    expect(notification.skip_reason).to include(doc_name)
  end
end

# Unlike the missing-attachment scenarios above (where only one commitment is affected), a
# blank body applies to every recipient of the custom notification - so this checks all of them.
Then('no commitment investor receives a notification email') do
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      expect(current_email).to be_nil, "Unexpected email '#{current_email&.subject}' delivered to #{user.email}"
    end
  end
end

# Proves SkippedNotificationReportJob emailed the triggering admin (@user, set via
# "the adhoc notification is triggered by the admin for all commitments") a summary
# naming the skipped investor and the missing document, with a working link back into the
# app pre-filtered to the skipped notifications (SkippedNotificationReportJob#skipped_notifications_url,
# which relies on Noticed::Notification's skip_reason ransackable_attribute — config/initializers/noticed.rb).
Then('the triggering admin receives a skipped notification report mentioning {string}') do |doc_name|
  open_email(@user.email)
  expect(current_email).not_to be_nil, "No skipped-notification report delivered to #{@user.email}"
  expect(current_email.body.to_s).to include(doc_name)
  expect(current_email.body.to_s).to include("skip_reason_not_null")
end

# Fallback counterpart — no triggered_by_user_id was set, so the report should go to every
# company_admin of the fund's entity instead (here, just @user, who has that role).
Then('the entity\'s company admins receive a skipped notification report mentioning {string}') do |doc_name|
  open_email(@user.email)
  expect(current_email).not_to be_nil, "No skipped-notification report delivered to company admin #{@user.email}"
  expect(current_email.body.to_s).to include(doc_name)
  expect(current_email.body.to_s).to include("skip_reason_not_null")
end

# The email to each commitment investor should have the named document attached
And('the notification email has the document {string} attached') do |doc_name|
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      filenames = current_email.attachments.map(&:filename)
      puts "## Attachments for #{user.email}: #{filenames.inspect}"
      expect(filenames.any? { |f| f.include?(doc_name) }).to be(true),
                                                             "Expected attachment containing '#{doc_name}' but got #{filenames.inspect}"
    end
  end
end

# Decodes the named attachment's actual bytes and opens it with the expected password via
# HexaPDF (already a Gemfile dependency) — proves pdftk actually encrypted it with THIS
# password, not just that some encryption dictionary is present.
And('the notification email attachment {string} is password protected with password {string}') do |doc_name, password|
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      attachment = current_email.attachments.find { |a| a.filename.include?(doc_name) }
      expect(attachment).not_to be_nil, "No attachment containing '#{doc_name}' found"
      Tempfile.create(["attachment", ".pdf"]) do |tmp|
        tmp.binmode
        tmp.write(attachment.decoded)
        tmp.flush
        doc = HexaPDF::Document.open(tmp.path, decryption_opts: { password: password })
        expect(doc.encrypted?).to be(true), "Expected '#{doc_name}' to be password protected but it wasn't"
      end
    end
  end
end

# Negative counterpart — proves the flag being off (or unset) leaves the original,
# unencrypted PDF bytes untouched.
And('the notification email attachment {string} is not password protected') do |doc_name|
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      attachment = current_email.attachments.find { |a| a.filename.include?(doc_name) }
      expect(attachment).not_to be_nil, "No attachment containing '#{doc_name}' found"
      Tempfile.create(["attachment", ".pdf"]) do |tmp|
        tmp.binmode
        tmp.write(attachment.decoded)
        tmp.flush
        expect(HexaPDF::Document.open(tmp.path).encrypted?).to be(false),
                                                                 "Expected '#{doc_name}' to NOT be password protected but it was"
      end
    end
  end
end

# Proves ApplicationMailer#adhoc_notification_link (overridden in CapitalCommitmentMailer)
# renders a "View Commitment" link, gated by CustomNotification#show_details_link
And('the notification email contains a link to view the commitment') do
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      expect(current_email).not_to be_nil
      body = current_email.body.to_s
      expect(body).to include("View Commitment")
      expect(body).to include(capital_commitment_path(cc))
    end
  end
end

And('the notification email does not contain a link to view the commitment') do
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      expect(current_email).not_to be_nil
      expect(current_email.body.to_s).not_to include("View Commitment")
    end
  end
end

# KYC-mode counterpart — proves FundInvestorKycMailer's own adhoc_notification_link override
And('the investor kyc notification email contains a link to view the kyc') do
  investor = @shared_investor_kyc.investor
  investor.notification_users(@shared_investor_kyc).each do |user|
    open_email(user.email)
    expect(current_email).not_to be_nil
    body = current_email.body.to_s
    expect(body).to include("View KYC")
    expect(body).to include(investor_kyc_path(@shared_investor_kyc))
  end
end

# Proves the dedup: two commitments share @shared_investor_kyc, but its investor should
# receive exactly one email with this subject — not two (one per commitment, the old behavior).
Then('exactly one notification email is sent for the shared investor kyc') do
  investor = @shared_investor_kyc.investor
  recipients = investor.notification_users(@shared_investor_kyc)
  expect(recipients).not_to be_empty, "notification_users is empty for shared investor kyc #{@shared_investor_kyc.id}"
  recipients.each do |user|
    matching = ActionMailer::Base.deliveries.select { |m| m.to.include?(user.email) && m.subject.include?(@custom_notification.subject) }
    puts "## Matching deliveries for #{user.email}: #{matching.size}"
    expect(matching.size).to eq(1), "Expected exactly 1 email to #{user.email} with subject '#{@custom_notification.subject}' but got #{matching.size}"
  end
end

# KYC-mode counterpart to "all commitment investors receive the notification email cc'd
# to {string}" — proves FundInvestorKycNotifier#email_data forwards the shared kyc's
# commitment-level cc via additional_ccs.
And('the investor kyc notification email is cc\'d to {string}') do |cc_email|
  investor = @shared_investor_kyc.investor
  investor.notification_users(@shared_investor_kyc).each do |user|
    open_email(user.email)
    expect(current_email).not_to be_nil, "No email delivered to #{user.email}"
    expect(current_email.cc).to include(cc_email),
                                "Expected cc #{cc_email} on email to #{user.email}, got #{current_email.cc.inspect}"
  end
end

# KYC-mode counterpart to "the notification email has the document {string} attached" —
# checks the shared investor kyc's recipient(s) instead of iterating every commitment.
And('the investor kyc notification email has the document {string} attached') do |doc_name|
  investor = @shared_investor_kyc.investor
  investor.notification_users(@shared_investor_kyc).each do |user|
    open_email(user.email)
    filenames = current_email.attachments.map(&:filename)
    puts "## Attachments for #{user.email}: #{filenames.inspect}"
    expect(filenames.any? { |f| f.include?(doc_name) }).to be(true),
                                                           "Expected attachment containing '#{doc_name}' but got #{filenames.inspect}"
  end
end

When('I open the actions menu on the first capital commitment') do
  first_cc = @fund.capital_commitments.order(:id).first
  visit(capital_commitment_path(first_cc))
  find("#commitment_actions").click
end

Then('I see a preview adhoc notification button') do
  expect(page).to have_css("[id^='capital_commitment_preview_adhoc_notification_']")
end

Then('I see {int} preview adhoc notification buttons') do |count|
  expect(page).to have_css("[id^='capital_commitment_preview_adhoc_notification_']", count: count)
end

Then('I do not see a preview adhoc notification button') do
  expect(page).not_to have_css("[id^='capital_commitment_preview_adhoc_notification_']")
end

When('I click the preview adhoc notification button for {string}') do |label|
  click_on("Preview Adhoc Fund Notification (#{label})")
end

Then('I see the adhoc notification preview with subject {string}') do |subject|
  expect(page).to have_content(subject)
end

Then('I see {string} listed as an attachment in the preview') do |doc_name|
  expect(page).to have_css("h6", text: "Attachments:")
  expect(page).to have_content(doc_name)
end

# Placeholder substitution is verified per-commitment against CapitalCommitmentMailer::PLACEHOLDERS:
#   investor_name, fund_name, committed_amount, kyc_full_name, folio_id
#   + base placeholders: user_full_name, user_first_name, user_last_name, user_email, entity_name
Then('the adhoc notification placeholders are resolved correctly') do
  @fund.capital_commitments.each do |cc|
    cc.investor.notification_users(cc).each do |user|
      open_email(user.email)
      expect(current_email).not_to be_nil

      body = current_email.body.to_s

      # Known CapitalCommitmentMailer placeholders are resolved (token text gone)
      expect(body).to include(cc.investor.name)
      expect(body).not_to include("{{investor_name}}")

      expect(body).to include(@fund.name)
      expect(body).not_to include("{{fund_name}}")

      expect(body).to include(cc.committed_amount.format)
      expect(body).not_to include("{{committed_amount}}")

      expect(body).to include(cc.investor_kyc&.full_name || "")
      expect(body).not_to include("{{kyc_full_name}}")

      # Unknown placeholder is preserved as-is (catches typos)
      expect(body).to include("{{not_a_real_placeholder}}")
    end
  end
  clear_emails
end

# KYC-mode counterpart to "the adhoc notification placeholders are resolved correctly" —
# verifies FundInvestorKycMailer::PLACEHOLDERS: investor_name, fund_name, kyc_full_name
# + base placeholders, against the shared investor kyc's single recipient(s).
Then('the investor kyc notification placeholders are resolved correctly') do
  investor = @shared_investor_kyc.investor
  investor.notification_users(@shared_investor_kyc).each do |user|
    open_email(user.email)
    expect(current_email).not_to be_nil

    body = current_email.body.to_s

    expect(body).to include(@shared_investor_kyc.investor_name)
    expect(body).not_to include("{{investor_name}}")

    expect(body).to include(@fund.name)
    expect(body).not_to include("{{fund_name}}")

    expect(body).to include(@shared_investor_kyc.full_name)
    expect(body).not_to include("{{kyc_full_name}}")

    # Unknown placeholder is preserved as-is (catches typos)
    expect(body).to include("{{not_a_real_placeholder}}")
  end
  clear_emails
end

# ── End Fund Commitment Adhoc Notification steps ──────────────────────────────
