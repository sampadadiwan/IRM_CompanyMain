# Steps for features/core/turbo_session_expiry.feature
#
# Strategy: instead of building a dedicated broken endpoint, we inject a probe
# <turbo-frame> via JS pointing at a real page. Because no real page contains a
# frame with the probe's id, this genuinely triggers turbo:frame-missing:
#   - with a valid session   -> the "section couldn't load" error card
#   - with an expired session -> Devise redirects the frame fetch to sign-in,
#     which the JS handler promotes to a full-page visit

PROBE_FRAME_ID = "cucumber_probe_frame".freeze

When('I visit the entity dashboard') do
  visit("/entities/dashboard")
  # Wait for the page (and the frame-error <template> in the layout) to be ready
  expect(page).to have_css("#turbo-frame-error-template", visible: :all, wait: 15)
end

When('my session has expired') do
  # Deleting the browser cookies is equivalent to the rolling 60-minute session
  # cookie expiring: the next request arrives unauthenticated. The page itself
  # stays on screen, exactly like a user returning to a stale tab.
  page.driver.with_playwright_page do |pw_page|
    pw_page.context.clear_cookies
  end
end

When('a turbo frame on the page loads {string}') do |src|
  # Prepend the probe frame to the main content area (not body) so the error
  # card renders at the top of the page, visible without scrolling.
  # Setting src makes Turbo fetch it immediately.
  page.execute_script(<<~JS)
    const frame = document.createElement("turbo-frame");
    frame.id = #{PROBE_FRAME_ID.to_json};
    frame.setAttribute("src", #{src.to_json});
    (document.querySelector("main") || document.body).prepend(frame);
  JS
end

Then('I should be redirected to the sign in page with a session message') do
  # The frame-missing handler must break out of the frame into a full-page
  # visit, landing on sign-in with the Devise flash explaining what happened
  expect(page).to have_current_path("/users/sign_in", wait: 15)
  expect(page).to have_content("You need to sign in or sign up before continuing.")
end

Then('I should be back on the entity dashboard page') do
  # Exact path assertion: proves TurboFailureApp stored the referer (the page
  # the user was on) and not the frame endpoint ("?from_frame=1") nor the
  # root fallback ("/")
  expect(page).to have_current_path("/entities/dashboard", wait: 15)
end

Then('I should see the section load error card') do
  within("turbo-frame##{PROBE_FRAME_ID}") do
    expect(page).to have_css(".turbo-frame-error", wait: 15)
    expect(page).to have_content("This section couldn't load.")
    expect(page).to have_button("Retry")
  end
end

When('I pause so the error card can be seen') do
  # Purely for humans watching the browser during the run — gives time to see
  # the rendered error card before the retry click replaces it
  sleep(5)
end

When('I click retry on the section load error card') do
  within("turbo-frame##{PROBE_FRAME_ID}") do
    # Stamp the current card so the next assertion can prove Retry actually
    # re-fetched the frame (a fresh card won't carry the stamp)
    page.execute_script(
      "document.querySelector('turbo-frame##{PROBE_FRAME_ID} .turbo-frame-error').setAttribute('data-stale-card', 'true')"
    )
    click_on("Retry")
  end
end

Then('a fresh section load error card replaces the stale one') do
  within("turbo-frame##{PROBE_FRAME_ID}") do
    # The stale stamp must be gone: proves frame.reload() re-fetched and the
    # handler re-rendered the card, rather than the old card just sitting there
    expect(page).to have_css(".turbo-frame-error", wait: 15)
    expect(page).to have_no_css(".turbo-frame-error[data-stale-card]", wait: 15)
    expect(page).to have_content("This section couldn't load.")
  end
end
