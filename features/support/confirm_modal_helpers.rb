# Clicking something that may or may not ask for confirmation in the shared #confirmModal.
#
# Steps used to click and then `if page.has_css?("#confirmModal", wait: 5)` - which costs the full 5 s
# on every click that does NOT open the modal. Whether it will open is known before clicking: elements
# that ask carry data-action "click->confirm#popup" (confirm_controller.js, ~250 of them).
module ConfirmModalHelpers
  # Clicks `element` and, if it asks for confirmation, waits for #confirmModal and clicks Proceed.
  # `proceed_wait` widens the wait for Proceed's own navigation (see "I approve all staged KPIs").
  def click_and_confirm_if_asked(element, proceed_wait: nil)
    asks = element[:"data-action"].to_s.include?("confirm#popup")
    element.click
    # rack_test runs no JS: the click submits directly and no modal ever opens
    return if page.driver.is_a?(Capybara::RackTest::Driver)

    # A few controllers open the modal from their own JS rather than via data-action
    # (e.g. portfolio_agent_runner_controller.js) - give those a short look, not the full wait.
    return unless asks || page.has_css?("#confirmModal", wait: 1)

    within(find("#confirmModal", visible: true)) do
      if proceed_wait
        using_wait_time(proceed_wait) { click_on I18n.t("common.proceed") }
      else
        click_on I18n.t("common.proceed")
      end
    end
  end
end

World(ConfirmModalHelpers)
