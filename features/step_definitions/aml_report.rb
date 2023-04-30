Given('there is an investor {string} with investor kyc and aml report for the entity {string}') do |arg1, arg2|
  args_temp = arg2.split(";").to_h { |kv| kv.split("=") }
  @investor_entity = if Entity.exists?(args_temp)
    Entity.find_by(args_temp)
  else
    FactoryBot.build(:entity)
  end
  key_values(@investor_entity, arg2)
  @investor_entity.save!
  args_temp = arg1.split(";").to_h { |kv| kv.split("=") }
  @investor = if Investor.exists?(args_temp)
    Investor.find_by(args_temp)
  else
    FactoryBot.build(:investor)
  end
  key_values(@investor, arg1)
  @investor.entity_id = @investor_entity.id
  @investor.investor_entity_id = FactoryBot.create(:entity).id
  @investor.save!
  RSpec::Mocks.with_temporary_scope do
    @investor_kyc = FactoryBot.build(:investor_kyc, investor: @investor, entity: @investor_entity)
    aml_report = FactoryBot.create(:aml_report, investor: @investor, entity: @investor_entity, investor_kyc: @investor_kyc, name: @investor_kyc.full_name)
    InvestorKyc.stub(:generate_aml_report).and_return(aml_report)
    allow_any_instance_of(InvestorKyc).to receive(:generate_aml_report).and_return(aml_report)
    @investor_kyc.save!
  end
  @aml_report = AmlReport.order(created_at: :desc).first
end

Then('{string} has {string} "{string}" access to the aml_report of investor {string}') do |arg1, arg2, accesses, arg4|
  args_temp = arg1.split(";").to_h { |kv| kv.split("=") }
  @user = if User.exists?(args_temp)
    User.find_by(args_temp)
  else
    FactoryBot.build(:user)
  end
  key_values(@user, arg1)
  @user.save!
  args_temp = arg4.split(";").to_h { |kv| kv.split("=") }
  @investor = if Investor.exists?(args_temp)
    Investor.find_by(args_temp)
  else
    FactoryBot.build(:investor)
  end
  @investor.entity_id = @investor_entity.id
  @investor.investor_entity_id = FactoryBot.create(:entity).id
  key_values(@investor, arg4)
  @investor.save!
  accesses.split(',').each do |access|
    Pundit.policy(@user, @aml_report).send("#{access}?").to_s.should == arg2
  end
end

Given('the entity {string} has aml enabled {string}') do |args, boolean|
  args_temp = args.split(";").to_h { |kv| kv.split("=") }
  @entity = if Entity.exists?(args_temp)
    Entity.find_by(args_temp)
  else
    FactoryBot.build(:Entity)
  end
  key_values(@entity, args)
  @entity.entity_setting.aml_enabled = boolean
  @entity.save!
end


