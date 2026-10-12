# Shared setup for the evergreen feature files: builds the design's shared data (Alpha Long-Short
# Fund, folios, NAVs) directly through the models so each scenario starts from a known state.
# Shared setup — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenHelpers
  def enable_evergreen_for(entity)
    entity.permissions.set(:enable_evergreen_funds)
    entity.save!(validate: false)
  end

  # Make @fund evergreen with the given setting overrides; class A..Z initial price ₹10,000
  def make_fund_evergreen(fund, user, settings = {}, class_terms = {})
    enable_evergreen_for(fund.entity)
    terms = fund.unit_types_list.map { |u| { unit_type: u, initial_price: "10000" }.merge(class_terms) }
    result = EvergreenEnable.call(fund:, current_user: user, params: settings.merge(class_terms: terms))
    raise "EvergreenEnable failed: #{result[:errors]}" unless result.success?

    fund.reload.tap(&:reset_evergreen_cache)
  end

  # Parse "a=1;b=two" into a hash with numeric-looking values left as strings for the model
  def evergreen_kv(str)
    str.split(";").to_h { |pair| pair.split("=", 2).map(&:strip) }.symbolize_keys
  end

  # Visit a page, signing back in when travel_to has outlived the session cookie (expire_after is
  # stamped at the travelled time, so long jumps land on the login page).
  def evergreen_visit(path)
    visit(path)
    return unless page.has_css?("#user_email", wait: 0)

    steps %(
      And I am at the login page
      When I fill and submit the login page
    )
    visit(path)
  end

  # The settings form is a step wizard: press Next until the element is on the visible step
  def evergreen_wizard_reveal(css)
    9.times do
      break if page.has_css?(css, visible: true, wait: 0)

      first(".setup-content .nextBtn", visible: true).click
    end
    expect(page).to have_css(css, visible: true)
  end
end

World(EvergreenHelpers)
