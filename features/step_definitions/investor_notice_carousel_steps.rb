# Step definitions for features/misc/investor_notices.feature
#
# Covers the GP-scoped notices carousel on the LP dashboard:
# InvestorNotice.notices(user, gp_entity_id:) must only return notices
# published by the GP selected in the vc_dashboard GP switcher.

# Creates an active InvestorNotice published by the given GP entity, plus the
# InvestorNoticeEntry that targets the LP's investor entity. Both records are
# required for the notice to surface via InvestorNotice.notices.
def create_notice_for_gp(gp_entity, investor, title)
  notice = InvestorNotice.create!(
    entity_id: gp_entity.id,
    title: title,
    start_date: Time.zone.today,
    end_date: Time.zone.today + 1.month,
    active: true
  )
  InvestorNoticeEntry.create!(
    investor_notice_id: notice.id,
    investor_id: investor.id,
    investor_entity_id: investor.investor_entity_id,
    entity_id: gp_entity.id,
    active: true
  )
  notice
end

Given('the GP entity has an active investor notice titled {string}') do |title|
  # @entity is the first GP (from "there is a user ... for an entity") and
  # @investor links the LP's investor entity to it (from "there is an existing
  # investor ... with ... users").
  @first_gp_entity = @entity
  create_notice_for_gp(@first_gp_entity, @investor, title)
end

Given('there is a second GP entity {string} that the investor user can access') do |args|
  # A second, independent GP the same LP user has approved access to — this is
  # what puts more than one option in the GP switcher dropdown.
  @second_gp_entity = FactoryBot.build(:entity, entity_type: "Investment Fund")
  key_values(@second_gp_entity, args)
  @second_gp_entity.save!

  # Mirror "there is an existing investor with users": an Investor row linking
  # the LP's investor entity to the new GP, plus an approved InvestorAccess for
  # the same LP user.
  @second_investor = FactoryBot.create(:investor,
                                       investor_entity_id: @investor_entity.id,
                                       entity_id: @second_gp_entity.id,
                                       investor_name: @investor_entity.name)
  @second_investor_access = InvestorAccess.create!(investor: @second_investor, user: @investor_user,
                                                   entity_id: @second_gp_entity.id,
                                                   first_name: @investor_user.first_name,
                                                   last_name: @investor_user.last_name,
                                                   email: @investor_user.email, approved: true)

  puts "\n####Second GP Entity####\n"
  puts @second_gp_entity.to_json
end

Given('the second GP entity has an active investor notice titled {string}') do |title|
  create_notice_for_gp(@second_gp_entity, @second_investor, title)
end

When('I visit the investor dashboard with GP {string} selected') do |gp_name|
  # Simulates picking a GP in the switcher dropdown: the switcher form submits
  # a GET to dashboard_entities_path with gp_entity_id (the turbo-frame swap in
  # the browser is this same request rendered inside the frame).
  gp = Entity.find_by!(name: gp_name)
  visit "/entities/dashboard?gp_entity_id=#{gp.id}"
end

Then('I should see the investor notice {string}') do |title|
  # Notice titles render in the carousel card header (_preview.html.erb), and
  # the carousel container id comes from _carousel.html.erb.
  within("#carouselExampleControls") do
    expect(page).to have_content(title, wait: 10)
  end
end

Then('I should not see the investor notice {string}') do |title|
  # Assert the carousel itself rendered first so the negative check cannot pass
  # vacuously on a broken page, then check :all text so notices hidden in
  # inactive carousel slides (display:none) are caught too.
  expect(page).to have_css("#carouselExampleControls", wait: 10)
  expect(page).to have_no_text(:all, title)
end
