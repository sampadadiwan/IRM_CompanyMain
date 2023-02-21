  include CurrencyHelper

  Given('Im logged in as the employee investor') do
    @user = @investor_entity.employees.first
    steps %(
        And I am at the login page
        When I fill and submit the login page
    )
  end
    
  When('I go to the dashboard I must see the employee holding') do
    visit("entities/dashboard")

    @user.holdings.approved.each do |holding|
        within("#holding_#{holding.id}") do
         page.should have_content(holding.quantity)
         page.should have_content(holding.vested_quantity)
         page.should have_content(holding.option_pool.excercise_price)
         page.should have_content(money_to_currency(holding.value))
        end
    end
  end
  
  When('I acknowledge the holding') do
    @user.holdings.approved.each do |holding|
      visit(holding_path(holding))        
      click_on("Acknowledge")
      visit("entities/dashboard")
    end
  end
  
  Then('the holding must be acknowledged') do
    @user.holdings.approved.each do |holding|
        holding.emp_ack.should == true
        within("#holding_#{holding.id}") do
            page.should have_content("Acknowledged")
        end
    end
  end
  