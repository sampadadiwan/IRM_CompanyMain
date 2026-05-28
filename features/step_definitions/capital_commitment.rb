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
    # find(".show_details_link").click

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

Then('There should be {string} capital commitments created') do |count|
  @fund.capital_commitments.count.should == count.to_i
end

Then('the import upload must be updated correctly for capital commitments') do
  @import_upload = ImportUpload.last
  @import_upload.failed_row_count.should == 0
  @import_upload.processed_row_count.should == @fund.capital_commitments.count
  @import_upload.total_rows_count.should == @fund.capital_commitments.count
  @import_upload.status.should == "Completed"
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
    cc.investor.investor_name.should == user_data["Stakeholder"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.commitment_date.should == Date.local_parse(user_data["Commitment Date"].to_s)
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

Then('the capital commitments must have the percentages updated') do
  puts "### Checking capital commitments percentages"
  ap CapitalCommitment.all.pluck(:id, :percentage)
  CapitalCommitment.where(percentage: 0).count.should == 0
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

Then('I should be able to see my capital commitments') do
  @user.reload
  # click_on("Commitments")


  within("#capital_commitments") do
    CapitalCommitment.all.each do |cc|

      @investor = cc.entity.investors.joins(:investor_accesses).where("investor_accesses.user_id=?", @user.id).first

      puts "checking capital commitment for #{cc.investor.investor_name} against #{@investor.investor_name}"

      if cc.investor_id == @investor.id
        puts "Commitment Visible"
        expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
        # expect(page).to have_content(cc.fund.name)
        expect(page).to have_content( money_to_currency(cc.committed_amount, {force_units: "Lakhs"}) )
      else
        puts "Commitment Not Visible"
        expect(page).not_to have_content(cc.investor.investor_name)
      end
    end
  end
end

Given('the fund has capital commitment template') do
  @commitment_template = Document.create!(name: "Fund Agreement", owner_tag: "Commitment Template",
    owner: @fund, entity_id: @fund.entity_id, user: @user,
    file: File.new("public/sample_uploads/Commitment Agreement Template.docx", "r"))
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

Given('each investor has a {string} kyc') do |status|
  verified = status == "verified"
  Investor.all.each do |inv|
    kyc = FactoryBot.create(:investor_kyc, investor: inv, entity: @fund.entity, verified:)
  end
end

Given('each investor has a {string} kyc linked to the commitment') do |status|
  # submission_status must match verified/completed_by_investor booleans so the
  # sync_boolean_fields_from_status after_save callback does not overwrite them.
  valid_statuses = %w[not_sent link_sent draft_saved completed verified]
  submission_status = valid_statuses.include?(status) ? status : "verified"
  verified = %w[verified].include?(submission_status)
  completed_by_investor = %w[completed verified].include?(submission_status)

  Investor.all.each do |inv|
    kyc = FactoryBot.build(
      :investor_kyc,
      investor: inv,
      entity: @fund.entity,
      verified:,
      completed_by_investor:,
      submission_status:
    )
    kyc.save(validate: false)
    @fund.capital_commitments.where(investor_id: inv.id).update(investor_kyc_id: kyc.id)
  end
end

Then('the commitment amounts change correctly') do
  @fund.reload
  @fund.capital_commitments.each do |cc|
    cc.committed_amount_cents.should == cc.orig_committed_amount_cents + cc.adjustment_amount_cents
  end
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

And('The commitments have investor kycs linked') do
  @fund.capital_commitments.each do |cc|
    p "Linking kyc for Commitment #{cc.id}"
    investor = cc.investor
    kyc = InvestorKyc.new(investor: investor, entity: @fund.entity, verified: true, completed_by_investor: true, submission_status: "verified", full_name: investor.investor_name)
    kyc.save(validate: false)
    cc.investor_kyc_id = kyc.id
    cc.save!
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

Given('The multiple commitments have the same investor kycs linked') do
  investors = {}
  @fund.capital_commitments.each do |cc|
    p "Linking kyc for Commitment #{cc.id}"
    investor = cc.investor
    if investors.include?(investor.id)
      kyc = InvestorKyc.find investors[investor.id]
      puts "Reusing KYC #{kyc.id} for investor #{investor.id}"
      cc.investor_kyc_id = kyc.id
      cc.save!
    else
      kyc = InvestorKyc.new(investor: investor, entity: @fund.entity, verified: true, completed_by_investor: true, submission_status: "verified", full_name: investor.investor_name)
      kyc.save(validate: false)
      puts "Creating new KYC #{kyc.id} for investor #{investor.id}"
      investors[investor.id] = kyc.id
      cc.investor_kyc_id = kyc.id
      cc.save!
    end
  end
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
