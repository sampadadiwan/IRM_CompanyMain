# Step definitions for features/misc/investor_notice_item_link.feature
#
# Covers InvestorNoticeLinkInterpolator: [user.xxx] variables in
# InvestorNoticeItem#link resolved per viewer at render time, the save-time
# validation that rejects an unsupported/sensitive path, and the support-only
# gate on the link field itself.
#
# Reuses @entity (access_rights_cache_steps.rb), @investor_notices
# (investor_notice_owner_scoping_steps.rb), and @carousel_investors + "I
# login as investor .../I log out" (investor_notice_carousel_owner_scoping_steps.rb).

Given('the investor notice {string} has a line item titled {string} with link {string}') do |title, item_title, link|
  @investor_notices[title].investor_notice_items.create!(
    title: item_title,
    details: "See details.",
    link: link
  )
end

Then('the investor notice item {string} should link to the investor\'s own entity sub_domain') do |item_title|
  investor_user = @carousel_investors["Link LP"][:user]
  expected_href = investor_user.entity.sub_domain
  within("#carouselExampleControls") do
    expect(page).to have_link(item_title, href: expected_href)
  end
end

Then('setting a line item link to {string} on the investor notice {string} should be rejected') do |link, title|
  item = @investor_notices[title].investor_notice_items.new(title: "Item", details: "See details.", link: link)
  expect(item.save).to be false
  expect(item.errors[:link]).to be_present
end

ITEM_LINK_FIELD_SELECTOR = "input[name*='investor_notice_items_attributes'][name$='[link]']".freeze

Then('the item link field should not be present') do
  # Scoped to the nested item's link (investor_notice[investor_notice_items_attributes][0][link])
  # — the notice's own [link] (image link) field is a separate, ungated field
  # that always renders, so a bare "[link]" substring match would false-negative here.
  expect(page).to have_no_css(ITEM_LINK_FIELD_SELECTOR)
end

Then('the item link field should be present') do
  expect(page).to have_css(ITEM_LINK_FIELD_SELECTOR)
end
