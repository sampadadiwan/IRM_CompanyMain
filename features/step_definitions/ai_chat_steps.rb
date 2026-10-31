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

# ---- Record analysis chat (features/ai_chat/kpi_chat.feature) ------------------------------------------

Given('Priya has a chat about {string} that asked {string}') do |fund_name, question|
  @chat = Chat.create!(user: @user, entity: @entity, owner: Fund.find_by!(name: fund_name), name: "#{fund_name} analysis")
  @chat.messages.create!(role: "user", content: question)
  @chat.messages.create!(role: "assistant", content: "Q2 was steady.")
end

# Chat#ask is stubbed as RubyLLM streams: it saves the question and an empty answer, then yields chunks.
def stub_chat_ask(chunks: [], error: nil)
  allow_any_instance_of(Chat).to receive(:ask) do |chat, content, with: [], &block| # rubocop:disable Lint/UnusedBlockArgument -- RubyLLM passes with:
    raise error if error

    chat.messages.create!(role: "user", content:)
    chat.messages.create!(role: "assistant", content: "")
    chunks.each { |text| block.call(OpenStruct.new(content: text)) }
  end
end

Given('the chat model streams {string}') do |text|
  stub_chat_ask(chunks: text.split(/(?<=\s)/))
end

Given('the chat model streams nothing') do
  stub_chat_ask
end

Given('the chat model fails with {string}') do |message|
  stub_chat_ask(error: StandardError.new(message))
end

Given('alerts are recorded') do
  @alerts = []
  allow_any_instance_of(ChatStreamJob).to receive(:send_notification) { |_job, *args| @alerts << args }
end

When('Priya opens that chat') do
  visit chat_path(@chat)
end

When('Priya sends {string} in the chat') do |question|
  post_turbo_stream(send_message_chat_path(@chat), { user_content: question })
end

Then('the chat sidebar lists {string}') do |question|
  within("#chat-conversations") { expect(page).to have_css(".aic-conversation", text: question) }
end

Then('the chat response adds the question {string} with {string} under it') do |question, pending|
  appended = @stream.at_css("turbo-stream[action='append'][target='chat-panel-items'] template")
  html = Nokogiri::HTML5.fragment(appended.inner_html)
  expect(html.at_css(".aic-question").text.strip).to eq(question)
  expect(html.at_css("[data-ai-chat-answer]").text).to include(pending)
end

def chat_answer_updates
  @live_updates.select { |u| u[:target].to_s.start_with?("chat_response_") }
end

def render_live(update)
  Nokogiri::HTML5.fragment(ApplicationController.render(partial: update[:partial], locals: update[:locals]))
end

Then('the live chat answer streamed before it finished') do
  statuses = chat_answer_updates.map { |u| u[:locals][:item].status }
  expect(statuses).to include(:running)
  expect(statuses.last).to eq(:answered)
end

Then('the live chat answer shows {string}') do |text|
  expect(render_live(chat_answer_updates.last).text).to include(text)
end

Then('the live chat answer reads {string}') do |badge|
  expect(render_live(chat_answer_updates.last).at_css(".badge").text).to include(badge)
end

Then('the live chat question box is ready again') do
  update = @live_updates.rfind { |u| u[:target] == "chat-composer" }
  expect(update[:locals]).to include(running: false, value: nil)
end

Then('the live chat question box holds {string}') do |question|
  expect(@live_updates.rfind { |u| u[:target] == "chat-composer" }[:locals][:value]).to eq(question)
end

Then('there is no document picker') do
  expect(page).to have_no_css("#chat-document")
end

Then('Priya is alerted {string}') do |message|
  expect(@alerts).to include([message, @user.id, :alert])
end

Given('{string} of {string} is signed in') do |full_name, entity_name|
  first_name, last_name = full_name.split(" ", 2)
  entity = FactoryBot.create(:entity, name: entity_name, entity_type: "Investment Fund")
  @other_user = FactoryBot.create(:user, entity:, first_name:, last_name:)
  @other_user.add_role(:company_admin)
  log_in(@other_user)
end

When("Arjun opens Priya's chat") do
  visit chat_path(@chat)
end

Then("the chat's questions are not shown") do
  expect(page).to have_no_content("Summarise Q2")
  expect(page).to have_no_css("#chat-panel")
end

# ---- Floating agent window (features/ai_chat/floating_window.feature) ------------------------------------

Given('Golden Angels has the {string} agent {string} with chat on') do |agent_type, name|
  agent = FactoryBot.create(:support_agent, entity: @entity, agent_type:, name:, enabled: true,
                                            json_fields: { "chat_config" => { "enabled" => true } })
  @agents ||= {}
  @agents[agent_type] = agent
  @agent ||= agent
  @lp_agent = agent if agent_type == "LpAssistantAgent"
end

Given('the fund {string} of Golden Angels') do |fund_name|
  FactoryBot.create(:fund, entity: @entity, name: fund_name)
end

# Only the model call is stubbed: GenericChatAgent still picks and saves the session itself.
def stub_agent_reply(text: nil, provider_error: nil, fail: false)
  allow_any_instance_of(GenericChatAgent).to receive(:resolve_provider) do |*|
    raise provider_error if provider_error

    true
  end
  allow_any_instance_of(GenericChatAgent).to receive(:setup_ruby_llm_chat).and_return(true)
  allow_any_instance_of(GenericChatAgent).to receive(:execute_chat) do |_agent, ctx, **|
    ctx[:ai_response] = text
    !fail
  end
end

Given('the agent answers {string}') do |text|
  stub_agent_reply(text:)
end

Given('the agent cannot reach the AI service') do
  stub_agent_reply(provider_error: SocketError.new("getaddrinfo: Name or service not known"))
end

Given('the agent fails') do
  stub_agent_reply(fail: true)
end

# A window conversation, last changed at `time`.
def window_session(chattable, question, time:, analyst: @user, agent: @agent)
  session = AgentChatSession.create!(support_agent: agent, chattable:, analyst:, channel: "web", status: "active")
  session.agent_chat_messages.create!(role: "user", content: question, channel: "web", created_at: time)
  session.agent_chat_messages.create!(role: "assistant", content: "Answered.", channel: "web", created_at: time)
  session.update_columns(created_at: time, updated_at: time)
  session
end

def example_time_or_ago(text)
  text =~ /\A(\d+) (minutes|hours) ago\z/ ? Regexp.last_match(1).to_i.send(Regexp.last_match(2)).ago : example_time(text)
end

Given('Priya has window conversations on {string}:') do |fund_name, table|
  fund = Fund.find_by!(name: fund_name)
  table.hashes.each { |row| window_session(fund, row["question"], time: example_time_or_ago(row["last changed"])) }
end

def window_path(chattable, agent: @agent, **params)
  support_agent_chats_path(agent, chattable_type: chattable.class.name, chattable_id: chattable.id, **params)
end

def window_frame_id(agent = @agent) = "agent-chat-#{agent.id}"

When('Priya opens the window on {string}') do |fund_name|
  @window_record = Fund.find_by!(name: fund_name)
  visit window_path(@window_record)
end

When('Priya starts a new conversation in the window on {string}') do |fund_name|
  @window_record = Fund.find_by!(name: fund_name)
  visit window_path(@window_record, new_session: 1)
end

When('Priya reopens {string} in the window on {string}') do |question, fund_name|
  @window_record = Fund.find_by!(name: fund_name)
  session = AgentChatSession.joins(:agent_chat_messages).find_by!(agent_chat_messages: { content: question })
  visit window_path(@window_record, session_id: session.id)
end

When('Priya opens the Portfolio Assistant agent\'s page') do
  visit support_agent_path(@agent)
end

# Posts the window's question box as the browser would: its own hidden fields, Accept turbo-stream.
def ask_in_window(question, agent: @agent)
  fields = all("##{window_frame_id(agent)}-composer input[type='hidden']", visible: :all)
           .to_h { |input| [input[:name], input.value] }
  page.driver.browser.post(support_agent_chats_path(agent), fields.merge("message" => question),
                           { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" })
  @window_status = page.driver.browser.last_response.status
  @stream = Nokogiri::HTML5.fragment(page.driver.browser.last_response.body)
end

When('Priya asks in the window {string}') do |question|
  ask_in_window(question)
end

def stream_template(action, target)
  node = @stream.at_css("turbo-stream[action='#{action}'][target='#{target}'] template")
  expect(node).to be_present, "no #{action} of #{target} in #{@stream.to_html.first(300)}"
  Nokogiri::HTML5.fragment(node.inner_html)
end

Then('the window shows the question {string} and the answer {string}') do |question, answer|
  html = stream_template("replace", window_frame_id)
  expect(html.css(".aic-question").map { |q| q.text.strip }).to include(question)
  expect(html.css("[data-ai-chat-answer]").map(&:text).join).to include(answer)
  @window_html = html
end

Then('the window\'s answer has no rating buttons') do
  expect(@window_html.css("[data-ai-chat-feedback]")).to be_empty
end

Then('the window opens on a new conversation') do
  expect(page).to have_css("##{window_frame_id}-thread-empty")
  expect(find("##{window_frame_id}-composer input[name='new_session']", visible: :all).value).to eq("1")
end

Then('the window lists {string} with {string}') do |question, meta|
  row = find("##{window_frame_id}-conversations .aic-conversation", text: question)
  expect(row).to have_css("[data-role='meta']", text: meta)
end

Then('the window lists {string}') do |question|
  expect(page).to have_css("##{window_frame_id(@window_agent || @agent)}-conversations .aic-conversation", text: question)
end

Then('the window does not list {string}') do |question|
  expect(page).to have_no_css("##{window_frame_id(@window_agent || @agent)}-conversations .aic-conversation", text: question)
end

Then('the window lists {string} without quote marks') do |question|
  title = find("##{window_frame_id}-conversations .aic-conversation [data-role='first-question']").text
  expect(title).to eq(question)
end

Then('the window suggests {string} with a fill button and an Ask button') do |question|
  within("##{window_frame_id}-suggestions") do
    expect(page).to have_css("button[data-action='ai-chat-thread#fill'][data-prompt='#{question}']")
    expect(page).to have_css("button[data-action='ai-chat-thread#askNow'][data-prompt='#{question}']", text: "Ask")
  end
end

Then('the page has the chat bubble and a lazy window') do
  expect(page).to have_css("[data-controller='ai-chat-window'] [data-ai-chat-window-target='toggle']", text: "Need help?")
  expect(page).to have_css("[data-ai-chat-window-target='panel'] turbo-frame##{window_frame_id}[loading='lazy']", visible: :all)
end

Then('the window has Conversations, New, Maximise and Close') do
  expect(page).to have_css("button[data-action='ai-chat-window#toggleList']", text: "Conversations")
  expect(page).to have_css("a##{window_frame_id}-new-chat", text: "New")
  expect(page).to have_css("button[data-action='ai-chat-window#toggleMaximize']")
  expect(page).to have_css("button[data-action='ai-chat-window#close']")
  expect(page).to have_css("##{window_frame_id}-conversations", visible: :all)
end

Then('the window request is refused and no message is saved') do
  expect(@window_status).to eq(422)
  expect(AgentChatMessage.count).to eq(0)
end

Then('Priya has {int} window conversations on {string}') do |count, fund_name|
  expect(AgentChatSession.where(chattable: Fund.find_by!(name: fund_name), analyst: @user).count).to eq(count)
end

def session_started_with(question)
  first_ids = AgentChatMessage.where(role: "user").group(:agent_chat_session_id).minimum(:id).values
  AgentChatMessage.where(id: first_ids, content: question).sole.agent_chat_session
end

Then('{string} is in the conversation that started {string}') do |question, first_question|
  expect(session_started_with(first_question).agent_chat_messages.where(role: "user").pluck(:content)).to include(question)
end

When('the agent is asked {string} about {string} without naming a conversation') do |question, fund_name|
  GenericChatAgent.call(support_agent_id: @agent.id, target: Fund.find_by!(name: fund_name), user_message: question,
                        analyst_id: @user.id)
end

Then('the window\'s pending answer reads {string} with {string}') do |badge, reason|
  html = stream_template("replace", "#{window_frame_id}-pending-answer")
  expect(html.at_css(".badge").text).to include(badge)
  expect(html.text).to include(reason)
end

Then('the window\'s question box holds {string}') do |question|
  html = stream_template("replace", "#{window_frame_id}-composer")
  expect(html.at_css("textarea").text).to eq(question)
end

# The LP chat: an investor (her own entity) with approved access to Golden Angels, and her window
# about herself (chattable: current_user, as entities/_vc_dashboard renders it).
def lp_investor_user(full_name)
  first_name, last_name = full_name.split(" ", 2)
  home = FactoryBot.create(:entity, name: "#{full_name} Family Office", entity_type: "Investor")
  user = FactoryBot.create(:user, entity: home, first_name:, last_name:)
  investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: home.id, investor_name: home.name,
                                          category: "LP")
  InvestorAccess.create!(investor:, entity: @entity, investor_entity: home, user:, email: user.email,
                         first_name:, last_name:, approved: true)
  user
end

Given('{string} is an investor of Golden Angels with her own LP chat {string}') do |full_name, question|
  @kavya = lp_investor_user(full_name)
  @kavya_session = window_session(@kavya, question, time: 10.minutes.ago, analyst: @kavya, agent: @lp_agent)
end

Given('another investor of Golden Angels has an LP chat {string}') do |question|
  other = lp_investor_user("Ravi Menon")
  @other_session = window_session(other, question, time: 5.minutes.ago, analyst: other, agent: @lp_agent)
end

When('Kavya opens her LP chat') do
  log_in(@kavya)
  @window_agent = @lp_agent
  visit window_path(@kavya, agent: @lp_agent)
end

When('Kavya asks her LP chat {string} naming the other investor\'s conversation') do |question|
  log_in(@kavya)
  page.driver.browser.post(support_agent_chats_path(@lp_agent),
                           { "message" => question, "chattable_type" => "User", "chattable_id" => @kavya.id,
                             "session_id" => @other_session.id },
                           { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" })
  expect(page.driver.browser.last_response.status).to eq(200)
end

Then('the other investor\'s conversation is unchanged') do
  expect(@other_session.agent_chat_messages.pluck(:content)).to eq(["Show my SOA", "Answered."])
end

Then('{string} is in Kavya\'s own LP chat') do |question|
  sessions = AgentChatSession.where(analyst: @kavya, support_agent: @lp_agent)
  expect(AgentChatMessage.where(agent_chat_session: sessions, content: question)).to exist
end

# ---- Customer Support extras (features/ai_chat/customer_support.feature) ---------------------------------

Given('Priya has a Customer Support conversation {string} answered {string}') do |question, answer|
  agent = @agents["CustomerSupportAgent"]
  @cs_session = AgentChatSession.create!(support_agent: agent, chattable: @user, analyst: @user, channel: "web", status: "active")
  @cs_session.agent_chat_messages.create!(role: "user", content: question, channel: "web")
  @cs_answer = @cs_session.agent_chat_messages.create!(role: "assistant", content: answer, channel: "web")
end

Given('that conversation was passed to a human') do
  @cs_session.update!(status: "escalated")
end

Given('Priya has a {string} conversation on {string} answered {string}') do |agent_name, fund_name, answer|
  agent = SupportAgent.find_by!(name: agent_name)
  session = AgentChatSession.create!(support_agent: agent, chattable: Fund.find_by!(name: fund_name), analyst: @user,
                                     channel: "web", status: "active")
  session.agent_chat_messages.create!(role: "user", content: "How are valuations?", channel: "web")
  session.agent_chat_messages.create!(role: "assistant", content: answer, channel: "web")
end

When('Priya opens the Customer Support window') do
  visit window_path(@user, agent: @agents["CustomerSupportAgent"])
end

When('Priya opens a new conversation in the Customer Support window') do
  visit window_path(@user, agent: @agents["CustomerSupportAgent"], new_session: 1)
end

When('Priya opens the {string} window on {string}') do |agent_name, fund_name|
  visit window_path(Fund.find_by!(name: fund_name), agent: SupportAgent.find_by!(name: agent_name))
end

Then('the answer offers 👍 and 👎') do
  within("##{ActionView::RecordIdentifier.dom_id(@cs_answer)} [data-ai-chat-feedback]") do
    expect(page).to have_css("button[data-rating='positive'][data-action='ai-chat-feedback#rate']")
    expect(page).to have_css("button[data-rating='negative'][data-action='ai-chat-feedback#rate']")
  end
end

Then('the answer offers no rating') do
  expect(page).to have_css("[data-ai-chat-answer]")
  expect(page).to have_no_css("[data-ai-chat-feedback]")
end

# The PATCH the 👍/👎 buttons and the note's Send make (ai_chat_feedback_controller).
def patch_feedback(message, body)
  url = find("##{ActionView::RecordIdentifier.dom_id(message)} [data-ai-chat-feedback]")["data-ai-chat-feedback-url-value"]
  page.driver.browser.patch(url, body.to_json, { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json" })
  expect(page.driver.browser.last_response.status).to eq(200)
end

When('Priya rates the answer {string}') do |rating|
  patch_feedback(@cs_answer, { rating: })
end

When('Priya sends the feedback note {string}') do |notes|
  patch_feedback(@cs_answer, { notes: })
end

Then('the answer\'s feedback is {string} with the note {string}') do |rating, notes|
  feedback = AgentChatMessageFeedback.find_by!(agent_chat_message: @cs_answer)
  expect([feedback.rating, feedback.notes]).to eq([rating, notes])
end

Then('the answer shows its rating {string}') do |rating|
  expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(@cs_answer)} [data-ai-chat-feedback-rating-value='#{rating}']")
end

Then('the conversation {string} shows {string}') do |question, badge|
  row = find("#agent-chat-#{@agents['CustomerSupportAgent'].id}-conversations .aic-conversation", text: question)
  expect(row).to have_css("[data-role='status']", text: badge)
end

When('Arjun rates Priya\'s answer {string}') do |rating|
  url = feedback_support_agent_chat_path(@agents["CustomerSupportAgent"], @cs_answer)
  page.driver.browser.patch(url, { rating: }.to_json, { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json" })
  @feedback_status = page.driver.browser.last_response.status
end

Then('the rating is refused and nothing is saved') do
  expect(@feedback_status).not_to eq(200)
  expect(AgentChatMessageFeedback.where(agent_chat_message: @cs_answer)).not_to exist
end
