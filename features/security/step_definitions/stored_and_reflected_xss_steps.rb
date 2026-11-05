# frozen_string_literal: true

# Steps for features/security/stored_and_reflected_xss.feature.
#
# Why these steps write the payload straight to the column (update_columns) instead of driving
# each edit form: the bug under test is on the RENDER side. Every one of these columns already
# accepts arbitrary text from its normal form or import, and the forms are not where the danger is.
# Writing the column directly keeps each scenario about one thing: does the page that shows the
# text turn it into live markup? It also keeps the scenarios fast and browser-free (@rack_test).
#
# Detection reads the served HTML with Nokogiri, so it works the same under rack_test and a real
# browser. An injected <img onerror> or <script> parsed into the DOM is exactly what a browser
# would execute.

module StoredXssHelpers
  # Bold text (allowed rich-text formatting) + an <img onerror> + a <script>. Each is tagged with a
  # unique marker so the check can never confuse the app's own scripts with the injected one.
  XSS_PAYLOAD = '<b>Wire by Friday</b> ' \
                '<img src="x" onerror="window.__xss_marker=1">' \
                '<script>window.__xss_marker=2</script>'

  # A user's first name is shorter and has no rich formatting, so its payload is just the handler.
  XSS_NAME_PAYLOAD = '<img src=x onerror="window.__xss_marker=3">'

  XSS_MARKER = "__xss_marker"

  # Every element the payload could have planted, found in the served HTML.
  def injected_nodes
    doc = Nokogiri::HTML(page.html)
    handlers = doc.xpath("//*[@*[starts-with(name(), 'on')]]").select do |node|
      node.attributes.any? { |name, attr| name.start_with?("on") && attr.value.include?(XSS_MARKER) }
    end
    scripts = doc.css("script").select { |node| node.text.include?(XSS_MARKER) }
    handlers + scripts
  end
end
World(StoredXssHelpers)

# ---- Writing the payload ------------------------------------------------------------------------

Given("the GP writes the XSS payload into the notes of the investor's remittance") do
  # The capital call step generated one remittance per committed investor (jobs run inline).
  @capital_remittance = CapitalRemittance.find_by!(capital_call_id: @capital_call.id, investor_id: @investor.id)
  @capital_remittance.update_columns(notes: StoredXssHelpers::XSS_PAYLOAD)
end

Given("the KYC's form has a custom field whose help text is the XSS payload") do
  # A KYC renders the custom fields of its own form type. Pin one explicitly, so the scenario never
  # passes vacuously because the KYC happened to have no form (and therefore no help text) at all.
  form_type = @investor_kyc.form_type ||
              @entity.form_types.find_by(name: @investor_kyc.class.name) ||
              @entity.form_types.find_by!(name: "InvestorKyc")
  @investor_kyc.update_columns(form_type_id: form_type.id)
  FormCustomField.create!(form_type:, name: "bank_statement_note", label: "Bank statement",
                          field_type: "TextField", position: 1, help_text: StoredXssHelpers::XSS_PAYLOAD)
end

Given("an employee writes the XSS payload into the distribution's notes") do
  @capital_distribution.update_columns(notes: StoredXssHelpers::XSS_PAYLOAD)
end

Given("an employee writes the XSS payload into the fund's details") do
  @fund.update_columns(details: StoredXssHelpers::XSS_PAYLOAD)
end

Given("an employee saves a notification template for the fund whose body is the XSS payload") do
  @custom_notification = CustomNotification.create!(entity: @entity, owner: @fund, subject: "Call notice",
                                                    body: StoredXssHelpers::XSS_PAYLOAD, email_method: "adhoc_notification",
                                                    for_type: "Fund", is_erb: false)
end

Given("the colleague has set their first name to the XSS name payload") do
  # Only presence is validated on first_name; update_columns keeps the 2FA setup intact.
  @colleague.update_columns(first_name: StoredXssHelpers::XSS_NAME_PAYLOAD)
end

# ---- Opening the page ---------------------------------------------------------------------------

When("I open the investor's remittance page") do
  visit(capital_remittance_path(@capital_remittance))
end

When("the investor opens their KYC form from the emailed signed link") do
  # The same signed link the KYC email carries (InvestorKyc.signed_id_for_user), opened with no
  # session, which is how an LP who is not signed in reaches the form.
  investor_user = @investor_user || @investor.users.first
  signed_id = InvestorKyc.signed_id_for_user(@investor_kyc, investor_user)
  visit(edit_investor_kyc_path(id: :shared, signed_id:))
end

# "I open the distribution page" (capital_distribution_journey_steps.rb) and "I open the fund page of
# {string}" (lp_gp_picker.rb) are reused from the existing steps: they visit the same pages.

When("I open that notification template") do
  visit(custom_notification_path(@custom_notification))
end

When("I reset the colleague's two-factor method") do
  # The admin reset posts from the colleague's user page. CSRF is off in the test env, so post directly.
  page.driver.submit :post, reset_two_factor_user_path(@colleague), { message: "Lost phone" }
end

When("I open the new financial statement account form with return_to {string}") do |return_to|
  visit(new_financial_statement_account_path(fund_id: @fund.id, return_to:))
end

When("I open the new financial statement mapping form with return_to {string}") do |return_to|
  visit(new_financial_statement_mapping_rule_path(fund_id: @fund.id, return_to:))
end

# ---- Assertions ---------------------------------------------------------------------------------

# Guards against a vacuous pass: the text must actually be on the page, so "no script" means the
# page rendered the field safely, not that it skipped the field.
Then("the page shows the payload's text {string}") do |text|
  expect(page).to have_text(text)
end

Then("the page shows the text {string}") do |text|
  expect(page).to have_text(text)
end

Then("the payload's bold text is still bold") do
  # Rich-text fields must keep their formatting: the fix is sanitize, not escape.
  expect(page).to have_css("b", text: "Wire by Friday")
end

Then("the page carries no injected script or event handler") do
  nodes = injected_nodes
  expect(nodes).to be_empty,
                   "User-entered text was rendered as live markup (XSS):\n#{nodes.map { |n| n.to_html[0, 160] }.join("\n")}"
end

Then("the Cancel link does not point at a javascript: URL") do
  link = find_link("Cancel")
  expect(link[:href].to_s.strip).not_to match(/\Ajavascript:/i)
end

Then("the Cancel link points at {string}") do |path|
  expect(find_link("Cancel")[:href]).to eq(path)
end

# ---- XSS-8 / 9 / 10 (fixes added after the first round) -----------------------------------------

Given("a colleague uploads a document to the fund whose name is the XSS name payload") do
  colleague = FactoryBot.create(:user, entity: @entity)
  folder = Folder.where(entity: @entity).first || FactoryBot.create(:folder, entity: @entity)
  @document = FactoryBot.create(:document, entity: @entity, folder:, owner: @fund, user: colleague,
                                           name: StoredXssHelpers::XSS_NAME_PAYLOAD)
end

When("I open that document's edit page") do
  visit(edit_document_path(@document))
end

Given("a colleague's change to the fund's custom fields put the XSS payload in the audit trail") do
  # The audit trail lists audits by the firm's employees (Audited::AuditPolicy::Scope), so the change
  # is recorded as a colleague's, the way Trackable records an edit of json_fields.
  colleague = FactoryBot.create(:user, entity: @entity)
  Audit.create!(auditable: @fund, user: colleague, action: "update",
                # A structured custom field (its value is itself a Hash): AuditChangeFlattener gives it one row
                # and the audit views draw a Hash through Json2table. A plain string value is printed escaped.
                audited_changes: { "json_fields" => [{ "bank_details" => { "note" => "Wire next week" } },
                                                     { "bank_details" => { "note" => StoredXssHelpers::XSS_PAYLOAD } }] })
end

When("I open the fund's audit trail") do
  visit(audits_path(auditable_type: "Fund", auditable_id: @fund.id))
end

Given("a colleague received a notification whose sent email contains the XSS payload") do
  colleague = FactoryBot.create(:user, entity: @entity)
  event = FinancialStatementNotifier.create!(record: @fund, params: { entity_id: @entity.id, periods: ["Q1"], unlocked_by: "Gita" })
  # The shape notifications/show reads: email["email"]["mail"]["body"]["raw_source"]
  email_html = "<html><head><style>p { color: #333 }</style></head><body><p>#{StoredXssHelpers::XSS_PAYLOAD}</p></body></html>"
  @notification = Noticed::Notification.create!(event:, recipient: colleague, entity_id: @entity.id,
                                                type: "FinancialStatementNotifier::Notification",
                                                email: { "email" => { "mail" => { "body" => { "raw_source" => email_html } },
                                                                      "params" => {}, "to" => colleague.email } })
end

When("I open that notification's page") do
  # I am not the recipient, so the page renders instead of redirecting to the record (NotificationsController#show)
  visit(notification_path(@notification))
end

Then("the email is shown in a sandboxed frame that cannot run scripts") do
  frame = Nokogiri::HTML(page.html).at_css("iframe[srcdoc]")
  expect(frame).to be_present, "The email was not put in a frame"
  expect(frame["srcdoc"]).to include("Wire by Friday")
  expect(frame["sandbox"]).to be_present
  expect(frame["sandbox"]).not_to include("allow-scripts")
end
