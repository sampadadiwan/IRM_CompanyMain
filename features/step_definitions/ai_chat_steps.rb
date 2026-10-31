# frozen_string_literal: true

# AI chat kit — features/ai_chat/*.feature.
# @see openspec/changes/ai-chat-kit/design.md#worked-examples

# E8, X6, E7 — AiChatHelper#ai_answer_html, called as a view would.
Given('an answer:') do |markdown|
  @answer_markdown = markdown
end

When('it is rendered in {word} mode') do |mode|
  @rendered_answer = Nokogiri::HTML5.fragment(ApplicationController.helpers.ai_answer_html(@answer_markdown, mode: mode.to_sym).to_s)
end

Then('the rendered answer has a chart canvas') do
  expect(@rendered_answer.css("canvas[data-controller='chart-renderer']")).not_to be_empty
end

Then('the rendered answer has no chart canvas') do
  expect(@rendered_answer.css("canvas")).to be_empty
end

Then('the rendered answer says {string}') do |text|
  expect(@rendered_answer.text).to include(text)
end

Then('the rendered answer has no script and no inline event handler') do
  expect(@rendered_answer.css("script")).to be_empty
  expect(@rendered_answer.to_html).not_to match(/\son\w+=/i)
end

Then('the rendered answer has a table in a card') do
  expect(@rendered_answer.css(".card .table-responsive table.table")).not_to be_empty
end

Then('the rendered answer has no italics') do
  expect(@rendered_answer.css("em")).to be_empty
end

# ---- Assistants page (features/ai_chat/assistants_page.feature) --------------------------------------

ASSISTANT_CLASSES = [FundAssistant, SpecificFundAssistant, PortfolioAssistant, PortfolioCompanyAssistant,
                     CapitalCommitmentAssistant].freeze

Given('{string} is a fund manager at {string} with the fund {string}') do |full_name, entity_name, fund_name|
  first_name, last_name = full_name.split(" ", 2)
  @entity = FactoryBot.create(:entity, name: entity_name, entity_type: "Investment Fund")
  @user = FactoryBot.create(:user, entity: @entity, first_name:, last_name:)
  @user.add_role(:company_admin)
  @fund = FactoryBot.create(:fund, entity: @entity, name: fund_name)
  log_in(@user)
end

# A Specific Fund Assistant chat for the fund, last changed at `time`, with its questions (and an answer each).
def assistant_chat_with(fund_name, questions, time: Time.current, answer: "Answered.", type: "SpecificFundAssistant")
  owner = type == "FundAssistant" ? @user : Fund.find_by!(name: fund_name)
  chat = Chat.create!(user: @user, entity: @entity, owner:, assistant_type: type, name: "#{owner} Chat")
  Array(questions).each do |question|
    chat.messages.create!(role: "user", content: question, created_at: time, updated_at: time)
    chat.messages.create!(role: "assistant", content: answer, created_at: time, updated_at: time)
  end
  # Messages touch the chat; put its "last changed" back to the example's time.
  chat.update_columns(created_at: time, updated_at: time)
  chat
end

# "today 09:15" or "2026-10-28" (noon that day).
def example_time(text)
  return Time.zone.now.change(hour: Regexp.last_match(1).to_i, min: Regexp.last_match(2).to_i) if text =~ /\Atoday (\d\d):(\d\d)\z/

  Date.parse(text).in_time_zone.change(hour: 12)
end

Given('Priya has Specific Fund Assistant chats on {string}:') do |fund_name, table|
  table.hashes.each { |row| assistant_chat_with(fund_name, row["question"], time: example_time(row["last changed"])) }
end

Given('Priya has {int} Specific Fund Assistant chats on {string}') do |count, fund_name|
  count.times { |i| assistant_chat_with(fund_name, "Question #{i + 1}", time: (i + 1).minutes.ago) }
end

Given('Priya has a Specific Fund Assistant conversation on {string} answered with a table') do |fund_name|
  assistant_chat_with(fund_name, "Which LPs are overdue?", answer: "Overdue:\n\n| Investor | Overdue |\n|---|---|\n| Mehta Family | 40,00,000 |")
end

Given('Priya has a Specific Fund Assistant conversation on {string} answered {string}') do |fund_name, answer|
  assistant_chat_with(fund_name, "Which ids?", answer:)
end

When('Priya opens the Specific Fund Assistant for {string}') do |fund_name|
  visit assistant_path("assistant", assistant_type: "SpecificFundAssistant", owner_id: Fund.find_by!(name: fund_name).id, owner_type: "Fund")
end

When('Priya opens the Specific Fund Assistant for {string} in locale {string}') do |fund_name, locale|
  page.driver.header("Accept-Language", locale)
  step %(Priya opens the Specific Fund Assistant for "#{fund_name}")
end

When('Priya opens the Fund Assistant') do
  visit assistant_path("assistant", assistant_type: "FundAssistant")
end

Then('the assistant sidebar lists {string} under {string} with {string}') do |question, group, meta|
  within("#assistant-conversations") do
    row = find(".aic-conversation", text: question)
    expect(row).to have_css("[data-role='meta']", text: meta)
    # The row's group is the nearest group label above it.
    expect(row.find(:xpath, "preceding-sibling::div[@data-group][1]")["data-group"]).to eq(group)
  end
end

Then('the assistant sidebar shows {int} conversation titled {string}') do |count, title|
  rows = all("#assistant-conversations .aic-conversation")
  expect(rows.size).to eq(count)
  expect(rows.first).to have_css("[data-role='first-question']", text: title)
end

Then('the assistant sidebar shows {int} conversations and says {string}') do |count, label|
  expect(all("#assistant-conversations .aic-conversation").size).to eq(count)
  expect(page).to have_css(".aic-sidebar .border-top", text: label)
end

Then('the assistant header names {string} and links to {string}') do |name, record|
  within("#assistant-chat .aic-header") do
    expect(page).to have_content(name)
    expect(page).to have_link(record)
  end
end

Then('the assistant header names {string} without a record link') do |name|
  within("#assistant-chat .aic-header") { expect(page).to have_content(name) }
  # The Export menu's Efficiency Report link sits in the dropdown, not in the header line itself.
  expect(page).to have_no_css("#assistant-chat .aic-header > a")
end

Then('the thread greets {string}') do |greeting|
  within("#assistant-chat") { expect(page).to have_content(greeting) }
end

Then('the thread shows {string} without italics') do |text|
  within("#assistant-chat-items") do
    expect(page).to have_content(text)
    expect(page).to have_no_css("em")
  end
end

Then('the exported answers include a table inside the answer body') do
  expect(page).to have_css("[data-ppt-export-target='responses'][data-slideshow-target='source'] " \
                           "[data-ai-chat-answer] [data-ai-chat-answer-body] .card table")
end

Then('the chat shows no Font Awesome or Bootstrap Icons') do
  classes = Nokogiri::HTML(page.html).css(".ai-chat [class]").flat_map { |node| node["class"].split }
  expect(classes.grep(/\A(fa|fas|far|fab|fa-.+|bi|bi-.+)\z/)).to be_empty
end

# The assistant itself is stubbed: these steps fix what every assistant's #run returns.
Given('the assistant answers:') do |text|
  ASSISTANT_CLASSES.each { |klass| allow_any_instance_of(klass).to receive(:run).and_return(OpenStruct.new(content: text)) }
end

Given('the assistant answers {string}') do |text|
  ASSISTANT_CLASSES.each { |klass| allow_any_instance_of(klass).to receive(:run).and_return(OpenStruct.new(content: text)) }
end

Given('the assistant times out') do
  ASSISTANT_CLASSES.each { |klass| allow_any_instance_of(klass).to receive(:run).and_raise(Timeout::Error) }
end

Given('speech is transcribed as {string}') do |text|
  allow(RubyLLM).to receive(:transcribe).and_return(OpenStruct.new(text:))
end

# The open conversation, from the question box (as the browser would send it).
def open_assistant_chat_id
  find("#assistant-composer input[name='chat_id']", visible: :all).value
end

# Posts as Turbo does (Accept: turbo-stream) and keeps the stream the server answered with.
def post_turbo_stream(path, params)
  page.driver.browser.post(path, params, { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" })
  expect(page.driver.browser.last_response.status).to eq(200)
  @stream = Nokogiri::HTML5.fragment(page.driver.browser.last_response.body)
end

When('Priya asks the assistant {string}') do |question|
  post_turbo_stream(ask_assistants_path, { query: question, chat_id: open_assistant_chat_id })
end

When('Priya sends a voice question') do
  audio = Rack::Test::UploadedFile.new(StringIO.new("a" * 2000), "audio/webm", original_filename: "voice.webm")
  post_turbo_stream(transcribe_assistants_path, { audio:, chat_id: open_assistant_chat_id })
end

Then('the response adds the question {string} with {string} under it') do |question, pending|
  appended = @stream.at_css("turbo-stream[action='append'][target='assistant-chat-items'] template")
  html = Nokogiri::HTML5.fragment(appended.inner_html)
  expect(html.at_css(".aic-question").text.strip).to eq(question)
  expect(html.at_css("[data-ai-chat-answer]").text).to include(pending)
end

Then('the response puts the question box in its working state') do
  box = @stream.at_css("turbo-stream[action='replace'][target='assistant-composer'] template")
  expect(box.inner_html).to include('data-ai-chat-composer-running-value="true"')
end

# The job's broadcast of the answer (replacing the pending one), rendered as the browser would get it.
def live_answer_html
  update = @live_updates.rfind { |u| u[:target].to_s.start_with?("assistant_response_") }
  expect(update).to be_present
  Nokogiri::HTML5.fragment(ApplicationController.render(partial: update[:partial], locals: update[:locals]))
end

def live_composer_update
  @live_updates.rfind { |u| u[:target] == "assistant-composer" }.tap { |u| expect(u).to be_present }
end

Then('the live answer replaces the pending one with a table in a card') do
  html = live_answer_html
  expect(html.css(".card .table-responsive table")).not_to be_empty
  expect(html.text).not_to include("Thinking…")
end

Then('the live question box is ready again') do
  update = live_composer_update
  expect(update[:locals][:running]).to be(false)
  expect(update[:locals][:value]).to be_nil
end

Then('the live answer reads {string} with {string}') do |badge, reason|
  html = live_answer_html
  expect(html.at_css(".badge").text).to include(badge)
  expect(html.text).to include(reason)
end

Then('the live question box holds {string}') do |question|
  expect(live_composer_update[:locals][:value]).to eq(question)
end
