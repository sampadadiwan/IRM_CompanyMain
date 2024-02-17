Given('the investor has investor kyc and aml report') do
  RSpec::Mocks.with_temporary_scope do
    @investor_kyc = FactoryBot.build(:investor_kyc, investor: @investor, entity: @entity)
    InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user: false)
    aml_report = FactoryBot.create(:aml_report, investor: @investor, entity: @entity, investor_kyc: @investor_kyc, name: @investor_kyc.full_name)
    InvestorKyc.stub(:generate_aml_report).and_return(aml_report)
    allow_any_instance_of(InvestorKyc).to receive(:generate_aml_report).and_return(aml_report)

  end
  @aml_report = AmlReport.order(created_at: :desc).first
end

Then('{string} has {string} "{string}" access to the aml_report of investor') do |arg1, arg2, accesses|
  args_temp = arg1.split(";").to_h { |kv| kv.split("=") }
  @user = if User.exists?(args_temp)
    User.find_by(args_temp)
  else
    FactoryBot.build(:user)
  end
  key_values(@user, arg1)
  @user.save!
  accesses.split(',').each do |access|
    Pundit.policy(@user, @aml_report).send("#{access}?").to_s.should == arg2
  end
end

Given('the entity {string} has aml enabled {string}') do |args, boolean|
  args_temp = args.split(";").to_h { |kv| kv.split("=") }
  @entity = if Entity.exists?(args_temp)
    Entity.find_by(args_temp)
  else
    FactoryBot.build(:entity, pan: Faker::Alphanumeric.alphanumeric(number: 10))
  end
  key_values(@entity, args)
  @entity.save!
  @entity.entity_setting.aml_enabled = boolean
  @entity.entity_setting.save!
end

Then('investor kyc and aml report is generated for it') do
  @investor_entity = FactoryBot.create(:entity,  pan: Faker::Alphanumeric.alphanumeric(number: 10), entity_type: "InvestmentFund")
  @investor = FactoryBot.create(:investor, investor_entity_id: FactoryBot.create(:entity,  pan: Faker::Alphanumeric.alphanumeric(number: 10), entity_type: "InvestmentFund").id, entity_id: @investor_entity.id)

  @investor_entity.entity_setting.fi_code = "test"
  @investor_entity.entity_setting.ckyc_enabled = true
  @investor_entity.entity_setting.kra_enabled = true
  @investor_entity.entity_setting.aml_enabled = true
  @investor_entity.entity_setting.save!
  visit(investor_kycs_url)
  sleep(2)
  click_on("New KYC")
  click_on("Individual")
  sleep(3)
  pan = "testpannum555"

  fill_in('individual_kyc_full_name', with: "testname abc")
  fill_in('individual_kyc_birth_date', with: "03/03/2020")
  fill_in('individual_kyc_PAN', with: pan)
  click_on("Next")
  sleep(3)
  click_on("Next")
  sleep(2)
  click_on("Save")
  sleep(5)
  InvestorKyc.where(PAN: pan).last.aml_reports.count.should > 0
  AmlReport.where(name: InvestorKyc.where(PAN: pan).last.full_name).count > 0
end

Then('investor kyc and aml report is not generated for it') do
  @investor_entity = FactoryBot.create(:entity,  pan: Faker::Alphanumeric.alphanumeric(number: 10), entity_type: "InvestmentFund")
  @investor = FactoryBot.create(:investor, investor_entity_id: FactoryBot.create(:entity,  pan: Faker::Alphanumeric.alphanumeric(number: 10), entity_type: "InvestmentFund").id, entity_id: @investor_entity.id)

  @investor.entity.entity_setting.fi_code = "test"
  @investor.entity.entity_setting.ckyc_enabled = true
  @investor.entity.entity_setting.kra_enabled = true
  @investor.entity.entity_setting.aml_enabled = true
  @investor.entity.entity_setting.save!
  visit(investor_kycs_url)
  sleep(2)
  click_on("New KYC")
  click_on("Individual")
  sleep(3)
  pan = "testpannum555"
  fill_in('individual_kyc_birth_date', with: "01/01/1955")
  fill_in('individual_kyc_PAN', with: pan)
  click_on("Next")
  sleep(3)
  click_on("Next")
  sleep(2)
  click_on("Save")
  sleep(5)
  InvestorKyc.where(PAN: pan).last.aml_reports.count.should == 0
  AmlReport.where(name: InvestorKyc.where(PAN: pan).last.full_name).count == 0
end
