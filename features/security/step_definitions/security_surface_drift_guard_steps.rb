# frozen_string_literal: true

# Steps for features/security/security_surface_drift_guard.feature.
# The surface itself is read by SecuritySurface (features/security/support/security_surface.rb).

# Compares the current surface with an allowlist and explains exactly what to do about each
# difference, because whoever sees this fail is usually not the person who wrote the guard.
def expect_surface_matches_allowlist(current, allowlist_name)
  allowlist = SecuritySurface.allowlist(allowlist_name)
  path = Pathname(SecuritySurface.allowlist_path(allowlist_name)).relative_path_from(Rails.root).to_s

  # Every entry must carry a reason; an empty reason defeats the review this list exists for.
  unexplained = allowlist.select { |_entry, reason| reason.to_s.strip.empty? }.keys
  expect(unexplained).to be_empty, "#{path}: these entries have no reason:\n  #{unexplained.join("\n  ")}"

  added = current - allowlist.keys
  stale = allowlist.keys - current
  message = +""
  if added.any?
    message << "NEW and not reviewed (check each one, then add it to #{path} with the reason it is safe):\n  "
    message << added.join("\n  ") << "\n"
  end
  message << "No longer present (delete from #{path}):\n  " << stale.join("\n  ") << "\n" if stale.any?
  expect(added + stale).to be_empty, message
end

Then("the actions without the {string} check match the allowlist {string}") do |check, allowlist_name|
  expect_surface_matches_allowlist(SecuritySurface.unprotected_actions.fetch(check), allowlist_name)
end

Then("the policy predicates that are always true match the allowlist {string}") do |allowlist_name|
  expect_surface_matches_allowlist(SecuritySurface.always_true_policy_predicates, allowlist_name)
end

Then("the views' raw output of non-literal values matches the allowlist {string}") do |allowlist_name|
  expect_surface_matches_allowlist(SecuritySurface.dynamic_raw_output, allowlist_name)
end

Then("the session cookie's SameSite protection is {string} or {string}") do |first, second|
  # session_store.rb sets no same_site of its own, so CookieStore installs a proc that defers to the
  # app-wide cookies_same_site_protection. A literal value set in session_store.rb would win instead.
  literal = Rails.application.config.session_options[:same_site]
  value = if literal.nil? || literal.respond_to?(:call)
            Rails.application.config.action_dispatch.cookies_same_site_protection
          else
            literal
          end
  value = value.call(ActionDispatch::TestRequest.create) if value.respond_to?(:call)
  expect([first.to_sym, second.to_sym]).to include(value&.to_sym),
                                           "cookies_same_site_protection is #{value.inspect}"
end

When("I request a documents download with back_to {string}") do |back_to|
  # The download itself is irrelevant here (and would queue a zip job): only the redirect is tested.
  allow(DocumentDownloadJob).to receive(:perform_later)
  begin
    page.driver.submit :post, download_documents_path, { back_to: }
    @redirect_outcome = page.current_url
  rescue ActionController::Redirecting::UnsafeRedirectError
    # action_on_open_redirect = :raise, and test.rb has show_exceptions = false, so the refusal
    # reaches the step as this error.
    @redirect_outcome = :refused
  end
end

Then("the redirect to another host is refused") do
  expect(@redirect_outcome).to eq(:refused), "Followed an off-site back_to to #{@redirect_outcome}"
end

Then("I am back on {string}") do |path|
  expect(URI(@redirect_outcome.to_s).path).to eq(path)
end
