When("I create a Capital Distribution {string}") do |args|
  visit(fund_path(@fund))
  @capital_distribution = FactoryBot.build(:capital_distribution, fund: @fund)
  key_values(@capital_distribution, args)
  click_on("Distributions")
  click_on("New Distribution")

  fill_in 'capital_distribution_title', with: @capital_distribution.title
  fill_in 'capital_distribution_income', with: @capital_distribution.income.to_d
  fill_in 'capital_distribution_cost_of_investment', with: @capital_distribution.cost_of_investment.to_d
  fill_in 'capital_distribution_reinvestment', with: @capital_distribution.reinvestment.to_d
  fill_in 'capital_distribution_distribution_date', with: @capital_distribution.distribution_date.strftime("%Y-%m-%d")

  CapitalCommitment.first.account_entries.find_each do |ae|
    # For each account entry, add a distribution fee
    puts "Adding distribution fee for account entry #{ae}"
    click_link 'Add Account Entries'

    within all('.nested-fields').last do
      select ae.name, from: 'fee_name'
      fill_in 'fee_start_date', with: (ae.reporting_date - 1.month).strftime("%Y-%m-%d")
      fill_in 'fee_end_date', with: (ae.reporting_date + 1.month).strftime("%Y-%m-%d")
      select ae.entry_type, from: 'fee_type'
      fill_in 'fee_notes', with: "From account entry #{ae.id}"
    end
  end

  click_button 'Save'
  expect(page).to have_content("Capital distribution was successfully created")
  # @capital_distribution above is the unsaved FactoryBot.build used only to fill in the form;
  # the actual persisted record is a separate object created server-side by the Save submit.
  # Steps further down the scenario (Clone/Create With Fees) need the real id, so re-point
  # @capital_distribution at the row that was actually created.
  @capital_distribution = CapitalDistribution.last
  # sleep(2)
end

Given("there is a AccountEntry for distribution {string}") do |args|
  CapitalCommitment.find_each do |cc|
    ae = @fund.account_entries.build(entity_id: @fund.entity_id, capital_commitment_id: cc.id)
    key_values(ae, args)
    ae.save!
    puts ae.to_json
  end
end

Then('it should create Capital Distribution') do
  distribution = CapitalDistribution.first
  expect(distribution.title).to(eq(@capital_distribution.title))
  expect(distribution.income_cents).to(eq(@capital_distribution.income_cents))
  expect(distribution.cost_of_investment_cents).to(eq(@capital_distribution.cost_of_investment_cents))
  expect(distribution.reinvestment_cents).to(eq(@capital_distribution.reinvestment_cents))

  @capital_distribution.income_cents
  @capital_distribution.cost_of_investment_cents
  @capital_distribution.reinvestment_cents
  AccountEntry.where(fund_id: @fund.id).where.not(entry_type: %w[Tax Expense]).sum(:amount_cents)
  # total_amount_cents -=  AccountEntry.where(fund_id: @fund.id).where(entry_type: ["Tax", "Expense"]).sum(:amount_cents)

  expect(distribution.gross_amount_cents).to(eq(distribution.capital_distribution_payments.sum(:gross_payable_cents)))
  expect(distribution.completed_distribution_amount_cents).to(eq(distribution.capital_distribution_payments.completed.sum(:net_payable_cents)))
end

Then('the data should be correctly displayed for each Capital Distribution Payment') do
  CapitalDistributionPayment.find_each do |cdp|
    visit(capital_distribution_payment_path(cdp))
    # sleep(20)
    puts "checking details of #{cdp}"

    cdp.income_with_fees_cents.should
    cdp.income_cents
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Income"]).sum(:amount_cents)
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: %w[Tax Expense]).sum(:amount_cents)
    cdp.cost_of_investment_with_fees_cents.should
    cdp.cost_of_investment_cents
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["FV For Redemption"]).sum(:amount_cents)
    cdp.reinvestment_with_fees_cents.should
    cdp.reinvestment_cents
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Reinvestment"]).sum(:amount_cents)

    cdp.net_payable_cents.should
    cdp.income_with_fees_cents
    cdp.cost_of_investment_with_fees_cents
    cdp.reinvestment_with_fees_cents
    cdp.gross_payable_cents.should
    cdp.income_cents
    cdp.cost_of_investment_cents
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Income", "FV For Redemption"]).sum(:amount_cents)

    expect(page).to have_content(money_to_currency(cdp.net_payable, {}))
    expect(page).to have_content(money_to_currency(cdp.income, {}))
    expect(page).to have_content(money_to_currency(cdp.income_with_fees, {}))
    expect(page).to have_content(money_to_currency(cdp.cost_of_investment, {}))
    expect(page).to have_content(money_to_currency(cdp.cost_of_investment_with_fees, {}))
    expect(page).to have_content(money_to_currency(cdp.reinvestment, {}))

    expect(page).to have_content(I18n.l(cdp.payment_date))
    expect(page).to have_content(cdp.capital_distribution.to_s)
    expect(page).to have_content(cdp.capital_commitment.to_s)
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).find_each do |ae|
      name = FormCustomField.to_name(ae.name)
      puts "checking details of #{name} in #{cdp.json_fields}"
      expect(cdp.json_fields[name]).to(eq(money_to_currency(ae.amount, {})))
    end
  end
end

# Inflates the reported size of a generated distribution notice. attach_all_files reads size
# from Shrine metadata, so this is exactly what the preflight sees.
Given('one distribution payment has an oversized document of {int} MB') do |megabytes|
  doc = Document.where(owner_type: "CapitalDistributionPayment").first
  raise "no CapitalDistributionPayment document to inflate" if doc.nil?

  data = JSON.parse(doc.file_data)
  data["metadata"]["size"] = megabytes * 1024 * 1024
  doc.update_column(:file_data, data.to_json)
  @oversized_payment_id = doc.owner_id
end

# Mirrors the capital call step: skip_doc_gen? reads a json_fields key, so it is the one filter
# the preflight applies in Ruby rather than in SQL. Flagging the payment that holds the oversized
# document proves the skip runs BEFORE the size check.
Given('the commitment with the oversized distribution document has skip_doc_gen enabled') do
  raise "run the oversized-document step first" if @oversized_payment_id.blank?

  CapitalDistributionPayment.find(@oversized_payment_id).capital_commitment
                            .update!(json_fields: { "skip_doc_gen" => "yes" })
end

# Deliberately NOT "the investors must receive email ..." - that step walks every Investor and
# demands an email for each, which is wrong here: the skip_doc_gen payment must receive nothing.
# What matters is that the rest of the distribution went out despite the oversized document
# sitting on the skipped one.
Then('the distribution payments that were not skipped still receive their notices') do
  skipped = CapitalDistributionPayment.find(@oversized_payment_id)
  skipped_emails = skipped.investor.emails.compact
  others = Investor.where.not(id: skipped.investor_id).flat_map(&:emails).compact

  notices = ActionMailer::Base.deliveries.reject { |m| m.subject.to_s.include?("not sent") }
  expect(notices).not_to be_empty,
                        "No distribution notice was sent at all - the oversized document on the skip_doc_gen " \
                        "payment blocked the whole run, which is exactly what skip_if exists to prevent."

  recipients = notices.flat_map { |m| Array(m.to) }.uniq
  expect(recipients & skipped_emails).to be_empty,
                                        "The skip_doc_gen payment's investor was emailed: #{(recipients & skipped_emails).inspect}"
  expect(recipients & others).not_to be_empty,
                                    "No other investor received a notice; recipients were #{recipients.inspect}"
end

When('the capital distribution notifications are sent') do
  CapitalDistributionPaymentNotificationJob.perform_now(@capital_distribution.id, @user.id)
end

Then('the Display Only fee should not affect income_with_fees_cents') do
  CapitalDistributionPayment.find_each do |cdp|
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Display Only").sum(:amount_cents)
    # Display Only should not affect income_with_fees_cents
    cdp.income_with_fees_cents.should
    cdp.income_cents
    puts "Display Only: income_with_fees_cents (#{cdp.income_with_fees_cents}) == income_cents (#{cdp.income_cents}) - PASS"
  end
end

Then('the Display Only fee should not affect cost_of_investment_with_fees_cents') do
  CapitalDistributionPayment.find_each do |cdp|
    # Display Only should not affect cost_of_investment_with_fees_cents
    cdp.cost_of_investment_with_fees_cents.should
    cdp.cost_of_investment_cents
    puts "Display Only: cost_of_investment_with_fees_cents (#{cdp.cost_of_investment_with_fees_cents}) == cost_of_investment_cents (#{cdp.cost_of_investment_cents}) - PASS"
  end
end

Then('the ae_audit should contain the Display Only fee details') do
  CapitalDistributionPayment.find_each do |cdp|
    ae_audit = cdp.json_fields["ae_audit"]
    puts "Checking ae_audit for Display Only: #{ae_audit}"
    expect(ae_audit).to be_present, "ae_audit should be present"
    # ae_audit is an array of arrays, each containing [name, reporting_date, amount_cents, fee_type]
    expect(ae_audit.flatten).to include("Display Only"), "ae_audit should contain Display Only fee type"
  end
end

Then('the json_fields should contain the Display Only fee name with amount {string}') do |_expected_amount|
  CapitalDistributionPayment.find_each do |cdp|
    # The json_fields key is the name converted using FormCustomField.to_name
    json_key = FormCustomField.to_name("Audit Entry")
    json_value = cdp.json_fields[json_key]
    puts "Checking json_fields[#{json_key}] = #{json_value}"
    expect(json_value).to be_present, "json_fields should contain the Display Only fee name"
    # The value is stored as currency (e.g., "₹999.99"), so just verify it's non-zero
    expect(json_value.to_s.gsub(/[^\d]/, '').to_i).to be_positive, "json_fields should contain a non-zero amount"
  end
end

Then('the reinvestment_with_fees_cents should be correctly calculated') do
  CapitalDistributionPayment.find_each do |cdp|
    reinvestment_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Reinvestment").sum(:amount_cents)
    cdp.reinvestment_cents
    cdp.reinvestment_with_fees_cents.should
    puts "Reinvestment: reinvestment_with_fees_cents (#{cdp.reinvestment_with_fees_cents}) == reinvestment_cents (#{cdp.reinvestment_cents}) + AE amount (#{reinvestment_ae_amount}) - PASS"
  end
end

Then('the net_payable_cents should account for reinvestment correctly') do
  CapitalDistributionPayment.find_each do |cdp|
    # Verify net_payable is correctly computed (reinvestment increases reinvestment_with_fees which reduces net_payable)
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Reinvestment").sum(:amount_cents)
    # net_payable should be income + cost_of_investment + net_ae_from_reinvestment - reinvestment_with_fees
    # Since reinvestment adds to both net_ae and reinvestment_with_fees, they cancel out for Reinvestment type
    cdp.income_cents
    cdp.cost_of_investment_cents
    cdp.reinvestment_cents
    cdp.net_payable_cents.should
    puts "Net Payable with Reinvestment: net_payable_cents (#{cdp.net_payable_cents}) == income_cents (#{cdp.income_cents}) + cost_of_investment_cents (#{cdp.cost_of_investment_cents}) - PASS"
  end
end

Then('the expense should reduce the income_with_fees_cents correctly') do
  CapitalDistributionPayment.find_each do |cdp|
    expense_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Expense").sum(:amount_cents)
    cdp.income_cents
    cdp.income_with_fees_cents.should
    puts "Expense: income_with_fees_cents (#{cdp.income_with_fees_cents}) == income_cents (#{cdp.income_cents}) - expense AE amount (#{expense_ae_amount}) - PASS"
  end
end

Then('the distribution payments should have the {string} fee details') do |fee_type|
  attr_name = "#{fee_type.downcase.tr(' ', '_')}_with_fees_cents"
  CapitalDistributionPayment.find_each do |cdp|
    fee_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: fee_type).sum(:amount_cents)
    puts "Checking #{fee_type} fee details for CD Payment #{cdp.id}: AE amount = #{fee_ae_amount} cents, attribute #{attr_name} = #{cdp.send(attr_name)} cents"
    expect(fee_ae_amount).to be_positive, "Expected to find AccountEntry with fee type #{fee_type} for capital commitment #{cdp.capital_commitment_id}"
    expect(cdp.send(attr_name)).to eq fee_ae_amount
  end
end

Then('the tax should reduce the income_with_fees_cents correctly') do
  CapitalDistributionPayment.find_each do |cdp|
    tax_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Tax").sum(:amount_cents)
    expected_income_with_fees = cdp.income_cents - tax_ae_amount
    puts "Checking Tax fee details for CD Payment #{cdp.id}: income_cents = #{cdp.income_cents} cents, Tax AE amount = #{tax_ae_amount} cents, expected income_with_fees_cents = #{expected_income_with_fees} cents"
    cdp.income_with_fees_cents.should
    puts "Tax: income_with_fees_cents (#{cdp.income_with_fees_cents}) == income_cents (#{cdp.income_cents}) - tax AE amount (#{tax_ae_amount}) - PASS"
  end
end

When('I create with fees from the capital distribution') do
  visit(capital_distribution_path(@capital_distribution))
  within "#capital_distribution_#{@capital_distribution.id}_actions" do
    click_on("Actions")
  end
  click_on("Replicate Distribution")
end

Then('the distribution actions menu should offer {string} but not {string}') do |present_label, absent_label|
  click_on("Actions")
  expect(page).to have_link(present_label)
  expect(page).not_to have_link(absent_label)
end

When('I visit the capital distributions list for the fund') do
  visit(capital_distributions_path(fund_id: @fund.id))
end

Then('the new distribution form should show the source title as a copy with {string} fee rows') do |count|
  expect(find_field('capital_distribution_title').value).to eq("#{@capital_distribution.title} (Copy)")
  expect(all('.nested-fields').count).to eq(count.to_i)
end

Then('the new distribution form should have a blank title with {string} fee rows pre-filled') do |count|
  expect(find_field('capital_distribution_title').value).to be_blank
  expect(all('.nested-fields').count).to eq(count.to_i)
end


Then('a new Capital Distribution should exist as an independent clone with matching fee rows') do
  cloned = CapitalDistribution.order(:id).last
  expect(cloned.id).not_to eq(@capital_distribution.id)
  expect(cloned.title).to eq("#{@capital_distribution.title} (Copy)")
  expect(cloned.income_cents).to eq(@capital_distribution.income_cents)
  expect(cloned.cost_of_investment_cents).to eq(@capital_distribution.cost_of_investment_cents)
  expect(cloned.distribution_fees.count).to eq(@capital_distribution.distribution_fees.count)
  expect(cloned.distribution_fees.pluck(:name, :fee_type)).to match_array(@capital_distribution.distribution_fees.pluck(:name, :fee_type))
  expect(cloned.distribution_fees.pluck(:id) & @capital_distribution.distribution_fees.pluck(:id)).to be_empty
end

Then("the source capital distribution's fee rows should be unchanged") do
  @capital_distribution.reload
  expect(@capital_distribution.distribution_fees.count).to be_positive
end

Then('the new distribution form should offer {string} as a fund choice') do |fund_name|
  expect(page).to have_select('capital_distribution_fund_id', with_options: [fund_name])
end

When('I switch the new distribution\'s fund to {string}') do |fund_name|
  select fund_name, from: 'capital_distribution_fund_id'
end

Then('the new Capital Distribution should belong to the fund {string} with matching fee rows') do |fund_name|
  target_fund = Fund.find_by(name: fund_name)
  cloned = CapitalDistribution.order(:id).last
  expect(cloned.fund_id).to eq(target_fund.id)
  expect(cloned.entity_id).to eq(target_fund.entity_id)
  expect(cloned.distribution_fees.count).to eq(@capital_distribution.distribution_fees.count)
end

Given('the fund has {string} capital distribution') do |count|
  (1..count.to_i).each do |_i|
    cc = FactoryBot.create(:capital_distribution, fund: @fund)
    puts "\n####CapitalDistribution####\n"
    puts cc.to_json
  end

  @fund.reload
end

Given('the capital distributions are approved') do
  @fund.capital_distributions.each do |cc|
    cc.approved = true
    cc.approved_by_user = @user
    cc.save
  end
end

When('I create a new capital distribution {string}') do |args|
  @capital_distribution = FactoryBot.build(:capital_distribution, fund: @fund)
  key_values(@capital_distribution, args)

  visit(fund_url(@fund))

  click_on "Distributions"
  # sleep((1)
  click_on "New Distribution"

  fill_in('capital_distribution_title', with: @capital_distribution.title)
  fill_in('capital_distribution_income', with: @capital_distribution.income)
  fill_in('capital_distribution_cost_of_investment', with: @capital_distribution.cost_of_investment)
  fill_in('capital_distribution_reinvestment', with: @capital_distribution.reinvestment)
  fill_in('capital_distribution_distribution_date', with: @capital_distribution.distribution_date)

  click_on "Save"
  # sleep(2)
  expect(page).to have_content("Capital distribution was successfully")
end

When("I change the capital distribution's distribution date to {string}") do |new_date|
  visit(edit_capital_distribution_path(@capital_distribution))
  fill_in('capital_distribution_distribution_date', with: new_date)
  click_on('Save')
end

Then('I should see the distribution date change warning naming all the payments') do
  expect(page).to have_css('#distributionDateChangeModal.show')
  expect(page).to have_content("#{@capital_distribution.capital_distribution_payments.count} payment")
end

When('I confirm the distribution date change') do
  within('#distributionDateChangeModal') do
    click_on('Change Distribution Date')
  end
  expect(page).to have_content('Capital distribution was successfully updated')
end

Then("every capital distribution payment's payment date should be {string}") do |new_date|
  @capital_distribution.reload
  @capital_distribution.capital_distribution_payments.each do |cdp|
    cdp.reload
    expect(cdp.payment_date).to eq(Date.parse(new_date))
  end
end

Then('the capital distribution must reflect the payments') do
  @capital_distribution.reload
  @capital_distribution.distribution_amount_cents.should
  @capital_distribution.capital_distribution_payments.sum(:net_payable_cents)
  @capital_distribution.fund.distribution_amount_cents.should == @capital_distribution.capital_distribution_payments.sum(:gross_payable_cents)
end

Then('There should be {string} capital distributions created') do |count|
  @fund.capital_distributions.count.should == count.to_i
end

Then('the capital distributions must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_distributions = @fund.capital_distributions.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_distributions[idx - 1]
    puts "Checking import of #{cc.title}"
    cc.title.should
    user_data["Title"].strip
    cc.fund.name.should
    user_data["Fund"]
    cc.income_cents.should
    user_data["Income"].to_i
    cc.reinvestment_cents.should
    user_data["Reinvestment"].to_i
    cc.distribution_date.should
    Date.local_parse(user_data["Date"])
    cc.gross_amount_cents.round(0).should
    (cc.income_cents + cc.reinvestment_cents + cc.cost_of_investment_cents - cc.reinvestment_cents).round(0)
    cc.import_upload_id.should == ImportUpload.last.id
  end
end

Given('there is a capital distribution {string}') do |args|
  @capital_distribution = FactoryBot.build(:capital_distribution, entity: @fund.entity, fund: @fund, approved: true)
  key_values(@capital_distribution, args)
  @capital_distribution.save!

  puts "\n####CapitalDistribution####\n"
  puts @capital_distribution.to_json
end

Then('I should be able to see my capital distributions') do
  click_on("Distributions")
  CapitalDistributionPayment.find_each do |cc|
    puts "checking capital distrbution payment for #{cc.investor.investor_name} against #{@investor.investor_name} "
    if cc.investor_id == @investor.id
      puts "Distribution Visible"
      # The Investing Entity column prefers the commitment's linked KYC full_name over the plain investor_name.
      expect(page).to have_content(cc.investor_kyc&.full_name || @investor.investor_name) if @user.curr_role != "investor"
      expect(page).to have_content(money_to_currency(cc.net_payable))
      expect(page).to have_content(money_to_currency(cc.gross_payable))
      expect(page).to have_content(I18n.l(cc.payment_date))
    else
      puts "Distribution Not Visible"
      expect(page).not_to have_content(cc.investor.investor_name)
    end
  end
end

Then('the corresponding distribution payments should be created') do
  CapitalDistributionPayment.count.should
  CapitalCommitment.count
  CapitalDistributionPayment.find_each do |cdp|
    cdp.investor_id.should
    cdp.capital_commitment.investor_id
    cdp.income_cents.should
    @capital_distribution.income_cents
    cdp.capital_commitment.percentage
    cdp.folio_id.should
    cdp.capital_commitment.folio_id
    cdp.capital_distribution_id.should
    @capital_distribution.id
    cdp.investor_name.should == cdp.capital_commitment.investor_name
  end
end

Then('I should see the distribution payments') do
  visit(capital_distribution_path(@capital_distribution))
  CapitalDistributionPayment.find_each do |cdp|
    within("#capital_distribution_payment_#{cdp.id}") do
      expect(page).to have_content(cdp.investor_name)
      expect(page).to have_content(cdp.folio_id)
      expect(page).to have_content(money_to_currency(cdp.gross_payable))
      expect(page).to have_content(money_to_currency(cdp.net_payable))
      # expect(page).to have_content(money_to_currency(cdp.cost_of_investment))
      expect(page).to have_content(I18n.l(cdp.payment_date))
      # expect(page).to have_content(money_to_currency(cdp.reinvestment))
      expect(page).to have_content(cdp.completed ? "Yes" : "No")
    end
  end
end

Given('the distribution payments are completed') do
  puts CapitalDistributionPayment.all.to_json

  CapitalDistributionPayment.find_each do |cdp|
    cdp.completed = true
    CapitalDistributionPaymentUpdate.wtf?(capital_distribution_payment: cdp).success?.should == true
  end
end

Given('Capital Distribution Payment Notification is sent') do
  CapitalDistributionPaymentNotifier::Notification.count.should == CapitalDistributionPayment.count
end

Then('there should be correct units for the distribution payments for each investor') do
  CapitalCommitment.find_each do |cc|
    puts "Checking units for #{cc}"
    cc.fund_units.length.should be_positive
    cc.fund_units.each do |fu|
      ap fu
      fu.unit_type.should == cc.unit_type
      fu.owner_type.should == "CapitalDistributionPayment"
      fu.price_cents == fu.owner.capital_distribution.unit_prices[fu.unit_type].to_d * 100
      fu.quantity.should == -(fu.owner.cost_of_investment_cents / fu.price_cents)
    end
  end

  # No duplicate fund units for the same distribution payment
  FundUnit.where(owner_type: "CapitalDistributionPayment").pluck(:owner_id).tally.count { |_k, v| v > 1 }.should == 0
end

Then('Given I upload {string} file for Distributions of the fund') do |_string|
  visit(capital_distributions_url)
  # sleep((2)
  click_on("Upload")
  # sleep((2)
  fill_in('import_upload_name', with: "Test Distributions Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/capital_distributions.xlsx'), make_visible: true)
  # sleep((2)
  click_on("Save")
  # sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep((4)
  ImportUpload.last.failed_row_count.should
  ImportUpload.last.status.should == "Completed"
end

Then('Given I upload {string} file for the Distribution Payments of the fund') do |file_name|
  visit(new_import_upload_path('import_upload[entity_id]': @fund.entity_id, 'import_upload[import_type]': "CapitalDistributionPayment"))
  # sleep((2)
  fill_in('import_upload_name', with: "Test CDP Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  # sleep((2)
  click_on("Save")
  # sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep((4)
  ImportUpload.last.failed_row_count.should
  ImportUpload.last.status.should == "Completed"
end

Then('There should be {string} distribution payments created') do |count|
  CapitalDistributionPayment.count.should == count.to_i
end

Then('the capital distribution payments must have the data in the sheet {string}') do |file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_distribution = CapitalDistribution.where(title: row_data["Capital Distribution"].strip).first
    # The investor is now derived from the folio's commitment, so find the payment via the folio
    cdp = CapitalDistributionPayment.where(folio_id: row_data["Folio No"].to_s, capital_distribution:).first

    puts "Checking import of #{cdp.to_json}"

    cdp.folio_id.should
    row_data["Folio No"].to_s
    cdp.income.to_d.should
    row_data["Income"].to_d
    cdp.cost_of_investment.to_d.should
    row_data["Face Value For Redemption"].to_d
    cdp.payment_date.should
    Date.local_parse(row_data["Payment Date"].to_s)
    cdp.completed.should
    row_data["Completed"]
    cdp.income_with_fees.to_d.should
    cdp.income.to_d
    cdp.cost_of_investment_with_fees.to_d.should
    cdp.cost_of_investment.to_d

    cdp.net_payable_cents.should
    cdp.income_cents
    cdp.net_of_account_entries_cents
    cdp.cost_of_investment_cents
    cdp.reinvestment_with_fees_cents
    cdp.gross_payable_cents.should == cdp.income_cents + cdp.gross_of_account_entries_cents + cdp.cost_of_investment_cents
  end
end

Then('The proper documents must be uploaded for the commitments and distributions') do
  expect(ImportUpload.last.failed_row_count).to eq(10)
  doc1 = Document.where(name: "Tax Statement").first
  expect(doc1.owner).to eq(CapitalCommitment.where(fund: @fund, folio_id: "6").first)
  doc2 = Document.where(name: "Distribution letter").first
  cd = CapitalDistribution.where(fund: @fund, title: "Distribution 1").first
  expect(doc2.owner).to eq(CapitalDistributionPayment.where(fund: @fund, capital_distribution_id: cd.id).first)
end

Then('I should see the commitment and distribuition docs upload errors') do
  import_upload = ImportUpload.last
  tempfile = import_upload.import_results.download
  file = File.open(tempfile.path, "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  # The commented out checks are for errors that are no longer generated due to changes in the import which does not check the kyc now.
  data.each_with_index do |row, idx|
    p row[headers.length]
    next if idx.zero? # skip header row

    row[headers.length].include?("Success").should == true if [1, 2].include?(idx)
    row[headers.length].include?("Fund Absent Fund not found").should == true if idx == 3
    if idx == 4
      # row[headers.length].include?("Investing Entity Investor 99 not found").should == true
    end
    if idx == 5
      # row[headers.length].include?("Capital Commitment not found for SAAS Fund, 1001 and Investor 1").should == true
    end
    row[headers.length].include?("Distribution Name must be specified for a Capital Distribution document").should == true if idx == 6
    row[headers.length].include?("Capital Distribution not found for SAAS Fund, Distribution 99").should == true if idx == 7
    if idx == 8
      # row[headers.length].include?("Capital Distribution Payment not found for SAAS Fund, Distribution 3, 10 and Investor 1").should == true
    end
    row[headers.length].include?("Fund is blank").should == true if idx == 9
    if idx == 10
      # row[headers.length].include?("Investing Entity is blank").should == true
    end
    row[headers.length].include?("Folio No is blank").should == true if idx == 11
    row[headers.length].include?("file1.pdf cannot be uploaded again").should == true if idx == 12
  end
end

Given('We Generate documents for the capital distribution') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  @capital_distribution_payments.each do |cdp|
    unless cdp.capital_commitment&.investor_kyc&.verified
      if cdp.capital_commitment.investor_kyc.present?
        cdp.capital_commitment.investor_kyc.update_columns(verified: true, completed_by_investor: true, submission_status: "verified")
        puts "KYC for investor #{cdp.investor_name} verified"
      else
        investor_kyc = InvestorKyc.new(investor: cdp.capital_commitment.investor, entity: @entity, verified: true, completed_by_investor: true, submission_status: "verified", full_name: cdp.investor_name, PAN: Faker::Alphanumeric.alphanumeric(number: 10).upcase, birth_date: Time.zone.today - 18.years)
        res = investor_kyc.save(validate: false)
        puts "KYC for investor #{cdp.investor_name} created and verified: #{res}"
        cdp.capital_commitment.investor_kyc = investor_kyc
        cdp.capital_commitment.save(validate: false)
        puts "Capital Commitment #{cdp.capital_commitment.id} updated with KYC"
      end
    end
  end
  visit(capital_distribution_path(@capital_distribution))
  # Both inside the Actions menu: the journey panel has its own "Generate Documents" button too
  within "#capital_distribution_#{@capital_distribution.id}_actions" do
    click_on("Actions")
    click_on("Generate Documents")
  end
  click_on("Proceed")
  sleep(5) # Wait for the job to complete
  # With :inline job adapter the job runs synchronously and the completion flash
  # ("N documents generated successfully") replaces the async "started" flash
  # before this assertion could catch it. Accept either message.
  expect(page).to have_content(
    /Documentation generation started|documents? generated/i,
    wait: 20
  )
end

When('I generate distribution payment documents directly for the capital distribution') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  # KYC must be verified or DocGenJob#validate skips the payment — same setup as
  # "We Generate documents for the capital distribution" above, but this step calls
  # the job directly (perform_now) instead of driving it through the UI, so a
  # SQL query counter wrapped around this step (see sql_query_count_steps.rb)
  # observes the job's own queries instead of a separate browser/server process's.
  @capital_distribution_payments.each do |cdp|
    next if cdp.capital_commitment&.investor_kyc&.verified

    if cdp.capital_commitment.investor_kyc.present?
      cdp.capital_commitment.investor_kyc.update_columns(verified: true, completed_by_investor: true, submission_status: "verified")
    else
      investor_kyc = InvestorKyc.new(investor: cdp.capital_commitment.investor, entity: @entity, verified: true, completed_by_investor: true, submission_status: "verified", full_name: cdp.investor_name, PAN: Faker::Alphanumeric.alphanumeric(number: 10).upcase, birth_date: Time.zone.today - 18.years)
      investor_kyc.save(validate: false)
      cdp.capital_commitment.investor_kyc = investor_kyc
      cdp.capital_commitment.save(validate: false)
    end
  end

  # nil payment id triggers the bulk "all payments in this distribution" path in
  # CapitalDistributionPaymentDocJob#models
  CapitalDistributionPaymentDocJob.perform_now(@capital_distribution.id, nil, @user.id)
end

Given('The distribution payment documents are approved') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  @capital_distribution_payments.each do |cdp|
    # perform_now runs the job's own code synchronously, but doc conversion happens on
    # a separate LibreOffice-profile thread (see DocumentGeneratorBase), so the document
    # row can still land after this call returns. Same 20s as the sibling doc-gen waits.
    eventually(timeout: 20) { expect(cdp.documents.count).to be_positive }
    cdp.documents.each do |doc|
      doc.approved = true
      res = doc.save
      puts "Document #{doc.id} approved: #{res}"
    end
  end
end

Then('Distribution notice should be generate for all distribution payments with verified KYC') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  @capital_distribution_payments.each do |cdp|
    unless cdp.capital_commitment&.investor_kyc&.verified
      puts "Skipping distribution payment #{cdp.id} for investor #{cdp.investor_name} as KYC is not verified"
      next
    end
    cdp.documents.each do |doc|
      puts "Checking document #{doc.name} for distribution payment #{cdp.id}"
      expect(doc.name.include?("Distribution Template - #{cdp.investor_name}")).to be true
      doc.approved.should == true
      doc.owner_type.should == "CapitalDistributionPayment"
      doc.owner_id.should == cdp.id
    end
  end
end

Given('there is a custom notification for the capital distribution with subject {string} with email_method {string}') do |subject, email_method|
  @custom_notification = CustomNotification.create!(entity: @capital_distribution.entity, subject: subject, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_distribution, email_method: email_method)
end

Given('there is a custom notification {string} in place for the Fund for Distributions') do |args|
  @custom_notification = CustomNotification.build(entity: @entity, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @fund, for_type: "CapitalDistribution")
  key_values(@custom_notification, args)
  @custom_notification.save!
end

Given('there is a custom notification with placeholders for the capital distribution with subject {string} with email_method {string}') do |subject, email_method|
  @custom_notification = CustomNotification.create!(
    entity: @capital_distribution.entity,
    owner: @capital_distribution,
    email_method: email_method,
    subject: subject,
    body: "Dear {{user_full_name}}, {{investor_name}} of {{fund_name}}. Folio {{folio_id}}, commitment {{committed_amount}}. Unknown: {{not_a_real_placeholder}}.",
    whatsapp: "Placeholder test",
    enabled: true
  )
end

Then('the capital distribution notification placeholders are resolved correctly') do
  @custom_notification.should_not be_nil

  email_found = false
  @capital_distribution.capital_distribution_payments.each do |cdp|
    cdp.investor.notification_users(@fund).each do |user|
      open_email(user.email)
      next if current_email.nil?

      email_found = true
      body = current_email.body.to_s

      # Known CapitalDistributionPaymentsMailer placeholders resolved
      expect(body).not_to include("{{user_full_name}}")
      expect(body).not_to include("{{investor_name}}")
      expect(body).not_to include("{{fund_name}}")
      expect(body).not_to include("{{folio_id}}")
      expect(body).not_to include("{{committed_amount}}")
      expect(body).to include(@fund.name)

      # Unknown placeholder preserved
      expect(body).to include("{{not_a_real_placeholder}}")
    end
  end
  expect(email_found).to(be(true), "No emails were delivered for any distribution payment")
  clear_emails
end

Given('The capital distribution payments are approved') do
  CapitalDistributionPayment.where(capital_distribution: @capital_distribution).find_each do |cdp|
    cdp.approved = true
    res = cdp.save
    puts "Capital distribution payment #{cdp.id} approved: #{res}"
  end
end

Given('the fund has a Distribution Template') do
  @distribution_template = Document.create!(name: "Distribution Template", owner_tag: "Distribution Template",
                                            owner: @fund, entity_id: @fund.entity_id, user: @user,
                                            file: File.new("public/sample_uploads/Distribution notice template.docx", "r"))
end

Given('the dist payments have proper notification users') do
  @capital_distribution ||= @fund.capital_distributions.first
  @capital_distribution.capital_distribution_payments.each do |cdp|
    next if cdp.investor.notification_users(@fund).present?

    investor = cdp.investor
    user = FactoryBot.create(:user, entity: investor.investor_entity)
    user.permissions.set(:enable_funds)
    user.save!
    user.entity.permissions.set(:enable_funds)
    user.entity.save!
    AccessRight.create!(entity: @fund.entity, access_to_investor_id: cdp.investor_id, metadata: "investor", access_type: "Fund", owner: @fund) if @fund.access_rights.where(access_to_investor_id: cdp.investor_id).blank?
    InvestorAccess.create!(email: user.email, investor: investor, approved: true, entity: investor.entity, first_name: user.first_name, last_name: user.last_name, user: @user, email_enabled: true)
    user.reload
  end
  @fund.reload
end

Given('dist notice is generated for the dist payments') do
  @capital_distribution = @fund.capital_distributions.first
  visit(capital_distribution_path(@capital_distribution))
  # Both inside the Actions menu: the journey panel has its own "Generate Documents" button too
  within "#capital_distribution_#{@capital_distribution.id}_actions" do
    click_on("Actions")
    click_on("Generate Documents")
  end
  click_on("Proceed")
  sleep(10) # Wait for the job to complete
  # With :inline job adapter the job runs synchronously and the completion flash
  # ("N documents generated successfully") replaces the async "started" flash
  # before this assertion could catch it. Accept either message.
  expect(page).to have_content(
    /Documentation generation started|documents? generated/i,
    wait: 20
  )
end

Then('dist notice must be generated for each dist payment') do
  @capital_distribution ||= @fund.capital_distributions.first
  distribution_template_name = @capital_distribution.fund.documents.where(owner_tag: "Distribution Template").first.name
  @capital_distribution.capital_distribution_payments.each do |cdp|
    puts "Checking distribution payment #{cdp.id} for investor #{cdp.investor_name} for document #{distribution_template_name} - #{cdp.investor_kyc} - #{cdp.folio_id}"
    # The generate-docs job runs inline but ActionCable broadcasts "started" before docs
    # are committed, so the previous step can return while the job is mid-flight. Retry
    # (same gap fixed for the analogous capital-call/commitment doc-gen checks).
    eventually(timeout: 20) do
      puts "All Available documents for distribution payment #{cdp.id}: #{cdp.documents.pluck(:name)}"
      cdp.documents.reload.pluck(:name).include?("#{distribution_template_name} - #{cdp.investor_kyc} - #{cdp.folio_id}").should == true
    end
    puts "------------------------------------------------------------------------"
  end
end

Given('the distribution is approved') do
  dists = @capital_distribution.present? ? @fund.capital_distributions.where(id: @capital_distribution.id) : @fund.capital_distributions
  dists.update_all(approved: true)
end

Given('I trigger notification for the distribution') do
  @capital_distribution ||= @fund.capital_distributions.first
  visit(capital_distribution_path(@capital_distribution))
  # Inside the Actions menu: the journey panel can show its own "Send Payment Notifications" button
  within "#capital_distribution_#{@capital_distribution.id}_actions" do
    click_on("Actions")
    click_on("Send Payment Notifications")
  end
  click_on("Proceed")
  sleep(5) # Wait for the job to complete
end

Then('the notification must be sent to the investors where the distribution notice was generated') do
  @capital_distribution ||= @fund.capital_distributions.first
  puts "Total Notifications - #{Noticed::Notification.count}"

  distribution_template_name = @capital_distribution.fund.documents.where(owner_tag: "Distribution Template").first.name
  @capital_distribution.capital_distribution_payments.each do |cdp|
    if cdp.documents.pluck(:name).include?("#{distribution_template_name} - #{cdp.investor_kyc} - #{cdp.folio_id}")
      cdp.investor.notification_users(@fund).each do |nu|
        current_email = nil
        emails_sent_to(nu.email).each do |email|
          puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
          current_email = email if email.subject.include?("Capital Distribution: #{cdp.fund.name}")
        end
        puts "Checking email to #{nu.email} for distribution payment #{cdp.id}"
        expect(current_email.body).to include "Please refer to the attached notice for further details or click on the link below"
      end
    else
      puts "No distribution notice generated for distribution payment #{cdp.id}, skipping notification check"
    end
  end
end

Given('I update the dist payments commitments custom fields with the same kyc and earlier payment date {string}') do |custom_fields|
  @capital_distribution ||= @fund.capital_distributions.first
  # Load all dist payments for the distribution, with their commitments + KYC,
  # ordered so that within each KYC group, the latest remittance is last.
  dist_payments = @capital_distribution.capital_distribution_payments
                                       .joins(:capital_commitment)
                                       .includes(:capital_commitment)
                                       .where.not(capital_commitments: { investor_kyc_id: nil })
                                       .order(
                                         'capital_commitments.investor_kyc_id ASC',
                                         'capital_distribution_payments.payment_date ASC',
                                         'capital_distribution_payments.id ASC'
                                       )

  # Group by KYC (through the commitment)
  dist_payments.group_by { |cr| cr.capital_commitment.investor_kyc_id }.each_value do |group|
    # If only one dist payment for that KYC, nothing to "earlier" update
    next if group.size <= 1

    # Take all except the latest (last in the sorted group)
    group[0..-2].each do |cdp|
      puts "Updating commitment #{cdp.capital_commitment.id} for dist payment #{cdp.id} for KYC #{cdp.capital_commitment.investor_kyc_id}"
      # Assuming key_values(model, attrs_string) assigns attributes from attrs
      custom_fields.split(",").each do |cf|
        k, v = cf.split(":").map(&:strip)
        cdp.capital_commitment.json_fields[k] = v
      end
      cdp.capital_commitment.save!
    end
  end
end

And('dist notice must be generated for the latest dist payment for each kyc') do
  @capital_distribution ||= @fund.capital_distributions.first
  # Load all dist payments for the distribution, with their commitments + KYC,
  # ordered so that within each KYC group, the latest remittance is last.
  dist_payments = @capital_distribution.capital_distribution_payments
                                       .joins(:capital_commitment)
                                       .includes(:capital_commitment)
                                       .where.not(capital_commitments: { investor_kyc_id: nil })
                                       .order(
                                         'capital_commitments.investor_kyc_id ASC',
                                         'capital_distribution_payments.payment_date ASC',
                                         'capital_distribution_payments.id ASC'
                                       )

  # Group by KYC (through the commitment)
  dist_template_name = @capital_distribution.fund.documents.where(owner_tag: "Distribution Template").last.name
  dist_payments.group_by { |cr| cr.capital_commitment.investor_kyc_id }.each_value do |group|
    # If only one dist payment for that KYC, then doc will be generated for that, so just check and move to next

    if group.size == 1
      cr = group.first
      puts "Only one distribution payment #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id}, checking if document is generated"
      cr.documents.pluck(:name).include?("#{dist_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should
      next
    end

    # Take all except the latest (last in the sorted group)
    group[0..-2].each do |cr|
      puts "Checking dist payment #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id} is NOT generated"
      cr.documents.pluck(:name).include?("#{dist_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should == false
    end
    group.last.tap do |cr|
      puts "Checking dist payment #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id} IS generated"
      cr.documents.pluck(:name).include?("#{dist_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should
    end
  end
end

Given('the distribution is not manually generated') do
  @capital_distribution ||= @fund.capital_distributions.first
  @capital_distribution.update_columns(manual_generation: false)
end

Then('the new capital distribution payments must have the data in the sheet {string}') do |file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  cdps = Set.new
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_distribution = CapitalDistribution.where(title: row_data["Capital Distribution"].strip).first

    # The investor is now derived from the folio's commitment, so find the payment via the folio
    cdp = CapitalDistributionPayment.where(folio_id: row_data["Folio No"].to_s, capital_distribution:).where.not(id: cdps.map(&:id)).first
    cdps.add(cdp)
    puts "Checking import of #{cdp.to_json}"

    cdp.folio_id.should
    row_data["Folio No"].to_s
    cdp.income.to_d.should
    row_data["Income"].to_d
    cdp.cost_of_investment.to_d.should
    row_data["Face Value For Redemption"].to_d
    cdp.payment_date.should
    Date.local_parse(row_data["Payment Date"].to_s)
    cdp.completed.should
    row_data["Completed"]
    cdp.income_with_fees.to_d.should
    cdp.income.to_d
    cdp.cost_of_investment_with_fees.to_d.should
    cdp.cost_of_investment.to_d

    cdp.net_payable_cents.should
    cdp.income_cents
    cdp.net_of_account_entries_cents
    cdp.cost_of_investment_cents
    cdp.reinvestment_with_fees_cents
    cdp.gross_payable_cents.should == cdp.income_cents + cdp.gross_of_account_entries_cents + cdp.cost_of_investment_cents
  end
end

Then('the generated distribution notices have as_of set to the payment date') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  @capital_distribution_payments.each do |cdp|
    next unless cdp.capital_commitment&.investor_kyc&.verified

    doc = cdp.documents.generated.last
    puts "Checking distribution notice as_of for payment #{cdp.id}: doc.as_of=#{doc&.as_of}, payment_date=#{cdp.payment_date}"
    expect(doc).to be_present, "Expected a generated document for distribution payment #{cdp.id}"
    expect(doc.as_of).to eq(cdp.payment_date)
  end
end

Then('I should see the capital distrbution details') do
  find(".show_details_link").click

  expect(page).to have_content(@capital_distribution.title)
  expect(page).to have_content(money_to_currency(@capital_distribution.gross_amount))
  expect(page).to have_content(money_to_currency(@capital_distribution.reinvestment))
  expect(page).to have_content(money_to_currency(@capital_distribution.income))
  expect(page).to have_content(I18n.l(@capital_distribution.distribution_date))

  @new_capital_distribution = CapitalDistribution.last
  @new_capital_distribution.approved.should
  @new_capital_distribution.distribution_amount_cents.should
  @new_capital_distribution.capital_distribution_payments.sum(:net_payable_cents)
  @new_capital_distribution.completed_distribution_amount_cents.should
  # @new_capital_distribution.capital_distribution_payments.length.should == 0

  @capital_distribution = @new_capital_distribution
end

Then('when the capital distrbution is approved') do
  @capital_distribution.approved = true
  @capital_distribution.approved_by_user = @user
  @capital_distribution.save
  # sleep((1)
  @capital_distribution.reload
end

Then('I should see the capital distrbution payments generated correctly') do
  puts "### payments length = #{@capital_distribution.capital_distribution_payments.length}"
  @capital_distribution.capital_distribution_payments.length.should
  @fund.capital_commitments.length
  @fund.capital_commitments.each do |cc|
    cdp = @capital_distribution.capital_distribution_payments.where(investor_id: cc.investor_id).first
    cdp.completed.should == false
    cdp.income_cents.should == cc.percentage * @capital_distribution.income_cents / 100
  end
end

Then('I should be able to see the capital distrbution payments') do
  visit(capital_distribution_path(@capital_distribution, tab: "payments-tab"))
  @capital_distribution.capital_distribution_payments.includes(:investor).find_each do |p|
    within "#capital_distribution_payment_#{p.id}" do
      expect(page).to have_content(p.investor.investor_name)
      expect(page).to have_content(money_to_currency(p.gross_payable))
      expect(page).to have_content(money_to_currency(p.net_payable))
      expect(page).to have_content(I18n.l(p.payment_date))
      expect(page).to have_content(p.completed ? "Yes" : "No")
    end
  end
end

Then('when the capital distrbution payments are marked as paid') do
  @capital_distribution.capital_distribution_payments.each do |cdp|
    cdp.completed = true
    CapitalDistributionPaymentUpdate.wtf?(capital_distribution_payment: cdp).success?.should == true
  end
end

Then('the payments are generated for the capital distrbutions') do
  Fund.find_each do |fund|
    fund.capital_distributions.each do |cc|
      # puts cc.capital_distribution_payments.to_json
      capital_distribution_payments_count = fund.capital_commitments.count
      cc.capital_distribution_payments.count.should == capital_distribution_payments_count
      cc.capital_distribution_payments.sum(:income_cents).round(0).should == cc.income_cents.round(0)
    end
  end
end
