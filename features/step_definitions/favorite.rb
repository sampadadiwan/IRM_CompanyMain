Given('I click on {string} button') do |string|
  click_button string
end

Given('I click on Add to Favorites button') do
  find("#add-to-favorites-button").click
end

When("I click View All in favorites") do
  within(".dropdown-menu-nav") do
    click_link "View All"
  end
end

Given('I have no favorites') do
  Favorite.destroy_all
end


Then('I should see the fund in the favorites list') do
   within(".dropdown-menu-nav") do
    @favorite_title = @fund.name
    expect(page).to have_selector("h6", text: @favorite_title)
  end
end

Then('I should see the fund in the favorites list page') do
  expect(page).to have_content(@favorite_title)
  expect(page).to have_content(@user.to_s)
end

Then('I click on the fund in the favorites list page') do
  within("table#DataTables_Table_0") do
    click_on @favorite_title
  end
end

Then('I should be on the fund details page') do
  @fund ||= Fund.first
  expect(page).to have_content("Fund: #{@fund.name}")
  expect(page).to have_content("Committed")
  expect(page).to have_content("Called")
  expect(page).to have_content("Collected")
  expect(page).to have_content("Distributed")
  expect(page).to have_content("Folios")
  expect(page).to have_content("Commitments")

end

Then('I should not see the fund in the favorites list page') do
  within("table#DataTables_Table_0") do
    expect(@favorite_title).to eq @fund.name
    expect(page).not_to have_content(@favorite_title)
  end
end

Given('I go to the investor page') do
  @investor ||= Investor.first
  visit investor_path(@investor)
end

Then('I should see the investors in the favorites list') do
  within(".dropdown-menu-nav") do
    @favorite_title = @investor.investor_name
    expect(page).to have_selector("h6", text: @favorite_title)
  end
end

Then('I should see the investors in the favorites list page') do
  @favorite_title = @investor.investor_name
  puts "Favorite Title: #{@favorite_title}"
  expect(page).to have_content(@favorite_title)
  expect(page).to have_content(@user.to_s)
end

Then('I click on the investors in the favorites list page') do
  within("table#DataTables_Table_0") do
    click_link @favorite_title
  end
end

Then('I should be on the investors details page') do
  expect(page).to have_content("Stakeholder: #{@investor.investor_name}")
  expect(page).to have_content("Users")
  expect(page).to have_content("KYC")
  expect(page).to have_content("Commitments")
end

Then('I should not see the investors in the favorites list page') do
  within("table#DataTables_Table_0") do
    expect(@favorite_title).to eq @investor.investor_name
    expect(page).not_to have_content(@favorite_title)
  end
end

Given('I am using first fund') do
  @fund = Fund.first
end
