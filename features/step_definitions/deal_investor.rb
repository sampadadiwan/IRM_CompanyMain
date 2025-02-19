include ActionView::Helpers::NumberHelper
include CurrencyHelper

  When('I create a new deal investor {string}') do |arg1|
    @deal_investor = FactoryBot.build(:deal_investor)
    @deal_investor.investor_name = @deal_investor.investor.investor_name
    key_values(@deal_investor, arg1)
    puts "\n####DealInvestor####\n"
    puts @deal_investor.to_json

    click_on("Add Investor")

    select(@deal_investor.investor_name, from: "deal_investor_investor_id")
    fill_in('deal_investor_primary_amount', with: @deal_investor.primary_amount)
    fill_in('deal_investor_secondary_investment', with: @deal_investor.secondary_investment)
    fill_in('deal_investor_pre_money_valuation', with: @deal_investor.pre_money_valuation)

    click_on("Save")
  end

  Then('a deal investor should be created') do
    @created = DealInvestor.last
    @created.deal_id.should == @deal.id
    @created.investor_id.should == @deal_investor.investor_id
    @created.primary_amount.should == @deal_investor.primary_amount
    @created.secondary_investment.should == @deal_investor.secondary_investment
    @created.entity_id.should == @deal.entity_id
  end

  Then('I should see the deal investor details on the details page') do
    expect(page).to have_content(@deal.name)
    expect(page).to have_content(@deal_investor.investor_name)
    expect(page).to have_content(money_to_currency @deal_investor.primary_amount)
    expect(page).to have_content(money_to_currency @deal_investor.secondary_investment)
    expect(page).to have_content(money_to_currency @deal_investor.pre_money_valuation)
    expect(page).to have_content(@deal_investor.entity_name)
  end

  Then('I should see the deal investor in all deal investors page') do
    visit("/deal_investors")
    expect(page).to have_content(@deal.name)
    expect(page).to have_content(@deal_investor.investor_name)
    expect(page).to have_content(money_to_currency @deal_investor.primary_amount)
    expect(page).to have_content(money_to_currency @deal_investor.secondary_investment)
    expect(page).to have_content(money_to_currency @deal_investor.pre_money_valuation)
    # expect(page).to have_content(@deal_investor.entity_name)
  end


  Given('there are {string} deal_investors for the deal') do |arg|
    (1..arg.to_i).each do |i|
      di = FactoryBot.create(:deal_investor, deal: @deal, entity: @deal.entity,
                             status: "Active", investor: Investor.find(i))
    end
    @deal.reload
  end

  Given('I should see the deal investors in the deal details page') do
    visit(deal_path(@deal, grid_view: true))

    @deal.deal_investors.each do |deal_investor|
      within("#deal_investor_#{deal_investor.id}") do
        expect(page).to have_content(deal_investor.investor_name)
        expect(page).to have_content(money_to_currency deal_investor.primary_amount)
        expect(page).to have_content(money_to_currency deal_investor.secondary_investment)
        expect(page).to have_content(money_to_currency deal_investor.pre_money_valuation)
      end
    end

  end

  Given('I should see the deal stages in the deal details page') do
    @deal.deal_investors.each do |deal_investor|
      within("#deal_investor_#{deal_investor.id}") do
        deal_investor.deal_activities.each do |act|
          within("#deal_activity_#{act.id}") do
            expect(page).to have_content(act.completed_status)
          end
        end
      end
    end
  end


  Given('the deal activites are completed') do
    @deal.deal_activities.update_all(completed: true)
    @deal.reload
  end

  Given('I complete an activity') do
    @deal_activity = @deal.deal_activities.where.not(deal_investor_id: nil).first
    within("#deal_activity_#{@deal_activity.id}") do
      find('span', text: 'No').click
      sleep(1)
      find('button', text: "Toggle Done").click
    end
    sleep(5)
  end

  Then('the activity must be completed') do
    @deal_activity.reload
    @deal_activity.completed_status.should == "Yes"
  end

  Given('there is a deal investor for the last investor') do
    inv = Investor.last
    @deal_investor = FactoryBot.create(:deal_investor, investor: inv, entity_id: inv.entity_id, deal: @deal)
  end


  Given('there is a deal investor with name {string}') do |name|
    inv = Investor.find_by(investor_name: name)
    @deal_investor = FactoryBot.create(:deal_investor, investor: inv, entity_id: inv.entity_id, deal: @deal)
  end

  When('I view the deal investor details') do
    visit(deal_investor_path(@deal_investor))
  end

  Given('I am {string} employee access to the deal_investors') do |given|
    if given == "given" || given == "yes"
      DealInvestor.all.each do |di|
        @access_right = AccessRight.create!(entity_id: di.entity_id, owner: di, user_id: @user.id)
        puts "\n####AccessRight####\n"
        puts @access_right.to_json
      end
    end
    @user.reload
  end

  Then('I {string} see the deal investors in the deal details page') do |should|
    visit(deal_path(@deal, grid_view:true))


    @deal.deal_investors.each do |deal_investor|
        if should == "true"
          within("#deal_investor_#{deal_investor.id}") do
            expect(page).to have_content(deal_investor.investor_name)
            expect(page).to have_content(money_to_currency deal_investor.primary_amount)
            expect(page).to have_content(money_to_currency deal_investor.secondary_investment)
            expect(page).to have_content(money_to_currency deal_investor.pre_money_valuation)
          end
        else
          expect(page).not_to have_selector "#deal_investor_#{deal_investor.id}"
        end
    end
  end
