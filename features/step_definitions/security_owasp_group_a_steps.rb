# Step definitions for features/security/owasp_group_a_2026_11.feature — the OWASP review's Group A (code-only
# Medium) fixes. docs/security/owasp_2026_11_changes.md › "Group A". Reused: "there is a user … for an entity …"
# (features/common.rb), "there is a fund … for the entity" (fund.rb).

# ── M3 — vendor keys encrypted at rest ──────────────────────────────────────────────────────────────────────────

When("the entity's Anthropic key is set to {string}") do |value|
  @group_a_setting = @entity.entity_setting
  @group_a_setting.update!(anthropic_api_key: value)
end

def group_a_raw_anthropic_key
  ActiveRecord::Base.connection.select_value("SELECT anthropic_api_key FROM entity_settings WHERE id = #{@group_a_setting.id.to_i}")
end

Then("the stored Anthropic key column does not contain {string}") do |value|
  raw = group_a_raw_anthropic_key
  expect(raw).to be_present
  expect(raw).not_to include(value)
end

Then("the entity setting's Anthropic key reads {string}") do |value|
  expect(EntitySetting.find(@group_a_setting.id).anthropic_api_key).to eq(value)
end

Then("the stored Anthropic key column is empty") do
  expect(group_a_raw_anthropic_key).to be_nil
end

# ── M5 — database dump link lifetime ────────────────────────────────────────────────────────────────────────────

Then("the emailed download link for a document tagged {string} lasts {string}") do |tag, duration|
  expected = { "1 hour" => 1.hour, "7 days" => 7.days }.fetch(duration)
  expect(DocumentMailer.download_link_ttl(Document.new(owner_tag: tag))).to eq(expected)
end

# ── M6 — no tokens while impersonating ──────────────────────────────────────────────────────────────────────────

Then("the user may create an API token in their own session") do
  user = User.find(@user.id)
  expect(ApiTokenPolicy.new(user, ApiToken).create?).to be(true)
end

Then("the user may not create an API token while support is signed in as them") do
  user = User.find(@user.id)
  user.support_user_id = 999_999 # what WithAuthentication sets from session[:support_user_id]
  expect(ApiTokenPolicy.new(user, ApiToken).create?).to be(false)
end

Then("the API token page shows New token disabled with the reason") do
  page_html = Nokogiri::HTML5(@docs_session.response.body)
  expect(page_html.at_css("#create_api_token")).to be_nil
  disabled = page_html.at_css("#create_api_token_disabled")
  expect(disabled).not_to be_nil
  expect(disabled["title"]).to include("can't be created while you are signed in as another user")
  expect(page_html.at_css("#api_token_support_help").text.squish).to include("Ask the user to create the token")
end

# ── M7 — Outlook add-in confirm step ────────────────────────────────────────────────────────────────────────────

def group_a_session
  @group_a_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
    # M8 — a support / super user answers the two-factor code step (RequiredTwoFactorSignIn)
    integration_sign_in(session, @user)
  end
end

When("I open the Outlook add-in sign-in page") do
  group_a_session.get "/outlook_addin/oauth_start"
end

When("I confirm the Outlook add-in connection") do
  group_a_session.post "/outlook_addin/oauth_start"
end

Then("the Outlook add-in page asks to connect and holds no token") do
  body = group_a_session.response.body
  expect(group_a_session.response.status).to eq(200)
  expect(body).to include("outlook_addin_confirm")
  expect(body).not_to include("token-payload")
  expect(body).not_to include("access_token")
end

Then("the Outlook add-in page hands over a token") do
  body = group_a_session.response.body
  expect(group_a_session.response.status).to eq(200)
  expect(body).to include("token-payload")
  expect(body).to include("access_token")
end

# ── M9 / M10 — scripts from other sites ─────────────────────────────────────────────────────────────────────────

def group_a_cdn_script_tags
  Rails.root.glob("app/**/*.erb").flat_map do |path|
    File.read(path).scan(%r{<script\b[^>]*\bsrc=(["'])(https?://[^"']+)\1[^>]*>}i).map do |_quote, url|
      tag = File.read(path)[/<script\b[^>]*\bsrc=["']#{Regexp.escape(url)}["'][^>]*>/i]
      { path: path.relative_path_from(Rails.root).to_s, url:, tag: }
    end
  end
end

Then("every CDN script tag in the app's views has an integrity hash, except:") do |table|
  allowed = table.hashes.pluck("url")
  missing = group_a_cdn_script_tags.reject { |t| t[:tag].to_s.include?("integrity=") || allowed.include?(t[:url]) }
  expect(missing).to be_empty, "scripts without integrity: #{missing.map { |t| "#{t[:path]} #{t[:url]}" }.join(', ')}"
end

Then("no CDN script URL uses {string} or an unversioned major") do |latest|
  floating = group_a_cdn_script_tags.select { |t| t[:url].include?(latest) || t[:url].match?(%r{@\d+/}) }
  expect(floating).to be_empty, "floating versions: #{floating.pluck(:url).join(', ')}"
end

def group_a_version(text)
  Gem::Version.new(text.to_s)
end

Then("the import map pins {string} at version {string} or later") do |name, version|
  line = Rails.root.join("config/importmap.rb").read[/^pin "#{Regexp.escape(name)}".*$/]
  pinned = line.to_s[/@(\d+\.\d+\.\d+)/, 1]
  expect(group_a_version(pinned)).to be >= group_a_version(version)
end

Then("the import map loads Mermaid {string} or later") do |version|
  line = Rails.root.join("config/importmap.rb").read[/^pin "mermaid".*$/]
  pinned = line.to_s[/mermaid@(\d+\.\d+\.\d+)/, 1]
  expect(group_a_version(pinned)).to be >= group_a_version(version)
end

# ── M12 — security event counters ───────────────────────────────────────────────────────────────────────────────

Then("a failed sign-in with a wrong password is counted as {string}") do |event|
  allow(SecurityMetrics).to receive(:event).and_call_original
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: @user.email, password: "wrong-password" } }
  expect(SecurityMetrics).to have_received(:event).with(event.to_sym, reason: anything)
end

Then("an unknown security event name is ignored") do
  expect { SecurityMetrics.event(:not_an_event, reason: "x") }.not_to raise_error
  expect(SecurityMetrics.event(:not_an_event)).to be_nil
end

# ── M15 — dashboard owner lookup ────────────────────────────────────────────────────────────────────────────────

Given("another firm has a fund {string}") do |name|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Group A Other Firm")
  @group_a_other_fund = FactoryBot.create(:fund, entity: other, name:)
end

# The helper as a view would call it: policy_scope is the signed-in user's
def group_a_dashboard_helper
  user = User.find(@user.id)
  Object.new.tap do |helper|
    helper.extend(DashboardWidgetsHelper)
    helper.define_singleton_method(:policy_scope) { |scope| Pundit.policy_scope!(user, scope) }
  end
end

Then("the dashboard owner for the user's own fund is that fund") do
  expect(group_a_dashboard_helper.dashboard_owner({ owner_type: "Fund", owner_id: @fund.id })).to eq(@fund)
end

Then("the dashboard owner for the other firm's fund is refused") do
  expect { group_a_dashboard_helper.dashboard_owner({ owner_type: "Fund", owner_id: @group_a_other_fund.id }) }
    .to raise_error(ActiveRecord::RecordNotFound)
end

Then("the dashboard owner of type {string} is refused") do |type|
  expect { group_a_dashboard_helper.dashboard_owner({ owner_type: type, owner_id: @user.id }) }
    .to raise_error(ActiveRecord::RecordNotFound)
end

# ── M18 — images in AI answers ──────────────────────────────────────────────────────────────────────────────────

def group_a_markdown(text)
  Object.new.extend(MarkdownHelper).markdown_to_html(text).to_s
end

Then("rendering the AI markdown {string} shows no image") do |markdown|
  expect(group_a_markdown(markdown)).not_to include("<img")
end

Then("rendering the AI markdown {string} shows the image") do |markdown|
  expect(group_a_markdown(markdown)).to include("<img")
end

# ── M19 — deal-ingest sender checks ─────────────────────────────────────────────────────────────────────────────

Then("a deal-ingest email with these authentication details is judged:") do |table|
  table.hashes.each do |row|
    params = ActionController::Parameters.new(
      to: "deal-1@ingest.test", from: "gp@fund.com", headers: "#{row['headers']}\nMessage-ID: <x@test>",
      SPF: row["sendgrid_spf"].presence, dkim: row["sendgrid_dkim"].presence
    )
    result = DealIngestAuthenticator.new(params).send(:verify_email_auth)
    expect(result.success ? "yes" : "no").to eq(row["accepted"]), "#{row.inspect} → #{result.reason}"
  end
end
