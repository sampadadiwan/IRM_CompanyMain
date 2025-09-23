  include CurrencyHelper
  include ActionView::Helpers::SanitizeHelper

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
    db_fund.name.should == @fund.name
    strip_tags(db_fund.details) == @fund.details

    @fund = db_fund
  end




  When('I am at the fund details page') do
    visit(fund_url(@fund))
  end


  Then('I should see the fund details on the details page') do
    find(".show_details_link").click
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(@fund.unit_types) if @fund.unit_types.present?
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

  Given('the investors are added to the fund') do
    @user.entity.investors.each do |inv|
        ar = AccessRight.create( owner: @fund, access_type: "Fund", metadata: "Investor",
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json
    end

  end

  When('I add a capital commitment {string} for investor {string}') do |amount, investor_name|
    @new_capital_commitment = FactoryBot.build(:capital_commitment, investor_name: investor_name, orig_folio_committed_amount_cents: (amount.to_d * 100), fund: @fund)
    @new_capital_commitment.fund_close ||= "First Close"

    visit(fund_url(@fund))
    click_on("Commitments")
    click_on("New Commitment")
    select(@new_capital_commitment.investor_name, from: "capital_commitment_investor_id")
    fill_in('capital_commitment_orig_folio_committed_amount', with: @new_capital_commitment.orig_folio_committed_amount.to_d)
    if @fund.capital_commitments.count > 0
      select(@new_capital_commitment.fund_close, from: "capital_commitment_fund_close")
    else
      fill_in('capital_commitment_fund_close', with: @new_capital_commitment.fund_close)
    end
    fill_in('capital_commitment_folio_id', with: rand(10**4))
    fill_in('capital_commitment_commitment_date', with: @new_capital_commitment.commitment_date)
    select(@new_capital_commitment.folio_currency, from: "capital_commitment_folio_currency")

    if @fund.entity.permissions.enable_units?
      unit_types = @fund.unit_types.split(",").map{|x| x.strip}
      @new_capital_commitment.unit_type = unit_types[rand(unit_types.length)]
      select(@new_capital_commitment.unit_type, from: 'capital_commitment_unit_type')
    end

    click_on "Save"

    expect(page).to have_content("Capital commitment was successfully")
  end

  Then('I should see the capital commitment details') do
    find(".show_details_link").click

    @capital_commitment = CapitalCommitment.last
    @capital_commitment.investor_name.should == @new_capital_commitment.investor_name
    @capital_commitment.unit_type.should == @new_capital_commitment.unit_type
    @capital_commitment.orig_folio_committed_amount_cents.should == @new_capital_commitment.orig_folio_committed_amount_cents

    expect(page).to have_content(@capital_commitment.investor_name)
    expect(page).to have_content(@capital_commitment.entity.name)
    expect(page).to have_content(@capital_commitment.fund_close)
    expect(page).to have_content(money_to_currency @capital_commitment.folio_committed_amount, {})
    expect(page).to have_content(money_to_currency @capital_commitment.committed_amount, {})
    expect(page).to have_content(@capital_commitment.fund.name)
    expect(page).to have_content(@capital_commitment.unit_type) if @fund.entity.permissions.enable_units?
  end

  Then('the fund total committed amount must be {string}') do |amount|
    @fund.reload
    (@fund.committed_amount_cents / 100).should == amount.to_i
  end

  Given('there are capital commitments of {string} from each investor') do |args|
    @fund.investors.each do |inv|
        commitment = FactoryBot.build(:capital_commitment, fund: @fund, investor: inv)
        key_values(commitment, args)
        CapitalCommitmentCreate.call(capital_commitment: commitment)
        puts "\n####CapitalCommitment####\n"
        puts commitment.to_json
    end
  end

  Given('there is a capital commitment of {string} for the last investor') do |args|
    @fund.reload
    inv = Investor.last
    @capital_commitment = FactoryBot.build(:capital_commitment, fund: @fund, investor: inv)
    key_values(@capital_commitment, args)
    result = CapitalCommitmentCreate.wtf?(capital_commitment: @capital_commitment)
    result.success?.should == true
    puts "\n####CapitalCommitment####\n"
    puts @capital_commitment.to_json
  end

  Then('the capital commitment percentages should be updated correctly') do
    @capital_commitment.fund.reload.check_percentage_calcs.should == []
  end

  Given('there is a capital call {string}') do |arg|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity)
    # Todo: Abhay Move this logic to env
    hash = arg.split('=').last
    hash = hash.gsub("'", "\"")
    close_percentages = JSON.parse(hash)
    if close_percentages.is_a?(Hash) && close_percentages.key?("First Close")
      @capital_call.close_percentages = close_percentages
    else
      key_values(@capital_call, arg)
    end
    CapitalCallCreate.call(capital_call: @capital_call)
    puts "\n####CapitalCall####\n"
    puts @capital_call.to_json
  end


  When('I create a new capital call {string}') do |args|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund)
    key_values(@capital_call, args)
    @capital_call.setup_defaults

    puts @capital_call.to_json

    visit(fund_url(@fund))

    click_on "Calls"
    click_on "New Call"

    fill_in('capital_call_name', with: @capital_call.name)

    fill_in('capital_call_due_date', with: @capital_call.due_date)
    fill_in "capital_call[close_percentages][First Close]", with: "50"
    select(@capital_call.call_basis, from: 'capital_call_call_basis')

    if @capital_call.call_basis == "Percentage of Commitment"
        fill_in "capital_call[close_percentages][First Close]", with: @capital_call.percentage_called
    elsif @capital_call.call_basis != "Upload"
      find('#select2-capital_call_fund_closes-container', visible: false)
      select2_trigger = find('.select2-selection--multiple', match: :first)
      select2_trigger.click
      first_option = find(".select2-results__option", match: :first, visible: true)
      first_option.click
      fill_in('capital_call_amount_to_be_called', with: @capital_call.amount_to_be_called)
    end

    if @fund.entity.permissions.enable_units?
      @fund.unit_types.split(",").each do |unit_type|
        unit_type = unit_type.strip
        fill_in("#{unit_type}_price", with: @capital_call.unit_prices[unit_type]["price"])
        fill_in("#{unit_type}_premium", with: @capital_call.unit_prices[unit_type]["premium"])
      end
    end

    if @capital_call.call_basis == "Amount allocated on Investable Capital"
      @capital_call.fee_account_entry_names.each_with_index do |fee_name, idx|
        click_on "Add Fees"
        #sleep((1)
        within all(".nested-fields").last do
          select(fee_name, from: "fee_name")
          fill_in("fee_start_date", with: Time.zone.today - 10.years)
          fill_in("fee_end_date", with: Time.zone.today)
          select(CapitalCall::FEE_TYPES[0], from: "call_fee_types")
        end
      end
    end
    allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
    click_on "Save"
    # sleep(2)
    expect(page).to have_content("Capital call was successfully")
  end

  Then('the no remittances should be created') do
    @capital_call = CapitalCall.last
    @capital_call.capital_remittances.count.should == 0
  end

  Then('the corresponding remittances should be created') do

    @capital_call = CapitalCall.last
    if @capital_call.call_basis != "Upload"
      @capital_call.capital_remittances.count.should == @fund.capital_commitments.count
    end

    @capital_call.capital_remittances.each_with_index do |remittance, idx|
        ap remittance
        cc = remittance.capital_commitment
        if @capital_call.call_basis == "Amount allocated on Investable Capital"
          ((@capital_call.amount_to_be_called * remittance.percentage / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Percentage of Commitment"
          ((cc.committed_amount * @capital_call.close_percentages["First Close"].to_f / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Upload"
          file = File.open("./public/sample_uploads/capital_remittances.xlsx", "r")
          data = Roo::Spreadsheet.open(file.path) # open spreadsheet
          headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
          row = data.row(idx+2)
          # create hash from headers and cells
          user_data = [headers, row].transpose.to_h

          puts "Checking import of #{user_data}"
          remittance.investor.investor_name.should == user_data["Investor"].strip
          remittance.fund.name.should == user_data["Fund"]
          remittance.capital_call.name.should == user_data["Capital Call"]

          remittance.folio_call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees, Folio Currency)"].to_f * 100
          remittance.folio_capital_fee_cents.should == user_data["Capital Fees (Folio Currency)"].to_f * 100
          remittance.folio_other_fee_cents.should == user_data["Other Fees (Folio Currency)"].to_f * 100

          remittance.call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].to_f * 100 if user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].present?
          remittance.capital_fee_cents.should == user_data["Capital Fees (Fund Currency)"].to_f * 100 if user_data["Capital Fees (Fund Currency)"].present?
          remittance.other_fee_cents.should == user_data["Other Fees (Fund Currency)"].to_f * 100 if user_data["Other Fees (Fund Currency)"].present?

          remittance.status.should == "Pending"
          remittance.verified.should == (user_data["Verified"] == "Yes")
        end

        # Check the fees
        if @capital_call.call_fees.present?
          @capital_call.call_fees.each do |fee|
            remittance.capital_fee_cents.should > 0
            # remittance.other_fee_cents.should > 0
          end
        end
    end
  end

  Then('I should see the remittances') do
    @capital_call.reload
    # @fund.capital_commitments.count.should == @fund.investors.count
    @capital_call.capital_remittances.count.should == @fund.capital_commitments.count

    visit(capital_call_url(@capital_call))
    #sleep((2)
    click_on "Remittances"

    @capital_call.capital_remittances.each do |remittance|
        within("#capital_remittance_#{remittance.id}") do
            expect(page).to have_content(remittance.investor.investor_name)
            expect(page).to have_content(remittance.verified ? "Yes" : "No")
            expect(page).to have_content(remittance.status)
            expect(page).to have_content(money_to_currency remittance.due_amount)
            expect(page).to have_content(money_to_currency remittance.collected_amount)
        end
    end
  end


   Then('I should see the capital call details') do
    find(".show_details_link").click
    @capital_call = CapitalCall.last
    expect(page).to have_content(@capital_call.name)
    expect(page).to have_content(@capital_call.close_percentages["First Close"].to_i) if  @capital_call.call_basis == "Percentage of Commitment"
    expect(page).to have_content(money_to_currency @capital_call.amount_to_be_called) if  @capital_call.amount_to_be_called_cents > 0

    expect(page).to have_content(@capital_call.due_date.strftime("%d/%m/%Y"))
  end


  Then('the remittances must be marked with notification sent') do
    @capital_call.capital_remittances.each do |remittance|
      remittance.notification_sent.should == true
    end
  end

  When('I mark the remittances as paid') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_remittance_url(remittance))
      click_on "New Payment"
      fill_in('capital_remittance_payment_folio_amount', with: remittance.due_amount)
      click_on "Save"
      # sleep(2)
      expect(page).to have_content("Capital remittance payment was successfully")
    end
  end

  When('I mark the remittances as verified') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_call_url(@capital_call))
      #sleep((1)
      click_on "Remittances"
      #sleep((1)
      within("#capital_remittance_#{remittance.id}") do
        click_on "Actions"
        click_on "Verify"
        #sleep((1)
      end
      click_on "Proceed"
      #sleep((1)
    end
  end


Then('the capital call collected amount should be {string}') do |arg|
  #sleep((1)
  @capital_call.reload
  @capital_call.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.fund.currency)
  @capital_call.fund.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.fund.currency)
end


Then('the remittance rollups should be correct') do
  # Call rollups
  CapitalCall.all.each do |capital_call|
    capital_call.reload
    puts "Checking rollups for #{capital_call.name}"
    capital_call.capital_fee_cents.should == capital_call.capital_remittances.sum(:capital_fee_cents)
    capital_call.other_fee_cents.should == capital_call.capital_remittances.sum(:other_fee_cents)
    capital_call.collected_amount_cents.should == capital_call.capital_remittances.verified.sum(:collected_amount_cents)
    capital_call.call_amount_cents.should == capital_call.capital_remittances.sum(:call_amount_cents)

    # Fund rollups
    fund = capital_call.fund
    puts "Checking rollups for fund #{fund.name}"
    fund.capital_fee_cents.should == fund.capital_remittances.sum(:capital_fee_cents)
    fund.other_fee_cents.should == fund.capital_remittances.sum(:other_fee_cents)
    fund.call_amount_cents.should == fund.capital_remittances.sum(:call_amount_cents)
    fund.collected_amount_cents.should == fund.capital_remittances.verified.sum(:collected_amount_cents)

    fund.capital_commitments.each do |cc|
      # Commitment rollups
      puts "Checking rollups for commitment #{cc}"
      cc.collected_amount_cents.should == cc.capital_remittances.verified.sum(:collected_amount_cents)
      cc.folio_collected_amount_cents.should == cc.capital_remittances.verified.sum(:folio_collected_amount_cents)
      cc.call_amount_cents.should == cc.capital_remittances.sum(:call_amount_cents)
      cc.folio_call_amount_cents.should == cc.capital_remittances.sum(:folio_call_amount_cents)

      # KYC rollups
      folio_remittances = CapitalRemittance.where(folio_id: cc.folio_id)
      if cc.investor_kyc
        puts "Checking rollups for KYC #{cc.investor_kyc}"
        cc.investor_kyc.call_amount_cents.should == folio_remittances.sum(:call_amount_cents)
        cc.investor_kyc.collected_amount_cents.should == folio_remittances.verified.sum(:collected_amount_cents)
        cc.investor_kyc.folio_collected_amount_cents.should == folio_remittances.verified.sum(:folio_collected_amount_cents)
        cc.investor_kyc.other_fee_cents.should == folio_remittances.sum(:other_fee_cents)
      end
    end
  end
end


Given('the fund has capital commitments from each investor') do
  @entity.investors.each do |inv|
    if inv.investor_entity.entity_type != "Investor Advisor" # IAs cannot have commitments
      cc = FactoryBot.create(:capital_commitment, fund: @fund, investor: inv, esign_emails: "emp1@gmail.com,emp2@gmail.com")
      puts "\n####CapitalCommitment####\n"
      puts cc.to_json
    end
  end

  @fund.reload
end

Given('the fund has Fund Unit Settings') do
  @fund.unit_types.split(",").each do |unit_type|
    fus = FactoryBot.create(:fund_unit_setting, fund: @fund, name: unit_type.strip, entity_id: @fund.entity_id)
    puts "\n####FundUnitSetting####\n"
    puts fus.to_json
  end
end


Given('the fund has Fund Units') do
  @fund.capital_commitments.each do |cc|
    fu = FactoryBot.create(:fund_unit, capital_commitment: cc, fund_id: cc.fund_id, entity_id: @fund.entity_id, investor_id: cc.investor_id)
    puts "\n####FundUnit####\n"
    puts fu.to_json
  end
end


Given('the fund has {string} Fund Formulas') do |count|
  (1..count.to_i).each do |i|
    ff = FactoryBot.create(:fund_formula, fund: @fund, entity_id: @fund.entity_id)
    puts "\n####FundFormula####\n"
    puts ff.to_json
  end
end





Given('the fund has {string} Fund Ratios') do |count|
  (1..count.to_i).each do |i|
    fr = FactoryBot.create(:fund_ratio, fund: @fund, entity_id: @fund.entity_id)
    puts "\n####FundRatio####\n"
    puts fr.to_json
  end
end








Given('the fund has {string} capital call') do |count|
  (1..count.to_i).each do |i|
    cc = FactoryBot.build(:capital_call, fund: @fund)
    CapitalCallCreate.wtf?(capital_call: cc)
    puts "\n####CapitalCall####\n"
    puts cc.to_json
  end

  @fund.reload
end



Given('the capital calls are approved') do
  @fund.capital_calls.each do |cc|
    cc.approved = true
    cc.approved_by_user = @user
    CapitalCallUpdate.wtf?(capital_call: cc)
  end
end


Given('the remittance have a document {string} from {string} attached') do |name, path|
  CapitalRemittance.all.each do |remittance|
    Document.create(entity_id: remittance.entity_id, owner: remittance, name: name, file: File.open(path, "rb"), user_id: @user.id)
  end
end


Given('the fund has {string} capital distribution') do |count|
  (1..count.to_i).each do |i|
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
  #sleep((1)
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

Then('I should see the capital distrbution details') do
  find(".show_details_link").click

  expect(page).to have_content(@capital_distribution.title)
  expect(page).to have_content(money_to_currency(@capital_distribution.gross_amount))
  expect(page).to have_content(money_to_currency(@capital_distribution.reinvestment))
  expect(page).to have_content(money_to_currency(@capital_distribution.income))
  expect(page).to have_content(@capital_distribution.distribution_date.strftime("%d/%m/%Y"))

  @new_capital_distribution = CapitalDistribution.last
  @new_capital_distribution.approved.should == false
  @new_capital_distribution.distribution_amount_cents.should == @new_capital_distribution.capital_distribution_payments.sum(:net_payable_cents)
  @new_capital_distribution.completed_distribution_amount_cents.should == 0
  # @new_capital_distribution.capital_distribution_payments.length.should == 0

  @capital_distribution = @new_capital_distribution
end

Then('when the capital call is approved') do
  @capital_call.approved = true
  @capital_call.approved_by_user = @user
  result = CapitalCallApprove.wtf?(capital_call: @capital_call)
  puts result
  result.success?.should == true
  #sleep((1)
  @capital_call.reload
end


Then('when the capital distrbution is approved') do
  @capital_distribution.approved = true
  @capital_distribution.approved_by_user = @user
  @capital_distribution.save
  #sleep((1)
  @capital_distribution.reload
end

Then('I should see the capital distrbution payments generated correctly') do
  puts "### payments length = #{@capital_distribution.capital_distribution_payments.length}"
  @capital_distribution.capital_distribution_payments.length.should == @fund.capital_commitments.length
  @fund.capital_commitments.each do |cc|
    cdp = @capital_distribution.capital_distribution_payments.where(investor_id: cc.investor_id).first
    cdp.completed.should == false
    cdp.income_cents.should == cc.percentage *  @capital_distribution.income_cents / 100
  end
end

Then('I should be able to see the capital distrbution payments') do
  visit(capital_distribution_path(@capital_distribution, tab: "payments-tab"))
  @capital_distribution.capital_distribution_payments.includes(:investor).each do |p|
    within "#capital_distribution_payment_#{p.id}" do
      expect(page).to have_content(p.investor.investor_name)
      expect(page).to have_content(money_to_currency(p.gross_payable))
      expect(page).to have_content(money_to_currency(p.net_payable))
      expect(page).to have_content(p.payment_date.strftime("%d/%m/%Y"))
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

Then('the capital distribution must reflect the payments') do
  @capital_distribution.reload
  @capital_distribution.distribution_amount_cents.should == @capital_distribution.capital_distribution_payments.sum(:net_payable_cents)
  @capital_distribution.fund.distribution_amount_cents.should == @capital_distribution.capital_distribution_payments.sum(:net_payable_cents)
end

Then('the investors must receive email with subject {string} with the document {string} attached') do |subject, document_name|
  #sleep((2)
  Investor.all.each do |inv|
    if inv.emails.present?
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
        if document_name.present?
          puts "Checking for attachment #{document_name} for #{email}"
          attachment_filenames = current_email.attachments.map(&:filename)
          expect(attachment_filenames.select{ |filename| filename.include?(document_name) || filename.downcase.include?(document_name.downcase)}).to be_present, "Expected attachment #{document_name}, but got #{attachment_filenames.inspect}"
        end

      end
    end
  end
end


Given('Given I upload {string} file for {string} of the fund') do |file, tab|

  @import_file = file
  visit(fund_path(@fund))
  click_on(tab)
  #sleep((0.5)
  if page.has_button?("Upload / Download")
    click_on("Upload / Download")
    click_on("Upload")
  else
    click_on("Upload")
  end

  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(2)
  click_on("Save")
  # sleep(2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # binding.pry if ImportUpload.last.failed_row_count > 0
  ImportUpload.last.failed_row_count.should == 0
end

Then('Given I upload {string} file for Call remittances of the fund') do |file|
  visit(capital_call_path(@capital_call))
  click_on("Remittances")
  #sleep((2)
  click_on("Upload / Download")
  click_on("Upload Remittances")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/capital_remittances.xlsx"), make_visible: true)
  #sleep((2)
  click_on("Save")
  # sleep(2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} capital commitments created') do |count|
  @fund.capital_commitments.count.should == count.to_i
end

Then('the import upload must be updated correctly for capital commitments') do
  @import_upload = ImportUpload.last
  @import_upload.failed_row_count.should == 0
  @import_upload.processed_row_count.should == @fund.capital_commitments.count
  @import_upload.total_rows_count.should == @fund.capital_commitments.count
  @import_upload.status.should == nil
  @import_upload.import_type.should == "CapitalCommitment"
end

Then('the capital commitments must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_commitments = @fund.capital_commitments.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row


    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_commitments[idx-1]
    puts "Checking import of #{cc.investor.investor_name}"
    cc.investor.investor_name.should == user_data["Investor"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.commitment_date.should == Date.parse(user_data["Commitment Date"].to_s)
    cc.folio_currency.should == user_data["Folio Currency"]
    cc.folio_committed_amount_cents.should == user_data["Committed Amount (Folio Currency)"].to_i * 100
    cc.committed_amount_cents.should == user_data["Committed Amount (Fund Currency)"].to_i * 100 if user_data["Committed Amount (Fund Currency)"].present?
    cc.folio_id.should == user_data["Folio No"].to_s
    cc.esign_emails.should == user_data["Investor Signatory Emails"]
    cc.import_upload_id.should == ImportUpload.last.id
    exchange_rate = cc.get_exchange_rate(cc.folio_currency, cc.fund.currency, cc.commitment_date)
    puts "Using exchange_rate #{exchange_rate}"
    committed = cc.foreign_currency? ? (cc.folio_committed_amount_cents * exchange_rate.rate) : cc.folio_committed_amount_cents
    binding.pry if cc.committed_amount_cents != committed
    cc.committed_amount_cents.should == committed
  end
end


Then('There should be {string} capital calls created') do |count|
  @fund.capital_calls.count.should == count.to_i
end

Then('the capital calls must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_calls = @fund.capital_calls.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_calls[idx-1]
    puts "Checking import of #{cc.name}"
    cc.name.should == user_data["Name"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.close_percentages["First Close"] == user_data["Percentage Called"].to_d
    cc.due_date.should == user_data["Due Date"]
    user_data["Unit Price/Premium"].split(",").each do |unit_price|
      puts "Checking unit price #{unit_price}"
      unit_type, price, premium = unit_price.split(":")
      cc.unit_prices[unit_type.strip]["price"].should == price
      cc.unit_prices[unit_type.strip]["premium"].should == premium
    end
    cc.import_upload_id.should == ImportUpload.last.id
  end
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
    cc = capital_distributions[idx-1]
    puts "Checking import of #{cc.title}"
    cc.title.should == user_data["Title"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.income_cents.should == user_data["Income"].to_i * 100
    cc.reinvestment_cents.should == user_data["Reinvestment"].to_i * 100
    cc.distribution_date.should == user_data["Date"]
    cc.gross_amount_cents.round(0).should == (cc.income_cents + cc.reinvestment_cents + cc.cost_of_investment_cents - cc.reinvestment_cents).round(0)
    cc.import_upload_id.should == ImportUpload.last.id
  end
end

Then('the capital commitments must have the percentages updated') do
  puts "### Checking capital commitments percentages"
  ap CapitalCommitment.all.pluck(:id, :percentage)
  CapitalCommitment.where(percentage: 0).count.should == 0
end

Then('the fund must have the counter caches updated') do

  @fund.reload
  @fund.collected_amount_cents.should == CapitalCommitment.sum(:collected_amount_cents)
  @fund.committed_amount_cents.should == CapitalCommitment.sum(:committed_amount_cents)
end


Then('the remittances are generated for the capital calls') do
  Fund.all.each do |fund|
    fund.capital_calls.each do |cc|

      commitments = fund.capital_commitments
      puts "Checking remittances for #{cc.name} #{commitments.count} #{cc.capital_remittances.count}"
      cc.capital_remittances.count.should == commitments.count
      cc.capital_remittances.sum(:call_amount_cents).should == cc.call_amount_cents
      cc.capital_remittances.verified.sum(:collected_amount_cents).should == cc.collected_amount_cents
      # Ensure status are set correctly post the import
      cc.capital_remittances.each do |cr|
        cr.status.should == cr.set_status if cr.verified
      end
    end
  end
end

Then('the payments are generated for the capital distrbutions') do
  Fund.all.each do |fund|
    fund.capital_distributions.each do |cc|
      # puts cc.capital_distribution_payments.to_json
      capital_distribution_payments_count = fund.capital_commitments.count
      cc.capital_distribution_payments.count.should == capital_distribution_payments_count
      cc.capital_distribution_payments.sum(:income_cents).round(0).should == cc.income_cents.round(0)
    end
  end
end


Then('the capital commitments are updated with remittance numbers') do
  CapitalCommitment.all.each do |cc|
    cc.reload
    cc.call_amount_cents.should == cc.capital_remittances.sum(:call_amount_cents)
    cc.collected_amount_cents.should == cc.capital_remittances.verified.sum(:collected_amount_cents)
    cc.folio_collected_amount_cents.should == cc.capital_remittances.verified.sum(:folio_collected_amount_cents)
    cc.folio_call_amount_cents.should == cc.capital_remittances.sum(:folio_call_amount_cents)
  end
end

Then('the funds are updated with remittance numbers') do
  Fund.all.each do |f|
    f.reload
    f.call_amount_cents.should == f.capital_remittances.sum(:call_amount_cents)
    f.collected_amount_cents.should == f.capital_remittances.verified.sum(:collected_amount_cents)
  end
end


Then('if the last remittance payment is deleted') do
  CapitalRemittancePayment.last&.destroy
end

Then('if the first remittance is deleted') do
  CapitalRemittance.first&.destroy
end


Given('my firm is an investor in the fund') do
  @investor = FactoryBot.create(:investor, entity: @fund.entity, investor_entity: @user.entity)
  puts "\n####Fund Investor####\n"
  puts @investor.to_json

  ar = AccessRight.create!( owner: @fund, access_type: "Fund",
      access_to_investor_id: @investor.id, entity: @fund.entity)


  ia = InvestorAccess.create!(entity: @investor.entity, investor: @investor,
        first_name: @user.first_name, last_name: @user.last_name,
        email: @user.email, granter: @user, approved: true )

  puts "\n####Granted Access####\n"
  puts ar.to_json

  @fund.reload
end

Then('I should be able to see my investor kycs') do
  @user.reload

  visible_kycs = []
  invisible_kycs = []
  InvestorKyc.all.includes(:investor).each do |kyc|
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

  puts "Visible KYC: #{visible_kycs.map{|k| k.investor.investor_name}} for User #{@user.email}"
  puts "Invisible KYC: #{invisible_kycs.map{|k| k.investor.investor_name}} for User #{@user.email}"

end

Then('I should be able to see my capital commitments') do
  @user.reload
  click_on("Commitments")


  within("#capital_commitments") do
    CapitalCommitment.all.each do |cc|

      @investor = cc.entity.investors.joins(:investor_accesses).where("investor_accesses.user_id=?", @user.id).first

      puts "checking capital commitment for #{cc.investor.investor_name} against #{@investor.investor_name}"

      if cc.investor_id == @investor.id
        puts "Commitment Visible"
        expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
        # expect(page).to have_content(cc.fund.name)
        expect(page).to have_content( money_to_currency(cc.committed_amount) )
      else
        puts "Commitment Not Visible"
        expect(page).not_to have_content(cc.investor.investor_name)
      end
    end
  end
end

Then('I should be able to see my capital remittances') do
  click_on("Calls")
  CapitalRemittance.all.each do |cc|
    puts "checking capital remittance for #{cc.investor.investor_name} against #{@investor.investor_name} "
    if cc.investor_id == @investor.id
      puts "Call Visible"
      expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
      expect(page).to have_content( money_to_currency(cc.due_amount) )
      expect(page).to have_content( money_to_currency(cc.collected_amount) )
    else
      puts "Call Not Visible"
      expect(page).not_to have_content(cc.investor.investor_name)
    end
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
  CapitalDistributionPayment.all.each do |cc|
    puts "checking capital distrbution payment for #{cc.investor.investor_name} against #{@investor.investor_name} "
    if cc.investor_id == @investor.id
      puts "Distribution Visible"
      expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
      expect(page).to have_content( money_to_currency(cc.net_payable) )
      expect(page).to have_content( money_to_currency(cc.gross_payable) )
      expect(page).to have_content( cc.payment_date.strftime("%d/%m/%Y") )
    else
      puts "Distribution Not Visible"
      expect(page).not_to have_content(cc.investor.investor_name)
    end
  end
end

Then('all the investor advisors should be able to receive notifications for the folios they represent') do
  InvestorAdvisor.all.each do |investor_advisor|
    visible_kycs = []
    invisible_kycs = []

    puts "Checking notifications for Investor Advisor #{investor_advisor.email}"
    # For each investor access, check if the advisor is notified for each capital commitment
    InvestorAccess.approved.where(email: investor_advisor.email).all.each do |investor_access|
      investor = investor_access.investor
      puts "Checking commitments"
      investor.capital_commitments.each do |cc|
        investor.notification_users(cc).pluck(:email).include?(investor_advisor.email).should == true
      end

      puts "Checking remittances"
      investor.capital_remittances.each do |cr|
        investor.notification_users(cr).pluck(:email).include?(investor_advisor.email).should == true
      end

      puts "Checking distributions"
      investor.capital_distribution_payments.each do |cdp|
        investor.notification_users(cdp).pluck(:email).include?(investor_advisor.email).should == true
      end


      investor.investor_kycs.each do |kyc|
        if Pundit.policy(investor_advisor.user, kyc).show?(across_all_entities: true)
          puts "Checking KYC notifications true"
          kyc.notification_users.pluck(:email).include?(investor_advisor.email).should == true
          visible_kycs << kyc
        else
          puts "Checking KYC notifications false"
          kyc.notification_users.pluck(:email).include?(investor_advisor.email).should == false
          invisible_kycs << kyc
        end
      end
    end

    puts "Visible KYC: #{visible_kycs.map{|k| k.investor.investor_name}} for Investor Advisor #{investor_advisor.email}"
    puts "Invisible KYC: #{invisible_kycs.map{|k| k.investor.investor_name}} for Investor Advisor #{investor_advisor.email}"

  end
end


Then('all the investor advisors should be able to switch to the investors they represent and view their details') do
  InvestorAdvisor.all.each do |investor_advisor|
    puts "Switching to Investor Advisor #{investor_advisor.email} for entity #{investor_advisor.entity.name}"
    investor_advisor.switch(investor_advisor.user)
    investor_advisor.user.reload

    CapitalCommitment.all.each do |cc|
      if Pundit.policy(investor_advisor.user, cc).show?
        # All capital commitments should belong to the investor advisor's entity
        cc.investor.investor_entity_id.should == investor_advisor.entity.id
        puts "Capital Commitment #{cc.investor.investor_name}, #{cc.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      if cc.investor.investor_entity_id != investor_advisor.entity.id
        # If the capital commitment does not belong to the investor advisor's entity, it should not be visible
        Pundit.policy(investor_advisor.user, cc).show?.should == false
        puts "Capital Commitment #{cc.investor.investor_name}, #{cc.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
    end

    CapitalRemittance.all.each do |cr|
      if Pundit.policy(investor_advisor.user, cr).show?
        # All capital remittances should belong to the investor advisor's entity
        cr.investor.investor_entity_id.should == investor_advisor.entity.id
        puts "Capital Remittance #{cr.investor.investor_name}, #{cr.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      if cr.investor.investor_entity_id != investor_advisor.entity.id
        # If the capital remittance does not belong to the investor advisor's entity, it should not be visible
        Pundit.policy(investor_advisor.user, cr).show?.should == false
        puts "Capital Remittance #{cr.investor.investor_name}, #{cr.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
    end

    CapitalDistributionPayment.all.each do |cdp|
      if Pundit.policy(investor_advisor.user, cdp).show?
        # All capital distribution payments should belong to the investor advisor's entity
        cdp.investor.investor_entity_id.should == investor_advisor.entity.id
        puts "Capital Distribution Payment #{cdp.investor.investor_name}, #{cdp.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      if cdp.investor.investor_entity_id != investor_advisor.entity.id
        # If the capital distribution payment does not belong to the investor advisor's entity, it should not be visible
        Pundit.policy(investor_advisor.user, cdp).show?.should == false
        puts "Capital Distribution Payment #{cdp.investor.investor_name}, #{cdp.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
    end

    InvestorKyc.all.each do |kyc|
      if Pundit.policy(investor_advisor.user, kyc).show?(across_all_entities: false)
        # All investor KYC should belong to the investor advisor's entity
        kyc.investor.investor_entity_id.should == investor_advisor.entity.id
        puts "Investor KYC #{kyc.investor.investor_name}, #{kyc.investor.investor_entity.name} visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
      if kyc.investor.investor_entity_id != investor_advisor.entity.id
        # If the investor KYC does not belong to the investor advisor's entity, it should not be visible
        Pundit.policy(investor_advisor.user, kyc).show?(across_all_entities: false).should == false
        puts "Investor KYC #{kyc.investor.investor_name}, #{kyc.investor.investor_entity.name} NOT visble to #{investor_advisor.email}, #{investor_advisor.entity.name}"
      end
    end


  end
end



Given('the fund has capital call template') do
  @call_template = Document.create!(name: "Call Doc", owner_tag: "Call Template",
    owner: @fund, entity_id: @fund.entity_id, user: @user,
    file: File.new("public/sample_uploads/Drawdown notice format.docx", "r"))
end

Given('the fund has capital commitment template') do
  @commitment_template = Document.create!(name: "Fund Agreement", owner_tag: "Commitment Template",
    owner: @fund, entity_id: @fund.entity_id, user: @user,
    file: File.new("public/sample_uploads/Commitment Agreement Template.docx", "r"))
end

Then('the user goes to the fund e-signature report') do
  @template_dup = @commitment_template.dup
  @template_dup.assign_attributes(sent_for_esign: true, owner: @fund.capital_commitments.last )
  @template_dup.save!
  ESignature.create!(user: @user, entity: @fund.entity, document: @template_dup, status: "failed")
  visit(fund_path(@fund))
  click_on("Reports")
  sleep(0.5)
  find("#basic_reports").hover
  sleep(0.5)
  click_on("eSignatures Report")
  #sleep((2)
end

Then('the user should see all esign report for all docs sent for esign') do
  esign = ESignature.last
  doc = esign.document
  expect(page).to have_content(doc.name)
  expect(page).to have_content(doc.owner_tag)
end

Then('when the capital commitment docs are generated') do
  CapitalCommitment.all.each do |cc|
    visit(capital_commitment_path(cc))
    find("#commitment_actions").click
    click_on("Generate All Documents")
    #sleep((1)
    click_on("Proceed")
    expect(page).to have_content("Documentation generation started")
    sleep(8)
    # expect(page).to have_content("generated successfully")
  end
end

Then('the generated doc must be attached to the capital commitments') do
  CapitalCommitment.all.each do |cc|
    cc.documents.where(name: "#{@commitment_template.name} - #{cc}", owner_tag: "Generated").count.should == 1
    visit(capital_commitment_path(cc))
    expect(page).to have_content(@commitment_template.name)
    expect(page).to have_content("Generated")
  end
end

Then('when the capital call docs are generated') do
  CapitalCall.all.each do |cc|
    visit(capital_call_path(cc))
    click_on("Actions")
    click_on("Generate Documents")
    click_on("Proceed")
    # sleep(1)
    cc.capital_remittances.each_with_index do |cr, count|
      sleep(4)
      expect(page).to have_content("#{count + 1}: Generated #{@call_template.name} for #{cr}")
    end
    expect(page).to have_content("generated successfully")
  end
end

Then('the generated doc must be attached to the capital remittances') do
  CapitalRemittance.all.each do |cc|
    cc.documents.where(name: @call_template.name).count.should == 1
    visit(capital_remittance_path(cc))
    within("#remittance_details") do
      click_on("Documents")
      expect(page).to have_content(@call_template.name)
      expect(page).to have_content("Generated")
    end
  end
end


Given('each investor has a {string} kyc') do |status|
  verified = status == "verified"
  Investor.all.each do |inv|
    kyc = FactoryBot.create(:investor_kyc, investor: inv, entity: @fund.entity, verified:)
  end
end


Given('each investor has a {string} kyc linked to the commitment') do |status|
  verified = status == "verified"
  Investor.all.each do |inv|
    kyc = FactoryBot.build(:investor_kyc, investor: inv, entity: @fund.entity, verified:)
    kyc.save(validate: false)
    @fund.capital_commitments.where(investor_id: inv.id).update(investor_kyc_id: kyc.id)
  end
end


When('the fund document details must be setup right') do
  @fund.data_room_folder.name.should == "Data Room"
  @fund.data_room_folder.owner.should == @fund

  @document.owner.should == @fund
  @document.folder.name.should == "Data Room"
  @document.folder.full_path.should == "/Funds/#{@fund.name}/Data Room"
end

When('I visit the fund details page') do
  visit(fund_path(@fund))
end

When('I click on fund documents tab') do
  #sleep((1)
  find("#documents_tab").click()
end

Given('the remittances are paid and verified') do
  CapitalRemittance.all.each do |cr|
    cr.update(folio_collected_amount_cents: cr.folio_call_amount_cents, collected_amount_cents: cr.call_amount_cents, verified: true)
  end
end

Given('the remittances are overpaid and verified') do
  CapitalRemittance.all.each do |cr|
    cr.update(folio_collected_amount_cents: cr.folio_call_amount_cents + 1000, collected_amount_cents: cr.call_amount_cents + 1000, verified: true)
  end
end


Given('the units are generated') do
  puts "### Generating units"
  puts "Before: FundUnit.count = #{FundUnit.count}, #{FundUnit.all.pluck(:id, :owner_id, :owner_type, :quantity, :unit_type, :price_cents)}"
  CapitalCall.all.each do |cc|
    FundUnitsJob.perform_now(cc.id, "CapitalCall", "Allocation for collected call amount", User.first.id)
  end
  CapitalDistribution.all.each do |cc|
    FundUnitsJob.perform_now(cc.id, "CapitalDistribution", "Redemption for distribution", User.first.id)
  end
  puts "After: FundUnit.count = #{FundUnit.count}, #{FundUnit.all.pluck(:id, :owner_id, :owner_type, :quantity, :unit_type, :price_cents)}"
end

Then('there should be correct units for the calls payment for each investor') do
  FundUnit.count.should == CapitalCommitment.count * CapitalCall.count
  CapitalCommitment.all.each do |cc|
    puts "Checking units for #{cc}"
    cc.fund_units.length.should > 0
    cc.fund_units.each do |fu|
      ap fu
      fu.unit_type.should == cc.unit_type
      fu.owner_type.should == "CapitalRemittance"

      capital_remittance = fu.owner
      fu.price_cents.should == fu.owner.capital_call.unit_prices[fu.unit_type]["price"].to_d * 100.0

      if capital_remittance.collected_amount_cents >= capital_remittance.call_amount_cents
        amount_cents = capital_remittance.call_amount_cents # - capital_remittance.allocated_unit_amount_cents
      else
        amount_cents = capital_remittance.collected_amount_cents # - capital_remittance.allocated_unit_amount_cents
      end

      fu.amount_cents.should == amount_cents
      fu.quantity.round(2).should == ( amount_cents / (fu.price_cents + fu.premium_cents)).round(2)
    end
  end
end

Then('the corresponding distribution payments should be created') do
  CapitalDistributionPayment.count.should == CapitalCommitment.count
  CapitalDistributionPayment.all.each do |cdp|
    cdp.investor_id.should == cdp.capital_commitment.investor_id
    cdp.income_cents.should == (@capital_distribution.income_cents * cdp.capital_commitment.percentage / 100)
    cdp.folio_id.should == cdp.capital_commitment.folio_id
    cdp.capital_distribution_id.should == @capital_distribution.id
    cdp.investor_name.should == cdp.capital_commitment.investor_name
  end
end

Then('I should see the distribution payments') do
  visit(capital_distribution_path(@capital_distribution))
  CapitalDistributionPayment.all.each do |cdp|
    within("#capital_distribution_payment_#{cdp.id}") do
      expect(page).to have_content(cdp.investor_name)
      expect(page).to have_content(cdp.folio_id)
      expect(page).to have_content(money_to_currency(cdp.gross_payable))
      expect(page).to have_content(money_to_currency(cdp.net_payable))
      # expect(page).to have_content(money_to_currency(cdp.cost_of_investment))
      expect(page).to have_content(cdp.payment_date.strftime("%d/%m/%Y"))
      # expect(page).to have_content(money_to_currency(cdp.reinvestment))
      expect(page).to have_content(cdp.completed ? "Yes" : "No")
    end
  end
end

Given('the distribution payments are completed') do
  puts CapitalDistributionPayment.all.to_json

  CapitalDistributionPayment.all.each do |cdp|
    cdp.completed = true
    CapitalDistributionPaymentUpdate.wtf?(capital_distribution_payment: cdp).success?.should == true
  end
end

Given('Capital Distribution Payment Notification is sent') do
  CapitalDistributionPaymentNotifier::Notification.count.should == CapitalDistributionPayment.count
end

Then('there should be correct units for the distribution payments for each investor') do
  CapitalCommitment.all.each do |cc|
    puts "Checking units for #{cc}"
    cc.fund_units.length.should > 0
    cc.fund_units.each do |fu|
      ap fu
      fu.unit_type.should == cc.unit_type
      fu.owner_type.should == "CapitalDistributionPayment"
      fu.price_cents == fu.owner.capital_distribution.unit_prices[fu.unit_type].to_d * 100
      fu.quantity.should == -(fu.owner.cost_of_investment_cents / (fu.price_cents))
    end
  end
end


Then('Given I upload {string} file for Account Entries') do |file|
  @import_file = file
  visit(capital_commitment_path(@fund.capital_commitments.first))
  click_on("Account Entries")
  #sleep((1)
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((1)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  # sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(4)
  # binding.pry if ImportUpload.last.failed_row_count > 0
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} account_entries created') do |count|
  AccountEntry.count.should == count.to_i
end

Given('Given I upload {string} {string} error file for Account Entries') do |file, err_count|
  @import_file = file
  visit(capital_commitment_path(@fund.capital_commitments.first))
  click_on("Account Entries")
  #sleep((1)
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == err_count.to_i
end

Then('I should see that the duplicate account entries are not uploaded') do
  # last 5 account entries are duped
  file = ImportUpload.last.import_results.download
  data = Roo::Spreadsheet.open(file.path)
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
  # data from 21st row should have error "Duplicate, already present"
  data.each_with_index do |row, idx|
    next if idx < 21 # skip rows
    # column after headers should have error "Duplicate, already present"
    row[headers.length].include?("Duplicate Account Entry").should == true
  end
end

Then('the account_entries must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    account_entries = @fund.account_entries.order(id: :asc).to_a
    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h
      ap user_data
      cc = account_entries[idx-1]
      ap cc

      puts "Checking import of #{cc.name}"
      cc.name.should == user_data["Name"].strip
      cc.fund.name.should == user_data["Fund"]
      cc.investor.investor_name.should == user_data["Investor"]
      cc.folio_id.should == user_data["Folio No"].to_s
      cc.amount_cents.should == user_data["Amount (Fund Currency)"].to_f * 100
      cc.folio_amount_cents.should == user_data["Amount (Folio Currency)"].to_f * 100 if user_data["Amount (Folio Currency)"].present?
      cc.entry_type.should == user_data["Entry Type"]
      cc.reporting_date.should == user_data["Reporting Date"]
      cc.notes.should == user_data["Notes"]
      cc.import_upload_id.should == ImportUpload.where(import_type: "AccountEntry").last.id
    end

end


Then('the account_entries must visible for each commitment') do
  @fund.account_entries.each do |ae|
    visit(capital_commitment_path(ae.capital_commitment))
    click_on "Account Entries"
    expect(page).to have_content(ae.name)
    expect(page).to have_content(ae.entry_type)
    if ae.name.include?("Percentage")
      expect(page).to have_content("#{ae.amount_cents} %")
    else
      expect(page).to have_content(money_to_currency(ae.amount, {}))
    end
    expect(page).to have_content(ae.capital_commitment.folio_id)
    expect(page).to have_content(ae.reporting_date.strftime("%d/%m/%Y"))
  end
end


Then('Given I upload {string} file for the remittances of the capital call') do |file|
  @import_file = file
  visit(capital_call_path(@fund.capital_calls.first))
  click_on("Remittances")
  #sleep((2)
  click_on("Upload / Download")
  click_on("Upload Payments")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep((2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  # binding.pry if ImportUpload.last.failed_row_count > 0
  # ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} remittance payments created') do |count|
  CapitalRemittancePayment.count.should == count.to_i
end

Then('the capital remittance payments must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    capital_remittance_payments = @fund.capital_remittance_payments.order(id: :asc).to_a
    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h

      cc = capital_remittance_payments[idx-1]

      cc.fund.name.should == user_data["Fund"]
      cc.capital_remittance.investor.investor_name.should == user_data["Investor"]
      cc.capital_remittance.folio_id.should == user_data["Folio No"].to_s
      cc.folio_amount_cents.should == user_data["Amount (Folio Currency)"].to_i * 100

      capital_commitment = cc.capital_remittance.capital_commitment
      capital_commitment.folio_currency.should == user_data["Currency"]

      if user_data["Amount (Fund Currency)"].present?
        cc.amount_cents.should == user_data["Amount (Fund Currency)"].to_i * 100
      else
        amount = capital_commitment.foreign_currency? ? (cc.folio_amount_cents * capital_commitment.get_exchange_rate(capital_commitment.folio_currency, cc.fund.currency, cc.payment_date).rate) : cc.amount_cents
        cc.amount_cents.should == amount
      end


      cc.reference_no.should == user_data["Reference No"].to_s
      cc.payment_date.should == user_data["Payment Date"]
      cc.import_upload_id.should == ImportUpload.last.id


      # sleep(30)
    end
end



Then('when the exchange rate changes') do
  foreign_currencies = @fund.capital_commitments.joins(:fund).where("folio_currency != funds.currency").all.pluck(:folio_currency).uniq
  foreign_currencies.each do |fc|
    # Change the exchange rate for the foreign_currencies randomly
    exchange_rate = ExchangeRate.where(from: fc, to: @fund.currency, latest: true).last.dup
    exchange_rate.rate += (rand(10) - rand(10) + 0.1)
    exchange_rate.save
  end
end

Then('the commitment amounts change correctly') do
  @fund.reload
  @fund.capital_commitments.each do |cc|
    cc.committed_amount_cents.should == cc.orig_committed_amount_cents + cc.adjustment_amount_cents
  end
end

Given('the last investor has a user {string}') do |args|
  cr = CapitalRemittance.first
  investor = cr.investor
  user = FactoryBot.create(:user,entity: investor.investor_entity, whatsapp_enabled: true)
  user1 = FactoryBot.create(:user,entity: investor.investor_entity)
  user2 = FactoryBot.create(:user,entity: investor.investor_entity, phone:"321")

  key_values(user,args)
  user.save!

  [user, user1].each do |u|
    user.add_role :investor_advisor
    AccessRight.create(entity_id: investor.investor_entity_id, owner: @fund, access_to_investor_id: investor.id,metadata: "Investor", user_id: u.id)
    ia = InvestorAccess.create(entity: investor.entity, investor: investor,
        first_name: u.first_name, last_name: u.last_name,
        email: u.email, granter: u, approved: true)
    ia.update_columns(approved: true)
  end
end

Given('the capital remittance whatsapp notification is sent to the first investor') do
  cr = CapitalRemittance.first
  cc = cr.capital_call
  cc.update_columns(approved:true, manual_generation: false)
  @resjob = cr.send_notification
end


Given('the fund has fund ratios') do
    FundRatiosJob.perform_now(@fund.id, nil, Time.zone.now + 2.days, @user.id, true, return_cash_flows: true)
end


Given('Given I upload a fund unit settings {string} for the fund') do |file_name|
  visit(fund_url(@fund))
  click_on("Actions")
  click_on("Fund Unit Settings")
  sleep(1)
  click_on("Upload")
  #sleep((6)
  fill_in('import_upload_name', with: "Test Fund Unit Settings Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} fund unit settings created with data in {string}') do |count, file_name|
  FundUnitSetting.all.count.should == count.to_i

  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
  custom_field_headers = headers - ImportFundUnitSetting::STANDARD_HEADERS
  fund_unit_settings = FundUnitSetting.all.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    fus = fund_unit_settings[idx-1]
    puts "Checking import of #{fus.to_json}"

    fus.fund_id.should == Fund.find_by(name: row_data["Fund"]).id
    fus.name.should == row_data["Class/Series"]
    fus.management_fee.should == row_data["Management Fee %"]
    fus.setup_fee.should == row_data["Setup Fee %"]
    fus.gp_units.should == row_data["Gp Units"].strip.casecmp?("Yes")
    fus.carry.should == row_data["Carry %"]
    fus.isin.should == row_data["Isin"]

    # Check that the custom fields got imported
    custom_field_headers.each do |cf_header|
      puts "Checking custom field #{cf_header}"
      cf_name = FormCustomField.to_name(cf_header)
      fus.custom_fields[cf_name].to_s.should == row_data[cf_header].to_s.strip

      fcf = FormCustomField.where(name: cf_name).first
      puts "Checking custom field #{fcf.name}"
      fcf.should be_present
    end

  end
end



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


Then('Given I upload {string} file for Distributions of the fund') do |string|
  visit(capital_distributions_url)
  #sleep((2)
  click_on("Upload")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Distributions Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/capital_distributions.xlsx'), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('Given I upload {string} file for Fund Units of the fund') do |file_name|
  visit(fund_units_url)
  #sleep((2)
  click_on("Upload")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Fund Units Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == 0
  # status is nil when no errors
  expect(ImportUpload.last.status.nil?).to be_truthy
end

Then('There should be {string} fund units created with data in the sheet') do |count|
  file = File.open("./public/sample_uploads/fund_units.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_commitment = CapitalCommitment.where(folio_id: row_data["Folio No"]).first

    fund_unit = FundUnit.where(capital_commitment_id: capital_commitment.id, quantity: row_data["Quantity"].to_f).first

    puts "Checking import of #{fund_unit.to_json}"

    fund_unit.quantity.should == row_data["Quantity"].to_f
    fund_unit.unit_type.should == row_data["Unit Type"]
    fund_unit.price_cents.should == row_data["Price"].to_f * 100.0
    fund_unit.premium_cents.should == row_data["Premium"].to_f * 100.0
    fund_unit.issue_date.should == row_data["Issue Date"]
    fund_unit.reason.should == row_data["Reason"]
    fund_unit.owner.folio_id.should == row_data["Folio No"].to_s

    if fund_unit.quantity.positive?
      fund_unit.owner_type.should == "CapitalRemittance"
    else
      fund_unit.owner_type.should == "CapitalDistributionPayment"
    end
  end
end

Then('Given I upload {string} file for the Distribution Payments of the fund') do |file_name|
  visit(new_import_upload_path("import_upload[entity_id]": @fund.entity_id, "import_upload[import_type]": "CapitalDistributionPayment"))
  #sleep((2)
  fill_in('import_upload_name', with: "Test CDP Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == 0
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
    investor = Investor.where(investor_name: row_data["Investor"]).first
    cdp = CapitalDistributionPayment.where(investor:, capital_distribution:).first

    puts "Checking import of #{cdp.to_json}"

    cdp.investor_name.should == row_data["Investor"]
    cdp.income.to_d.should == row_data["Income"].to_d
    cdp.cost_of_investment.to_d.should == row_data["Face Value For Redemption"].to_d
    cdp.payment_date.should == Date.parse(row_data["Payment Date"].to_s)
    cdp.completed.should == (row_data["Completed"] == "Yes")
    cdp.income_with_fees.to_d.should == cdp.income.to_d
    cdp.cost_of_investment_with_fees.to_d.should == cdp.cost_of_investment.to_d

    cdp.net_payable_cents.should == cdp.income_cents + cdp.net_of_account_entries_cents + cdp.cost_of_investment_cents - cdp.reinvestment_with_fees_cents
    cdp.gross_payable_cents.should == cdp.income_cents + cdp.gross_of_account_entries_cents + cdp.cost_of_investment_cents
  end
end

Given('there is a custom notification for the capital call with subject {string} with email_method {string}') do |subject, email_method|
  @custom_notification = CustomNotification.create!(entity: @capital_call.entity, subject:, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_call, email_method:)
end

Given('Given the commitments have a cc {string}') do |email|
  @cc_email = email
  CapitalCommitment.all.each do |cc|
    cc.properties[:cc] = email
    cc.save
  end
end


When('the capital commitment is resaved') do
  CapitalCommitmentUpdate.wtf?(capital_commitment: @capital_commitment).success?.should == true
  @capital_commitment.reload
end



Then('when the adjustment is destroyed') do
  AdjustmentDestroy.wtf?(commitment_adjustment: @commitment_adjustment).success?.should == true
end

When('a commitment adjustment {string} is created') do |args|
  @commitment_adjustment = CommitmentAdjustment.new(entity: @entity, capital_commitment: @capital_commitment, fund: @fund, as_of: Date.today, reason: "Test Adjustment")
  key_values(@commitment_adjustment, args)
  AdjustmentCreate.wtf?(commitment_adjustment: @commitment_adjustment)
end

Then('the capital commitment should have a orig commitment amount {string}') do |orig_committed_amount|
  @capital_commitment.reload
  puts "Checking orig_committed_amount  #{@capital_commitment.orig_committed_amount}"
  @capital_commitment.orig_committed_amount.should == orig_committed_amount.to_i
end


Then('the capital commitment should have a committed amount {string}') do |committed_amount_cents|
  @capital_commitment.reload
  puts "Checking committed amount #{@capital_commitment.committed_amount}"
  @capital_commitment.committed_amount_cents.should == committed_amount_cents.to_i
end

Then('the capital commitment should have a arrears amount {string}') do |arrear_amount_cents|
  @capital_commitment.reload
  @capital_commitment.arrear_amount_cents.should == arrear_amount_cents.to_i
end

When('a commitment adjustment {string} is created for the last remittance') do |args|
  @capital_remittance = @fund.capital_remittances.last
  @commitment_adjustment = CommitmentAdjustment.new(entity: @entity, capital_commitment: @capital_commitment, fund: @fund, as_of: Date.today, reason: "Test Adjustment", owner: @capital_remittance)
  key_values(@commitment_adjustment, args)
  AdjustmentCreate.wtf?(commitment_adjustment: @commitment_adjustment)
end

Then('the last remittance should have a arrears amount {string}') do |arrear_amount_cents|
  @capital_remittance.reload
  puts @capital_remittance.to_json
  @capital_remittance.arrear_amount_cents.should == arrear_amount_cents.to_i
end


Then('a reverse remittance payment must be generated for the remittance') do
  @capital_remittance.reload
  @reverse_payment = @capital_remittance.capital_remittance_payments.last
  @reverse_payment.fund_id.should == @capital_remittance.fund_id
  @reverse_payment.amount_cents.should == @capital_remittance.arrear_amount_cents
  @reverse_payment.folio_amount_cents.should == @capital_remittance.arrear_folio_amount_cents
  @reverse_payment.amount_cents.should == @commitment_adjustment.amount_cents
  @reverse_payment.folio_amount_cents.should == @commitment_adjustment.folio_amount_cents
  @reverse_payment.payment_date.should == @commitment_adjustment.as_of
end

Then('the collected amounts must be computed properly') do
  @capital_call.reload
  @capital_remittance.reload
  @capital_commitment.reload

  @capital_call.collected_amount_cents.should == @capital_call.capital_remittances.sum(:collected_amount_cents)
  @capital_commitment.collected_amount_cents.should == @capital_commitment.capital_remittances.sum(:collected_amount_cents)
  @capital_commitment.folio_collected_amount_cents.should == @capital_commitment.capital_remittances.sum(:folio_collected_amount_cents)
end

Given('the remittances are verified') do
  CapitalRemittance.all.each do |cr|
    CapitalRemittanceVerify.wtf?(capital_remittance: cr)
  end
end

Then('the remittances have verified set to {string}') do |flag|
  CapitalRemittance.all.each do |cr|
    cr.verified.should == (flag == "true")
  end
end

Given('notification should be sent {string} to the remittance investors for {string}') do |sent, cn_args|
  cn = CustomNotification.new
  key_values(cn, cn_args)

  @capital_call.capital_remittances.each do |cr|
    user = cr.investor.investor_accesses.approved.first.user
    open_email(user.email)
    puts "Checking email for #{user.email} with email_method: #{cn.email_method}, subject: #{current_email&.subject}"
    if sent == "true"
      expect(current_email.subject).to include @capital_call.custom_notification(cn.email_method).subject
    else
      current_email.should == nil
    end
  end

end

Given('there is a custom notification {string} in place for the Call') do |args|
    @capital_call = CapitalCall.last
    @custom_notification = CustomNotification.build(entity: @entity, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_call)
    key_values(@custom_notification, args)
    @custom_notification.save!
end

Then('the imported data must have the form_type updated') do
  @import_upload = ImportUpload.last
  @import_upload.imported_data.all.each do |row|
    form_type = @import_upload.entity.form_types.where(name: row.class.name).first
    if form_type.present?
      puts "Checking form_type for #{row.class.name}"
      row.form_type_id.should == form_type.id
      form_type.form_custom_fields.each do |fcf|
        # Ensure that the data json fields are exactly the same as the form custom fields name
        puts "Checking #{fcf.name} in imported data #{row.custom_fields[fcf.name]}"
        row.custom_fields[fcf.name].should_not == nil
      end
    end
  end
end


When('fund units are transferred {string}') do |transfer|

  @fund.reload
  @price, @premium, @transfer_ratio, @transfer_account_entries, @account_entries_excluded = transfer.split(",").map{|x| x.split("=")[1]}
  @price = @price.to_f
  @premium = @premium.to_f
  @transfer_ratio = @transfer_ratio.to_f
  @transfer_account_entries = @transfer_account_entries == "true"

  @from_cc = @fund.capital_commitments.first
  @from_cc_committed_amount_cents = @from_cc.committed_amount_cents
  @from_cc_folio_committed_amount_cents = @from_cc.folio_committed_amount_cents

  @to_cc = @fund.capital_commitments.last
  @transfer_quantity = (@transfer_ratio * @from_cc.total_fund_units_quantity).to_f

  result = FundUnitTransferService.wtf?(from_commitment: @from_cc, to_commitment: @to_cc, fund: @fund, price: @price, premium: @premium, transfer_ratio: @transfer_ratio, transfer_date: Date.today, transfer_account_entries: @transfer_account_entries, account_entries_excluded: @account_entries_excluded)

  puts result[:error]
  result.success?.should == true
  @transfer_token = result[:transfer_token]
end

Then('the units should be transferred') do

  from_fu = @from_cc.fund_units.last
  to_fu = @to_cc.fund_units.last

  from_fu.quantity.should == -@transfer_quantity
  from_fu.price_cents.should == @price * 100
  from_fu.premium_cents.should == @premium * 100
  from_fu.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true
  to_fu.quantity.should == @transfer_quantity
  to_fu.price_cents.should == @price * 100
  to_fu.premium_cents.should == @premium * 100
  to_fu.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true

end


Then('the account entries are adjusted upon fund unit transfer') do

  transfer_ratio = @transfer_ratio
  retained_ratio = 1 - transfer_ratio

  @from_cc.account_entries.each do |entry|
    if entry.json_fields["transfer_id"].present?
      puts "Checking account entry for #{entry.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
      entry.json_fields["transfer_id"].should == @transfer_token
      # entry.json_fields["orig_amount"].should == entry.amount_cents / retained_ratio
      entry.amount_cents.should == (entry.json_fields["orig_amount"].to_f * retained_ratio).round
    end
  end

  @to_cc.account_entries.each do |entry|
    if entry.json_fields["transfer_id"].present?
      puts "Checking account entry for #{entry.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"
      entry.json_fields["transfer_id"].should == @transfer_token
      # entry.json_fields["orig_amount"].should == entry.amount_cents / transfer_ratio
      entry.amount_cents.should == (entry.json_fields["orig_amount"].to_f * transfer_ratio)
    end
  end
end

Then('the remittances are adjusted upon fund unit transfer') do

  transfer_ratio = @transfer_ratio
  retained_ratio = 1 - transfer_ratio

  @from_cc.capital_remittances.each do |cr|
    if cr.json_fields["transfer_id"].present?
      puts "Checking capital remittance for #{cr.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
      cr.json_fields["transfer_id"].should == @transfer_token
      # cr.json_fields["orig_call_amount"].should == cr.call_amount_cents / retained_ratio
      cr.call_amount_cents.should == (cr.json_fields["orig_call_amount"].to_f * retained_ratio).round
      # cr.json_fields["orig_collected_amount"].should == cr.collected_amount_cents / retained_ratio
      cr.collected_amount_cents.should == (cr.json_fields["orig_collected_amount"].to_f * retained_ratio).round

      cr.capital_remittance_payments.each do |crp|
        puts "Checking capital remittance payment for #{crp.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
        crp.json_fields["transfer_id"].should == @transfer_token
        # crp.json_fields["orig_amount"].should == crp.amount_cents / retained_ratio
        crp.amount_cents.should == (crp.json_fields["orig_amount"].to_f * retained_ratio).round
      end
    end
  end

  @to_cc.capital_remittances.each do |cr|
    cr.reload # Ensure the latest data is loaded from the database

    if cr.json_fields["transfer_id"].present?
      puts "Checking capital remittance for #{cr.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"

      cr.json_fields["transfer_id"].should == @transfer_token
      # cr.json_fields["orig_call_amount"].should == cr.call_amount_cents / transfer_ratio
      cr.call_amount_cents.should == (cr.json_fields["orig_call_amount"].to_f * transfer_ratio).round
      # cr.json_fields["orig_collected_amount"].should == cr.collected_amount_cents / transfer_ratio
      cr.collected_amount_cents.should == (cr.json_fields["orig_collected_amount"].to_f * transfer_ratio).round

      cr.capital_remittance_payments.each do |crp|
        puts "Checking capital remittance payment for #{crp.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"
        crp.json_fields["transfer_id"].should == @transfer_token
        # crp.json_fields["orig_amount"].should == crp.amount_cents / transfer_ratio
        crp.amount_cents.should == (crp.json_fields["orig_amount"].to_f * transfer_ratio).round
      end
    end
  end
end

Then('distributions are adjusted upon fund unit transfer') do

  transfer_ratio = @transfer_ratio
  retained_ratio = 1 - transfer_ratio

  @from_cc.capital_distribution_payments.each do |cdp|
    if cdp.json_fields["transfer_id"].present?
      puts "Checking capital distribution payment for #{cdp.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
      cdp.json_fields["transfer_id"].should == @transfer_token
      # cdp.json_fields["orig_gross_payable"].should == cdp.gross_payable_cents / retained_ratio
      cdp.gross_payable_cents.should == (cdp.json_fields["orig_gross_payable"].to_f * retained_ratio).round
      # cdp.json_fields["orig_units_quantity"].should == cdp.units_quantity / retained_ratio
      cdp.units_quantity.should == (cdp.json_fields["orig_units_quantity"].to_f * retained_ratio).round
    end
  end

  @to_cc.capital_distribution_payments.each do |cdp|
    if cdp.json_fields["transfer_id"].present?
      puts "Checking capital distribution payment for #{cdp.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"
      cdp.json_fields["transfer_id"].should == @transfer_token
      # cdp.json_fields["orig_gross_payable"].should == cdp.gross_payable_cents / transfer_ratio
      cdp.gross_payable_cents.should == (cdp.json_fields["orig_gross_payable"].to_f * transfer_ratio)
      # cdp.json_fields["orig_units_quantity"].should == cdp.units_quantity / transfer_ratio
      cdp.units_quantity.should == (cdp.json_fields["orig_units_quantity"].to_f * transfer_ratio)
    end
  end
end

Then('adjustments are create upon fund unit transfer') do

  transfer_ratio = @transfer_ratio

  from_adjustment = @from_cc.commitment_adjustments.where(adjustment_type: "Transfer").last
  to_adjustment = @to_cc.commitment_adjustments.where(adjustment_type: "Transfer").last

  puts "Checking commitment adjustment for #{from_adjustment.id} for #{@from_cc.folio_id}"
  from_adjustment.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true
  # from_adjustment.amount_cents.should == -(@from_cc_committed_amount_cents * transfer_ratio).round
  from_adjustment.folio_amount_cents.should == -(@from_cc_folio_committed_amount_cents * transfer_ratio).round
  from_adjustment.adjustment_type.should == "Transfer"
  from_adjustment.as_of.should == Date.today

  puts "Checking commitment adjustment for #{to_adjustment.id} for #{@to_cc.folio_id}"
  to_adjustment.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true
  # to_adjustment.amount_cents.should == (@from_cc_committed_amount_cents * transfer_ratio).round
  to_adjustment.folio_amount_cents.should == (@from_cc_folio_committed_amount_cents * transfer_ratio).round
  to_adjustment.adjustment_type.should == "Transfer"
  to_adjustment.as_of.should == Date.today
end


Then('I should be able to see the transferred fund units') do
  @from_cc = @fund.capital_commitments.first
  @to_cc = @fund.capital_commitments.last
  from_fu = @from_cc.fund_units.last
  to_fu = @to_cc.fund_units.last

  visit(fund_unit_path(from_fu))
  expect(page).to have_content(number_with_delimiter(from_fu.quantity))
  expect(page).to have_content(money_to_currency(from_fu.price))
  expect(page).to have_content(money_to_currency(from_fu.premium))
  expect(page).to have_content(from_fu.reason)
  expect(page).to have_content(from_fu.transfer&.titleize)


  visit(fund_unit_path(to_fu))
  expect(page).to have_content(number_with_delimiter(to_fu.quantity))
  expect(page).to have_content(money_to_currency(to_fu.price))
  expect(page).to have_content(money_to_currency(to_fu.premium))
  expect(page).to have_content(to_fu.reason)
  expect(page).to have_content(to_fu.transfer&.titleize)
end


Given('there are payments for each remittance') do
  CapitalRemittance.all.each do |cr|
    unless cr.capital_remittance_payments.exists?
      cr.capital_remittance_payments.create!(fund_id: cr.fund_id, entity_id: cr.entity_id, folio_amount_cents: cr.folio_call_amount_cents, payment_date: cr.remittance_date)
    end
  end
end


Given('I upload fund documents {string}') do |zip|
  @import_file = zip
  visit(fund_path(@fund))
  click_on("Import")
  #sleep((2)
  click_on("Import Documents")
  #sleep((2)
  fill_in('import_upload_name', with: "Commitments and Distribution Docs Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep((2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
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

  data.each_with_index do |row, idx|
    p row[headers.length]
    next if idx.zero? # skip header row
    if idx == 1 or idx == 2
      row[headers.length].include?("Success").should == true
    end
    if idx == 3
      row[headers.length].include?("Fund Absent Fund not found").should == true
    end
    if idx == 4
      row[headers.length].include?("Investing Entity Investor 99 not found").should == true
    end
    if idx == 5
      row[headers.length].include?("Capital Commitment not found for SAAS Fund, 1001 and Investor 1").should == true
    end
    if idx == 6
      row[headers.length].include?("Distribution Name not found").should == true
    end
    if idx == 7
      row[headers.length].include?("Capital Distribution not found for SAAS Fund, Distribution 99").should == true
    end
    if idx == 8
      row[headers.length].include?("Capital Distribution Payment not found for SAAS Fund, Distribution 3, 10 and Investor 1").should == true
    end
    if idx == 9
      row[headers.length].include?("Fund is blank").should == true
    end
    if idx == 10
      row[headers.length].include?("Investing Entity is blank").should == true
    end
    if idx == 11
      row[headers.length].include?("Folio No is blank").should == true
    end
    if idx == 12
      row[headers.length].include?("file1.pdf cannot be uploaded again").should == true
    end
  end
end

Then('Given I upload {string} file for the remittances of the capital call with errors') do |file|
  @import_file = file
  visit(capital_call_path(@fund.capital_calls.first))
  click_on("Remittances")
  #sleep((2)
  click_on("Upload / Download")
  click_on("Upload Payments")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep((2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(10)
  ImportUpload.last.failed_row_count.should_not == 0
end

Then('I should see the remittance payments upload errors') do
  import_upload = ImportUpload.last
  tempfile = import_upload.import_results.download
  file = File.open(tempfile.path, "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row
    puts "row[headers.length] = #{row[headers.length]}"
    if idx < 7
      row[headers.length].include?("Success").should == true
    end
    if idx == 7
      row[headers.length].include?("Fund not found").should == true
    end
    if idx == 8
      row[headers.length].include?("Capital Call not found").should == true
    end
    if idx == 9
      row[headers.length].include?("Investor not found").should == true
    end
    if idx == 10
      row[headers.length].include?("Folio No or Virtual Bank Account must be specified").should == true
    end
    if idx == 11
      row[headers.length].include?("Investor commitment not found for folio C999").should == true
    end
    if idx == 12
      row[headers.length].include?("Investor commitment not found for virtual bank account 99998888").should == true
    end
    if idx == 13
      row[headers.length].include?("Investor commitment not found").should == true
    end
  end
end

Then('The proper documents must be uploaded for the remittances') do
  expect(ImportUpload.last.failed_row_count).to eq(7)
  doc1 = Document.where(name: "Remittance doc 1").first
  cc = CapitalCall.find_by(fund: @fund, name: "Capital Call 4")
  investor = Investor.find_by(investor_name: "Investor 1", entity: @fund.entity)
  expect(doc1.owner).to eq(CapitalRemittance.where(fund: @fund, folio_id: "6", investor_id: investor.id, capital_call_id: cc.id).first)
  doc2 = Document.where(name: "Remittance doc 2").first
  cc = CapitalCall.find_by(fund: @fund, name: "Capital Call 8")
  investor = Investor.find_by(investor_name: "Investor 2", entity: @fund.entity)
  expect(doc2.owner).to eq(CapitalRemittance.where(fund: @fund, folio_id: "7", investor_id: investor.id, capital_call_id: cc.id).first)
end

Then('I should see the remittance docs upload errors') do
  import_upload = ImportUpload.last
  tempfile = import_upload.import_results.download
  file = File.open(tempfile.path, "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    p row[headers.length]
    next if idx.zero? # skip header row
    if idx == 1 or idx == 2
      row[headers.length].include?("Success").should == true
    end
    if idx == 3
      row[headers.length].include?("Call Name not found").should == true
    end
    if idx == 4
      row[headers.length].include?("Capital Call not found for Some capital call").should == true
    end
    if idx == 5
      row[headers.length].include?("Capital Remittance not found for SAAS Fund, Capital Call 25, 55 and Investor 6").should == true
    end
    if idx == 6
      row[headers.length].include?("Fund is blank").should == true
    end
    if idx == 7
      row[headers.length].include?("Investing Entity is blank").should == true
    end
    if idx == 8
      row[headers.length].include?("Folio No is blank").should == true
    end
    if idx == 9
      row[headers.length].include?("file1.pdf cannot be uploaded again").should == true
    end
  end
end

And('The commitments have investor kycs linked') do
  @fund.capital_commitments.each do |cc|
    p "Linking kyc for Commitment #{cc.id}"
    investor = cc.investor
    kyc = InvestorKyc.new(investor: investor, entity: @fund.entity, verified: true, full_name: investor.investor_name)
    kyc.save(validate: false)
    cc.investor_kyc_id = kyc.id
    cc.save!
  end
end


Given('Given import file {string} for {string}') do |file, type|
  @import_file = file
  owner = @fund || @entity
  iu = ImportUpload.create!(entity: @entity, owner:, import_type: type, name: "Import #{type}", user_id: @user.id,  import_file: File.open(File.absolute_path("./public/sample_uploads/#{file}")))
  ImportUploadJob.perform_now(iu.id)
  iu.reload
  # binding.pry if iu.failed_row_count > 0
  # binding.pry if iu.failed_row_count > 0
  iu.failed_row_count.should == 0
end


Given('remittances are paid {string} and verified') do |paid_percentage|
  @latest_payment = {}
  @fund.capital_remittances.each do |cr|
    # Calculate the folio amount to be paid based on the given percentage
    folio_amount_cents = cr.folio_call_amount_cents * (paid_percentage.to_d / 100)

    # Create a new payment for the capital remittance
    crp = cr.capital_remittance_payments.new(
      fund_id: cr.fund_id,
      entity_id: cr.entity_id,
      folio_amount_cents: folio_amount_cents,
      payment_date: cr.remittance_date
    )

    result = CapitalRemittancePaymentCreate.wtf?(capital_remittance_payment: crp)

    # Store the latest   payment amount for the remittance
    @latest_payment[cr.id] = crp.amount_cents

    # Verify the capital remittance after the payment
    result = CapitalRemittanceVerify.call(capital_remittance: cr)
    result.success?.should == true
  end
end

Then('there should be correct units generated for the latest payment') do
  @fund.capital_remittances.each do |cr|
    fund_unit = cr.fund_units.last
    crp = cr.capital_remittance_payments.last
    puts "Checking fund unit for #{cr.id} with fund unit id #{fund_unit.id} amount #{fund_unit.amount} against payment #{crp.id} amount #{crp.amount}"
    fund_unit.amount.should == crp.amount
  end
end

Then('the total units should match the total paid amount') do
  @fund.capital_remittances.each do |cr|
    total_paid = cr.capital_remittance_payments.sum(&:amount)
    total_units = cr.fund_units.sum(&:amount)
    puts "Checking total paid #{total_paid} against total units amount #{total_units}"
    total_paid.should == total_units
  end
end

Then('the total units should be {string}') do |count|
  FundUnit.count.should == count.to_i
end

Given('Given I upload fund formulas for the fund') do
  @user.add_role :support # only support user can upload fund formulas
  @user.save!
  visit(fund_url(@fund))
  click_on("Actions")
  menu = find('#basic_reports', text: "Account Entries")  # Replace with actual selector
  menu.hover
  click_on("Allocation Formulas")
  sleep(1)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Fund Formulas Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/fund_formulas.xlsx"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} fund formulas created') do |string|
  @import_upload = ImportUpload.last
  expect(FundFormula.where(import_upload_id: @import_upload.id).count).to eq(string.to_i)
end

Then('the fund formulas must have the data in the sheet') do
  ffs = FundFormula.where(import_upload_id: @import_upload.id).order(:sequence).to_a
  file = File.open("./public/sample_uploads/fund_formulas.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row
    ff = ffs[idx-1]
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    ff.fund.should == @fund
    ff.name.should == user_data["Name"]
    ff.rule_for.should == user_data["Rule For"]
    ff.description.should == user_data["Description"]
    ff.generate_ytd_qtly.should == (user_data["Generate Ytd, Quarterly, Since Inception Numbers"]&.downcase == "yes")
    ff.tag_list.should == user_data["Tag List"].split(",").map(&:strip)
    ff.rule_type.should == user_data["Rule Type"]
    ff.formula.should == user_data["Formula"]
  end
end

Given ('the fund snapshot is created') do
  # Need to ensure that the fund has the entity permission to enable snapshots
  es = @fund.entity
  es.permissions.set(:enable_snapshots)
  es.save
  # Create the fund snapshot
  FundSnapshotJob.perform_now(fund_id: @fund.id)
  puts "Checking fund snapshot for #{@fund.id}"
  Fund.with_snapshots.where(orignal_id: @fund.id).count.should == 2
  fs = Fund.with_snapshots.where(orignal_id: @fund.id, snapshot: true).first
  fs.should_not == nil
  fs.snapshot_date.should == Time.zone.today

  @fund.aggregate_portfolio_investments.each do |api|
    AggregatePortfolioInvestment.with_snapshots.where(orignal_id: api.id).count.should == 2
    puts "Checking aggregate portfolio investment snapshot for #{api.id}"
    api_s = AggregatePortfolioInvestment.with_snapshots.where(orignal_id: api.id, snapshot: true).first
    api_s.should_not == nil
    api_s.snapshot_date.should == Time.zone.today

    api.portfolio_investments.each do |pi|
      PortfolioInvestment.with_snapshots.where(orignal_id: pi.id).count.should == 2
      puts "Checking portfolio investment snapshot for #{pi.id}"
      pi_s = PortfolioInvestment.with_snapshots.where(orignal_id: pi.id, snapshot: true).first
      pi_s.should_not == nil
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

Then('I can fetch the fund unit setting associated with the commitments') do
  commitment_investors_fund_unit_settings = {
    "Investor 1" => "Series A",
    "Investor 2" => "Series A",
    "Investor 3" => "Series B",
    "Investor 4" => "Series B",
    "Investor 5" => "Series C",
    "Investor 6" => "Series D",
  }
  @fund.capital_commitments.each do |cc|
    expect(cc.fund_unit_setting).to be_present
    expect(cc.fund_unit_setting.name).to eq(cc.unit_type)
    expect(cc.fund_unit_setting.name).to eq(commitment_investors_fund_unit_settings[cc.investor_name])
  end
end

Then('I can fetch the lp and gp commitments') do
  series_to_lp_gp = {
    "Series A" => "LP",
    "Series B" => "GP",
    "Series C" => "LP",
    "Series D" => "GP"
  }

  commitment_investors_fund_unit_settings = {
    "Investor 1" => "Series A",
    "Investor 2" => "Series A",
    "Investor 3" => "Series B",
    "Investor 4" => "Series B",
    "Investor 5" => "Series C",
    "Investor 6" => "Series D",
  }
  expect(@fund.capital_commitments.lp(@fund.id).pluck(:unit_type).uniq).to match_array(series_to_lp_gp.keys.select { |k| series_to_lp_gp[k] == "LP" })
  expect(@fund.capital_commitments.gp(@fund.id).pluck(:unit_type).uniq).to match_array(series_to_lp_gp.keys.select { |k| series_to_lp_gp[k] == "GP" })
  expect(@fund.capital_commitments.lp(@fund.id).count).to eq(3)
  expect(@fund.capital_commitments.gp(@fund.id).count).to eq(5)

  expect(@fund.capital_commitments.lp(@fund.id).pluck(:unit_type)).to match_array(["Series A", "Series A", "Series C"])
  expect(@fund.capital_commitments.gp(@fund.id).pluck(:unit_type)).to match_array(["Series B", "Series B", "Series B", "Series D", "Series D"])
  expect(@fund.capital_commitments.lp(@fund.id).pluck(:investor_name)).to match_array(["Investor 1", "Investor 2", "Investor 5"])
  expect(@fund.capital_commitments.gp(@fund.id).pluck(:investor_name)).to match_array(["Investor 3", "Investor 4", "Investor 4", "Investor 6", "Investor 6"])
end


Then('There should be {string} fund units created with data in the {string} sheet') do |count, file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_commitment = CapitalCommitment.where(folio_id: row_data["Folio No"]).first

    fund_unit = FundUnit.where(capital_commitment_id: capital_commitment.id, quantity: row_data["Quantity"].to_f).first

    puts "Checking import of #{fund_unit.to_json}"

    fund_unit.quantity.should == row_data["Quantity"].to_f
    fund_unit.unit_type.should == row_data["Unit Type"]
    fund_unit.price_cents.should == row_data["Price"].to_f * 100.0
    fund_unit.premium_cents.should == row_data["Premium"].to_f * 100.0
    fund_unit.issue_date.should == row_data["Issue Date"]
    fund_unit.reason.should == row_data["Reason"]
    fund_unit.owner.folio_id.should == row_data["Folio No"].to_s

    if fund_unit.quantity.positive?
      fund_unit.owner_type.should == "CapitalRemittance"
    else
      fund_unit.owner_type.should == "CapitalDistributionPayment"
    end
  end
end


When('I edit the remittance payment with convert_to_fund_currency {string}') do |string|
  @convert_to_fund_currency = string == "true"
  @target_remittance_payment = CapitalRemittancePayment.where(convert_to_fund_currency: @convert_to_fund_currency).first
  visit(edit_capital_remittance_payment_path(@target_remittance_payment))
  @amount = @target_remittance_payment.amount.to_f
  @folio_amount = @target_remittance_payment.folio_amount.to_f * 5
  fill_in("capital_remittance_payment_folio_amount", with: @folio_amount) if @convert_to_fund_currency
  fill_in("capital_remittance_payment_notes", with: "Test edit remittance payment")
  click_on("Save")
  expect(page).to have_content("Capital remittance payment was successfully updated")
end

Then('the capital remittance payment amount is recomputed') do
  @target_remittance_payment.reload
  puts "Checking remittance payment amount #{@target_remittance_payment.amount} against folio amount #{@target_remittance_payment.folio_amount}"
  expect(@target_remittance_payment.folio_amount.to_f).to eq(@folio_amount)
  expect(@target_remittance_payment.amount.to_f).not_to eq(@amount)
end

Then('the capital remittance payment amount is not recomputed') do
  @target_remittance_payment.reload
  puts "Checking remittance payment amount #{@target_remittance_payment.amount} against folio amount #{@target_remittance_payment.folio_amount}"
  expect(@target_remittance_payment.folio_amount.to_f).not_to eq(@folio_amount)
  expect(@target_remittance_payment.amount.to_f).to eq(@amount)
end


Given('We Generate documents for the capital distribution') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  @capital_distribution_payments.each do |cdp|
    unless cdp.capital_commitment&.investor_kyc&.verified
      if cdp.capital_commitment.investor_kyc.present?
        cdp.capital_commitment.investor_kyc.verified = true
        res = cdp.capital_commitment.investor_kyc.save(validate: false)
        puts "KYC for investor #{cdp.investor_name} verified: #{res}"
      else
          investor_kyc = InvestorKyc.new(investor: cdp.capital_commitment.investor, entity: @entity, verified: true, full_name: cdp.investor_name, PAN: Faker::Alphanumeric.alphanumeric(number: 10).upcase, birth_date: Date.today - 18.years)
          res = investor_kyc.save(validate:false)
          puts "KYC for investor #{cdp.investor_name} created and verified: #{res}"
          cdp.capital_commitment.investor_kyc = investor_kyc
          cdp.capital_commitment.save(validate: false)
          puts "Capital Commitment #{cdp.capital_commitment.id} updated with KYC"
      end
    end
  end
  visit(capital_distribution_path(@capital_distribution))
  click_on("Actions")
  click_on("Generate Documents")
  click_on("Proceed")
  sleep(5) # Wait for the job to complete
  expect(page).to have_content("Documentation generation started")
end


Given('The distribution payment documents are approved') do
  @capital_distribution_payments ||= @capital_distribution.capital_distribution_payments
  @capital_distribution_payments.each do |cdp|
    expect(cdp.documents.count).to be > 0
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
  @custom_notification = CustomNotification.create!(entity: @capital_distribution.entity, subject: subject, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_distribution, email_method: "send_notification")
end
