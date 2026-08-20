# Step definitions for features/misc/investor_notice_carousel_owner_scoping.feature
#
# End-to-end check that InvestorNoticeJob-generated entries (owner-scoped or
# entity-wide — see InvestorNotice#investors) actually surface, or don't
# surface, in the real LP dashboard carousel via InvestorNotice.notices. The
# job-level investor_notice_owner_scoping.feature only asserts on
# InvestorNoticeEntry rows directly; this closes the loop by checking what an
# LP actually sees after logging in.
#
# Reuses @entity/@fund set by access_rights_cache_steps.rb's "there is an
# entity"/"there is a fund" steps, the notice-creation and job-run steps from
# investor_notice_owner_scoping_steps.rb, and the generic "I should (not) see
# the investor notice"/"I visit the investor dashboard" steps from
# investor_notice_carousel_steps.rb / data_room_steps.rb.

Given('there is an investor {string} with an approved login') do |investor_name|
  @carousel_investors ||= {}
  investor_entity = FactoryBot.create(:entity, entity_type: "Investor", name: "#{investor_name} Co")
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity, investor_name: investor_name)
  user = FactoryBot.create(:user, entity: investor_entity)
  InvestorAccess.create!(investor: investor, user: user, entity_id: @entity.id,
                          first_name: user.first_name, last_name: user.last_name,
                          email: user.email, approved: true)
  @carousel_investors[investor_name] = { investor: investor, user: user }
end

Given('investor {string} has access to the fund') do |investor_name|
  investor = @carousel_investors[investor_name][:investor]
  ar = AccessRight.new(owner: @fund, entity: @fund.entity, access_to_investor_id: investor.id)
  ar.permissions.set(:read)
  ar.save!
end

Given('I login as investor {string}') do |investor_name|
  @user = @carousel_investors[investor_name][:user]
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end
