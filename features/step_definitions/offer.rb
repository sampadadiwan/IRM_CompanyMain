  Given('Im logged in as an employee investor') do
    @investor_entity = Entity.where(is_holdings_entity: true).first
    @employee_investor = @investor_entity.employees.first
    puts "\n####employee_investor####\n"
    puts @employee_investor.to_json

    @user = @employee_investor
    steps %(
        And I am at the login page
        When I fill and submit the login page
    )

  end

  Given('Im logged in as an investor') do

    @user = @investor_user
    steps %(
        And I am at the login page
        When I fill and submit the login page
    )

  end

  Given('there is a holding {string} for each employee investor') do |args|
    @investor_entity.employees.each do |emp|
        holding = FactoryBot.build(:holding, user: emp, entity: @entity,
                                    funding_round: @funding_round, investor_id: @entity.investors.first.id)
        key_values(holding, args)
        CreateHolding.wtf?(holding: holding).success?.should == true
        ApproveHolding.wtf?(holding: holding).success?.should == true
        puts "\n#########Holding##########\n"
        puts holding.to_json
    end
  end

  Given('there is a holding {string} for each investor') do |args|
    @sale.seller_investors.each do |inv|
      emp = inv.investor_entity.employees.first
      holding = FactoryBot.build(:holding, user: emp, entity: @entity, holding_type: "Investor",
                                  funding_round: @funding_round, investor_id: inv.id)
      key_values(holding, args)
      CreateHolding.wtf?(holding: holding).success?.should == true
      ApproveHolding.wtf?(holding: holding)
      puts "\n#########Holding##########\n"
      puts holding.to_json
    end
  end


  Given('there is an option holding {string} for each employee investor') do |args|
    @investor_entity.employees.each do |emp|
        holding = FactoryBot.build(:holding, user: emp, entity: @entity, option_pool: @option_pool,
                                    funding_round: @option_pool.funding_round, investor_id: @entity.investors.first.id)
        key_values(holding, args)
        CreateHolding.wtf?(holding:holding).success?.should == true

        puts "\n#########Option Holding##########\n"
        puts holding.to_json

        if holding.approved
          ApproveHolding.wtf?(holding: holding).success?.should == true
        end
    end

  end
  Then('I should see only my holdings') do
    @employee_investor.holdings.all.each do |h|
        within("tr#holding_#{h.id}") do
            expect(page).to have_content(h.holding_type)
            expect(page).to have_content(h.user.full_name)
            # expect(page).to have_content(h.user.email)
            # expect(page).to have_content(h.entity.name)
            expect(page).to have_content(h.investment_instrument)
            expect(page).to have_content(h.quantity)

            expect(page).to have_content("Offer")
        end
    end

    @investor_entity.employees.where("id <> ?", @employee_investor.id).each do |other_emp|
        other_emp.holdings.all.each do |h|
            expect(page).to have_no_content(h.user.full_name)
            expect(page).to have_no_content(h.user.email)
        end
    end

  end

  Then('I edit the offer {string}') do |arg|
    visit(edit_offer_path(@offer))

    @offer = FactoryBot.build(:offer, approved: @offer.approved, secondary_sale: @offer.secondary_sale)
    key_values(@offer, arg)

    steps %(
      Then when I submit the offer
    )
  end


  Then('when I submit the offer') do

    puts "\n####Offer####\n"
    puts @offer.to_json

    fill_in("offer_quantity", with: @offer.quantity) unless @offer.approved

    if(@offer.secondary_sale && @offer.secondary_sale.finalized)
      click_on("Next")
      fill_in("offer_full_name", with: @offer.full_name)
      fill_in("offer_PAN", with: @offer.PAN)
      fill_in("offer_address", with: @offer.address)
      # fill_in("offer_city", with: @offer.city)
      fill_in("offer_demat", with: @offer.demat)
      fill_in("offer_bank_account_number", with: @offer.bank_account_number)
      fill_in("offer_ifsc_code", with: @offer.ifsc_code)
      # fill_in("offer_bank_name", with: @offer.bank_name)
      # fill_in("offer_bank_routing_info", with: @offer.bank_routing_info)
      click_on("Next")
    end

    click_on("Save")
    sleep(1)

  end

  Then('when I place an offer {string}') do |arg|
    @offer = FactoryBot.build(:offer)
    key_values(@offer, arg)
    within "table#holdings" do
      click_on("Offer")
    end
    steps %(
      Then when I submit the offer
    )
  end

  When('I visit the offer details page') do
    @offer ||= Offer.first
    visit(offer_path(@offer))
  end


  Then('I should see the offer details') do
    if page.has_css?("#display_status_ok")
      sleep(1)
      find("#display_status_ok").click
    end

    expect(page).to have_content(@user.full_name)
    expect(page).to have_content(@entity.name)
    expect(page).to have_content(@sale.name)
    expect(page).to have_content(@offer.quantity)

    if(@offer.secondary_sale && @offer.secondary_sale.finalized)
      expect(page).to have_content(@offer.full_name)
      expect(page).to have_content(@offer.PAN)
      expect(page).to have_content(@offer.address)
      expect(page).to have_content(@offer.bank_account_number)
      # expect(page).to have_content(@offer.bank_name)
      # expect(page).to have_content(@offer.bank_routing_info)
    end

    within("tr#approved") do
        expect(page).to have_content(@offer.approved ? "Yes" : "No")
    end

    @offer = Offer.last
  end

  Then('when the offer sale is finalized') do
    @offer.secondary_sale.finalized = true
    @offer.secondary_sale.lock_allocations = true

    @offer.secondary_sale.final_price = 100
    @offer.secondary_sale.save
  end

  Then('I should see the offer in the offers tab') do
    visit(secondary_sale_path(@sale))
    click_on("Offers")
    expect(page).to have_content(@user.full_name)
    # expect(page).to have_content(@entity.name)
    expect(page).to have_content(@offer.quantity)
    # within("td.approved") do
        expect(page).to have_content("No")
    # end
  end



Given('there is an {string} offer {string} for each employee investor') do | approved_arg, args|

  approved = approved_arg == "approved"
  Holding.all.each do |h|
    offer = FactoryBot.build(:offer, holding_id: h.id, user_id:h.user_id, entity_id: h.entity_id,
                secondary_sale_id: @sale.id, investor_id: h.investor_id, approved: approved)
    key_values(offer, args)
    offer.save!

    offer.approved = approved
    offer.save

    puts "\n####Offer####\n"
    puts offer.to_json
  end

  @sale.reload
end

Then('I should see all the offers') do
  click_on("Offers")

  Offer.all.each do |offer|
    within("tr#offer_#{offer.id}") do
        expect(page).to have_content(offer.user.full_name)
        expect(page).to have_content(offer.investor.investor_name)
        expect(page).to have_content(offer.quantity)
        expect(page).to have_content(offer.percentage)
        within("td.approved") do
          if offer.approved
            expect(page).to have_content("Yes")
          else
            expect(page).to have_content("No")
          end
        end
    end
  end
end

Then('When I approve the offers the offers should be approved') do
Offer.all.each do |offer|
    visit offer_path(offer)
    click_on("Approve")
    sleep(1)

    offer.reload
    offer.approved.should == true

    within("td.approved") do
      expect(page).to have_content("Yes")
    end

    visit secondary_sale_path(offer.secondary_sale)
    click_on("Offers")
  end
end

Given('Given I upload a offer file') do
    Sidekiq.redis(&:flushdb)

    @existing_user_count = User.count
    visit(secondary_sale_path(@sale))
    click_on("Pending Offers")
    click_on("Upload / Download")
    click_on("Upload Offers")
    fill_in('import_upload_name', with: "Test Upload")
    attach_file('files[]', File.absolute_path('./public/sample_uploads/offers.xlsx'), make_visible: true)
    sleep(3)
    click_on("Save")
    sleep(3)
    ImportUploadJob.perform_now(ImportUpload.last.id)
    sleep(5)

    ImportUpload.last.failed_row_count.should == 0
end

Then('when the offers are approved') do
  @sale.reload
  @sale.offers.each do |offer|
    offer.approved = true
    offer.granted_by_user_id = @user.id
    offer.save
  end
end

Then('the sale offered quantity should be {string}') do |quantity|
  @sale.reload
  @sale.total_offered_quantity.should == quantity.to_i
end
