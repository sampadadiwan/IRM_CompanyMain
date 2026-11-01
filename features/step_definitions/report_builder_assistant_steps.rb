# frozen_string_literal: true

# Report Builder assistant ("Describe it") over HTTP, on the Acme fixture from
# report_builder_trust_steps.rb. The AI is always stubbed at
# LlmService.ruby_llm_chat: a fake chat answers by the prompt's first line
# (REPORT TABLE / REPORT SPEC) and keeps every prompt it was sent.
# Worked examples: openspec/changes/report-builder-assistant/business-rules.md

# A stand-in for a RubyLLM chat. `answers` maps a prompt marker to the replies
# in order (the last one repeats); a reply that is an Exception is raised.
class FakeReportAiChat
  Reply = Struct.new(:content)

  attr_reader :prompts

  def initialize(answers)
    @answers = answers.transform_values { |list| Array(list).dup }
    @prompts = []
  end

  def ask(prompt, **)
    @prompts << prompt
    marker = @answers.keys.find { |key| prompt.start_with?(key) }
    raise "no fake AI answer for #{prompt.lines.first}" unless marker

    queue = @answers[marker]
    reply = queue.size > 1 ? queue.shift : queue.first
    raise reply if reply.is_a?(Exception)

    Reply.new(reply.is_a?(String) ? reply : reply.to_json)
  end
end

module ReportBuilderAssistantWorld
  # The AI's "LP owing" draft (shared setup)
  def lp_owing_answer(extra_columns: [])
    {
      "spec" => {
        "root_model" => "Investor",
        "columns" => [{ "key" => "investor_name", "label" => "Investor" }, { "key" => "category", "label" => "Category" },
                      { "key" => "capital_commitments.committed_amount", "label" => "Committed", "total" => "sum" },
                      { "key" => "capital_commitments.call_amount", "label" => "Called", "total" => "sum" },
                      { "key" => "capital_commitments.collected_amount", "label" => "Collected", "total" => "sum" }] +
          extra_columns + [{ "formula" => "unpaid" }],
        "joins" => [{ "relation" => "capital_commitments" }],
        "root_filters" => { "category_eq" => "LP" },
        "formulas" => [{ "key" => "unpaid", "label" => "Unpaid",
                         "expression" => "[capital_commitments.call_amount] - [capital_commitments.collected_amount]" }],
        "sort" => { "key" => "unpaid", "dir" => "desc" }
      },
      "questions" => [{ "kind" => "pick_fund", "text" => "Which fund?" }],
      "assumptions" => ["owe money = Called − Collected"], "cannot" => [], "name" => "LPs owing on calls"
    }
  end

  def table_answer(model)
    { "root_model" => model, "cannot" => [] }
  end

  def fake_ai(answers)
    @fake_ai = FakeReportAiChat.new(answers)
    allow(LlmService).to receive(:ruby_llm_chat).and_return(@fake_ai)
  end

  def ai_prompts
    @fake_ai ? @fake_ai.prompts : []
  end

  def draft_path(suffix = nil)
    ["/report_builder/#{@draft.id}/draft", suffix].compact.join("/")
  end

  def latest_draft
    Report.where(category: ReportBuilder::Assistant::DRAFT_CATEGORY).order(:id).last
  end

  def draft_text
    Nokogiri::HTML(@last_rb_response.body).text.gsub(/[[:space:]]+/, " ")
  end

  def draft_doc
    Nokogiri::HTML(@last_rb_response.body)
  end

  # A request from inside the draft frame; the answer is the frame
  def draft_request(verb, suffix, params = {})
    rb_session.public_send(verb, draft_path(suffix), params: params, headers: { "Turbo-Frame" => "rb_draft_#{@draft.id}" })
    @last_rb_response = rb_session.response
  end

  def open_draft
    rb_session.get draft_path
    @last_rb_response = rb_session.response
  end

  # A spec-step answer with only these parts (E1–E3, X3, X5, chart rows)
  def simple_answer(root, columns, extra = {})
    { "spec" => { "root_model" => root, "columns" => columns }.merge(extra),
      "questions" => [], "assumptions" => [], "cannot" => [], "name" => "#{root} report" }
  end
end

World(ReportBuilderAssistantWorld)

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

Given("Acme has a default AI model") do
  @entity.entity_setting.update_columns(default_llm_model: "test-model")
end

Given("Acme has no AI model and there is no platform default") do
  @entity.entity_setting.update_columns(default_llm_model: nil)
  allow(ENV).to receive(:[]).and_call_original
  allow(ENV).to receive(:[]).with("DEFAULT_MODEL").and_return(nil)
end

Given("the AI drafts the LP owing report") do
  fake_ai("REPORT TABLE" => [table_answer("Investor")], "REPORT SPEC" => [lp_owing_answer])
end

Given("the AI then adds Distributed when refined") do
  distributed = { "key" => "capital_commitments.distribution_amount", "label" => "Distributed", "total" => "sum" }
  fake_ai("REPORT TABLE" => [table_answer("Investor")], "REPORT SPEC" => [lp_owing_answer(extra_columns: [distributed])])
end

Given("the AI picks {string} and answers with columns {string}") do |root, keys|
  columns = keys.split(",").map(&:strip).map do |key|
    label, column_key = key.include?("=") ? key.split("=", 2) : [nil, key]
    { "key" => column_key, "label" => label }.compact
  end
  @ai_answer = simple_answer(root, columns)
  fake_ai("REPORT TABLE" => [table_answer(root)], "REPORT SPEC" => [@ai_answer])
end

Given("the AI's answer also says it can't do {string}") do |text|
  @ai_answer["cannot"] = [text]
end

Given("the AI's answer filters the rows by {string} = {string}") do |pred_key, value|
  @ai_answer["spec"]["root_filters"] = { pred_key => value }
end

Given("the AI's answer filters the rows to Beta Partners' company") do
  @beta ||= build_fund_entity(name: "Beta Partners")
  @ai_answer["spec"]["root_filters"] = { "entity_id_eq" => @beta.id.to_s }
end

Given("the AI's answer assumes {string}") do |text|
  @ai_answer["assumptions"] = [text]
end

Given("the AI picks {string} as the table") do |root|
  fake_ai("REPORT TABLE" => [table_answer(root)], "REPORT SPEC" => [simple_answer(root, [])])
end

Given("the AI fails every time") do
  fake_ai("REPORT TABLE" => [Timeout::Error.new("execution expired")], "REPORT SPEC" => [Timeout::Error.new("execution expired")])
end

Given("the AI answers in prose every time") do
  fake_ai("REPORT TABLE" => ["Sure! The investors table is the right one."], "REPORT SPEC" => ["Here is your report."])
end

Given("the draft alerts are recorded") do
  @alerts = []
  allow(UserAlert).to receive(:new).and_wrap_original do |original, **kwargs|
    @alerts << kwargs[:message].to_s
    original.call(**kwargs)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Describe and draft
# ─────────────────────────────────────────────────────────────────────────────

When("I open Describe it") do
  rb_session.get "/report_builder/describe"
  @last_rb_response = rb_session.response
end

When("I describe {string}") do |question|
  rb_session.post "/report_builder/describe", params: { question: question }
  @last_rb_response = rb_session.response
  @draft = latest_draft
  follow_rb_redirect
end

Then("the New report menu offers Describe it") do
  rb_session.get "/reports"
  expect(Nokogiri::HTML(rb_session.response.body).css(".rb-new-report a").map { |a| a.text.strip }).to include("Describe it")
end

Then("the Describe page shows the question box and the template questions as examples") do
  expect(draft_doc.at_css("textarea[name='question']")).to be_present
  examples = draft_doc.css(".rb-describe-examples a").map { |a| a.text.strip }
  expect(examples).to include(ReportBuilderTemplates.all["lp_capital_account"]["question"])
end

Then("the Describe page says {string} and links to the templates") do |text|
  expect(draft_text).to include(text)
  expect(draft_doc.css("a").pluck("href")).to include("/report_builder/templates")
  expect(draft_doc.at_css(".rb-describe-form")).to be_nil
end

Then("the draft page shows the cards {string}") do |lines|
  cards = draft_doc.css(".rb-wizard-summary").text.gsub(/[[:space:]]+/, " ")
  lines.split("|").map(&:strip).each { |line| expect(cards).to include(line), "cards: #{cards}" }
end

Then("the draft asks {string} with the funds {string}") do |question, funds|
  form = draft_doc.at_css(".rb-draft-questions form")
  expect(form.text).to include(question)
  expect(form.css("select option").map { |o| o.text.strip }).to eq(funds.split(",").map(&:strip))
end

Then("the draft lists the assumption {string}") do |text|
  expect(draft_doc.css(".rb-draft-assumptions li").map { |li| li.text.strip }).to include(text)
end

Then("Couldn't do lists {string}") do |text|
  items = draft_doc.css(".rb-draft-cannot li").map { |li| li.text.gsub(/[[:space:]]+/, " ").strip }
  expect(items).to include(text), "couldn't do: #{items.inspect}"
end

Then("the draft has no preview and no Save") do
  expect(draft_doc.css(".rb-draft-save, turbo-frame#report_builder_preview")).to be_empty
end

Then("the draft has a preview and Save") do
  expect(draft_doc.at_css(".rb-draft-save")).to be_present
  expect(draft_doc.at_css("turbo-frame#report_builder_preview")).to be_present
end

When("I pick the fund {string} for the draft") do |fund|
  @prompts_before = ai_prompts.size
  draft_request(:post, "fund", fund_id: Fund.find_by!(entity_id: @entity.id, name: fund).id)
end

Then("no AI call was made for it") do
  expect(ai_prompts.size).to eq(@prompts_before)
end

When("I refine the draft with {string}") do |instruction|
  @prompts_before = ai_prompts.size
  draft_request(:post, "refine", instruction: instruction)
end

Then("the AI was sent the current report and {string}") do |instruction|
  prompt = ai_prompts.last
  expect(prompt).to start_with("REPORT SPEC")
  expect(prompt).to include("Current report spec")
  expect(prompt).to include("Instruction: #{instruction}")
end

Then("the report sent to the AI has no {string} column") do |key|
  current = ai_prompts.last[/Current report spec[^\n]*\n(.+)\nInstruction:/, 1]
  columns = JSON.parse(current)["columns"].filter_map { |c| c["key"] }
  expect(columns).not_to include(key)
end

Then("the draft's columns are {string}") do |labels|
  expect(@draft.reload.grid_view_preferences.reorder(:sequence).map { |g| g.label.presence || g.name }).to eq(labels.split(",").map(&:strip))
end

Then("the draft's {string} are limited to {string}") do |relation, fund|
  join = @draft.reload.template["joins"].find { |j| j["relation"] == relation }
  expect(join.dig("child_filters", "fund_id_eq")).to eq(Fund.find_by!(entity_id: @entity.id, name: fund).id.to_s)
end

Given("Meera removed {string} from the draft in the builder") do |key|
  @draft.grid_view_preferences.where(key: key).destroy_all
end

Then("the draft page says {string}") do |text|
  expect(draft_text).to include(text)
end

Then("the question {string} is still on the draft") do |question|
  expect(@draft.reload.template.dig("ai", "question")).to eq(question)
  expect(draft_doc.at_css(".rb-draft-question").text.strip).to eq(question)
end

Then("the AI was asked {int} times") do |count|
  expect(ai_prompts.size).to eq(count)
end

Then("the alert {string} links to the draft") do |text|
  alert = @alerts.find { |m| m.include?(text) }
  expect(alert).to be_present, "alerts: #{@alerts.inspect}"
  expect(alert).to include("/report_builder/#{@draft.id}/draft")
end

Then("the draft preview shows only Acme's investors") do
  names = Nokogiri::HTML(@last_rb_response.body).css("turbo-frame#report_builder_preview table tbody tr td:first-child").map { |td| td.text.strip }
  acme_names = Investor.where(entity_id: @entity.id).pluck(:investor_name)
  expect(names).not_to be_empty
  names.each { |name| expect(acme_names.include?(name) || name.start_with?("Total")).to be(true), "not Acme's: #{name}" }
end

Given("the draft is still drafting") do
  ai = @draft.reload.template["ai"].merge("status" => "drafting", "started_at" => Time.current.iso8601)
  @draft.update!(template: @draft.template.merge("ai" => ai))
end

# ─────────────────────────────────────────────────────────────────────────────
# Save, discard, privacy, clean-up
# ─────────────────────────────────────────────────────────────────────────────

When("I save the draft as {string}") do |name|
  rb_session.patch draft_path("save"), params: { name: name }
  @last_rb_response = rb_session.response
end

When("I fine-tune the draft in the builder") do
  rb_session.patch draft_path("save"), params: { name: "", fine_tune: "1" }
  @last_rb_response = rb_session.response
end

Then("I land on the report page of {string}") do |name|
  expect(@last_rb_response).to be_redirect
  expect(@last_rb_response.location).to end_with("/report_builder/#{@draft.id}/view")
  expect(@draft.reload.name).to eq(name)
end

Then("I land on the builder") do
  expect(@last_rb_response.location).to end_with("/report_builder/#{@draft.id}/edit")
end

Then("the report is no longer a draft and its description is {string}") do |question|
  @draft.reload
  expect(@draft.category).to be_nil
  expect(@draft.template).not_to have_key("draft")
  expect(@draft.description).to eq(question)
end

When("I discard the draft") do
  @discarded_id = @draft.id
  rb_session.delete draft_path
  @last_rb_response = rb_session.response
end

Then("the draft is deleted and I am back on Describe") do
  expect(Report.exists?(@discarded_id)).to be(false)
  expect(@last_rb_response.location).to end_with("/report_builder/describe")
end

Given("Ravi of Acme is signed in") do
  ravi = FactoryBot.create(:user, entity: @entity, first_name: "Ravi", permissions: User.permissions.keys)
  @rb_session = nil
  rb_sign_in(ravi)
end

Then("the Reports page {word} {string}") do |verb, name|
  rb_session.get "/reports"
  names = Nokogiri::HTML(rb_session.response.body).css(".note-title a").map { |a| a.text.strip }
  verb == "lists" ? expect(names).to(include(name)) : expect(names).not_to(include(name))
end

When("he opens the draft's address") do
  rb_request_or_not_found(:get, draft_path)
end

When("he refines the draft") do
  rb_request_or_not_found(:post, draft_path("refine"), instruction: "show everything")
end

Then("he is refused") do
  expect(@not_found || !@last_rb_response.status.between?(200, 299)).to be(true)
  expect(@last_rb_response.location.to_s).not_to include("/draft") if @last_rb_response&.redirect?
end

Given("drafts untouched for {int} and {int} days, and a report saved {int} days ago") do |old_days, new_days, saved_days|
  make = lambda do |name, category, days|
    report = Report.create!(entity: @entity, user: @user, curr_role: @user.curr_role, name: name, category: category,
                            report_builder: true, url: "/report_builder",
                            template: { "root_model" => "Investor", "draft" => category.present? })
    report.update_columns(updated_at: days.days.ago)
    report
  end
  @old_draft = make.call("Old draft", ReportBuilder::Assistant::DRAFT_CATEGORY, old_days)
  @new_draft = make.call("New draft", ReportBuilder::Assistant::DRAFT_CATEGORY, new_days)
  @saved     = make.call("Saved report", nil, saved_days)
end

When("the draft clean-up runs") do
  ReportDraftCleanupJob.perform_now
end

Then("only the {int}-day-old draft is deleted") do |_days|
  expect(Report.exists?(@old_draft.id)).to be(false)
  expect(Report.exists?(@new_draft.id)).to be(true)
  expect(Report.exists?(@saved.id)).to be(true)
end
