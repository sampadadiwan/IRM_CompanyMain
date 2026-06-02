# frozen_string_literal: true

# Step definitions for features/ai/deal_management_agent.feature.
#
# Strategy: all agent calls go through DealManagementAgent.wtf?(...) directly —
# no browser/UI involvement. LLM calls are stubbed via allow(LlmService) so tests
# are deterministic and fast. Email delivery is checked via ActionMailer::Base.deliveries
# (test env uses :inline queue adapter so deliver_later is synchronous).

# ── Helpers ────────────────────────────────────────────────────────────────────

# Builds a stub LLM chat object whose ask() returns a fixed response string.
def stub_llm(response_text)
  fake_chat = double("llm_chat")
  allow(fake_chat).to receive(:ask).and_return(response_text)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
  fake_chat
end

# Tracks whether the LLM was asked during a run.
def tracking_llm
  @llm_calls = []
  fake_chat = double("llm_chat")
  allow(fake_chat).to receive(:ask) do |prompt|
    @llm_calls << prompt
    "{}"  # minimal valid response
  end
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
  fake_chat
end

# Returns the deal-level SupportAgentReport for the current deal+agent pair.
def deal_report
  SupportAgentReport.find_by(owner: @deal, support_agent: @agent)
end

# Returns all investor-level reports for the current agent.
def investor_reports
  SupportAgentReport.where(
    owner_type: "DealInvestor",
    support_agent: @agent
  ).joins("INNER JOIN deal_investors ON deal_investors.id = support_agent_reports.owner_id")
   .where("deal_investors.deal_id = ?", @deal.id)
end

# Attaches a stub file to a Document so read_document_text returns a string.
def attach_stub_file_to(doc)
  fake_file = double("shrine_file",
    blank?: false,
    present?: true,
    original_filename: "#{doc.name.gsub(/\s+/, '_')}.txt",
    open: nil
  )
  allow(fake_file).to receive(:open).and_yield(StringIO.new("Stub content for #{doc.name}"))
  allow(doc).to receive(:file).and_return(fake_file)
  # Stub File.extname since it will be called on the filename
  allow(doc).to receive_message_chain(:file, :blank?).and_return(false)
  allow(doc).to receive_message_chain(:file, :present?).and_return(true)
  allow(doc).to receive_message_chain(:file, :original_filename).and_return("#{doc.name.gsub(/\s+/, '_')}.txt")
  allow(doc).to receive_message_chain(:file, :open).and_yield(StringIO.new("Stub content for #{doc.name}"))
end

# Creates a plain-text document record attached to owner with a stub file.
def create_stub_doc(name:, owner:, entity: @entity, user: @user)
  folder = owner.document_folder
  doc = Document.new(name: name, entity: entity, owner: owner, user: user, folder: folder, send_email: false)
  # Inject a synthetic file_data blob so the record saves without a real upload
  doc.file_data = { "id" => "#{SecureRandom.hex(8)}.txt", "storage" => "store",
                    "metadata" => { "filename" => "#{name.gsub(/\s+/, '_')}.txt", "size" => 20, "mime_type" => "text/plain" } }.to_json
  doc.save!(validate: false)
  # Stub file I/O for text extraction
  allow_any_instance_of(DealManagementAgent).to receive(:read_document_text).with(doc).and_return("Stub content for #{name}")
  doc
end

# Runs the agent against @deal and captures the context result.
# Clears ActionMailer deliveries first so each scenario starts clean.
def run_agent
  ActionMailer::Base.deliveries.clear
  stub_llm(@llm_response || "{}") unless @llm_stubbed
  @agent_result = DealManagementAgent.wtf?(
    support_agent_id: @agent.id,
    target:           @deal
  )
end

# ── Background ─────────────────────────────────────────────────────────────────

Given('there is a DealManagementAgent configured for the entity') do
  @agent = FactoryBot.create(
    :support_agent,
    entity:     @entity,
    agent_type: "DealManagementAgent",
    name:       "Deal Management",
    enabled:    true,
    llm_model:  "gemini-3-flash-preview",
    json_fields: {
      "check_progress"         => "Yes",
      "stagnant_days"          => "7",
      "check_documents"        => "No",
      "required_docs"          => "",
      "extract_terms"          => "No",
      "term_extraction_prompt" => "",
      "summarize_notes"        => "No",
      "note_period"            => "Quarter",
      "score_investors"        => "No",
      "min_points_per_section" => "3",
      "notify_email"           => ""
    }
  )
end

# ── Deal + investor setup ──────────────────────────────────────────────────────

Given('there is an open deal with {int} active investor(s)') do |count|
  @deal = FactoryBot.create(:deal, entity: @entity, status: "Open",
                             name: "Test Deal #{SecureRandom.hex(4)}",
                             amount_cents: 10_000_000_00, currency: "USD")

  @deal_investors = count.times.map do |i|
    inv_entity = FactoryBot.create(:entity, entity_type: "Investor")
    investor   = FactoryBot.create(:investor, entity: @entity, investor_entity: inv_entity,
                                              investor_name: "Investor #{i + 1} #{SecureRandom.hex(3)}")
    FactoryBot.create(:deal_investor,
      deal:                     @deal,
      investor:                 investor,
      entity:                   @entity,
      status:                   "Active",
      primary_amount_cents:     5_000_000_00,
      pre_money_valuation_cents: 50_000_000_00)
  end
  @deal_investor = @deal_investors.first
end

Given('there is an open deal with {int} active investor(s) and {int} declined investor(s)') do |active_count, declined_count|
  step "there is an open deal with #{active_count} active investor"

  declined_count.times do |i|
    inv_entity = FactoryBot.create(:entity, entity_type: "Investor")
    investor   = FactoryBot.create(:investor, entity: @entity, investor_entity: inv_entity,
                                              investor_name: "Declined Investor #{i} #{SecureRandom.hex(3)}")
    FactoryBot.create(:deal_investor,
      deal:                     @deal,
      investor:                 investor,
      entity:                   @entity,
      status:                   "Declined",
      primary_amount_cents:     2_000_000_00,
      pre_money_valuation_cents: 50_000_000_00)
  end
end

Given('there is an open deal with {int} active investor(s) with documents') do |count|
  step "there is an open deal with #{count} active investor"
  @deal_investors.each do |di|
    create_stub_doc(name: "Investor Doc #{di.id}", owner: di)
  end
end

Given('there is an open deal with 1 declined investor') do
  step "there is an open deal with 0 active investor"
  inv_entity = FactoryBot.create(:entity, entity_type: "Investor")
  investor   = FactoryBot.create(:investor, entity: @entity, investor_entity: inv_entity,
                                            investor_name: "Declined #{SecureRandom.hex(3)}")
  @deal_investor = FactoryBot.create(:deal_investor,
    deal:                     @deal,
    investor:                 investor,
    entity:                   @entity,
    status:                   "Declined",
    primary_amount_cents:     2_000_000_00,
    pre_money_valuation_cents: 50_000_000_00)
end

Given('there is an open deal with no documents in the data room') do
  step "there is an open deal with 0 active investor"
end

Given('there is an open deal with a document {string} in the data room') do |doc_name|
  step "there is an open deal with 0 active investor"
  @data_room_doc = create_stub_doc(name: doc_name, owner: @deal)
  # Override: use the deal's deal_documents_folder instead of document_folder
  folder = @deal.deal_documents_folder
  @data_room_doc.update_column(:folder_id, folder.id)
end

# ── Deal state mutations ───────────────────────────────────────────────────────

Given('the deal is closed') do
  @deal.update!(status: "Closed")
end

Given('all DealManagementAgent capabilities are disabled') do
  @agent.update!(json_fields: @agent.json_fields.merge(
    "check_progress"  => "No",
    "check_documents" => "No",
    "extract_terms"   => "No",
    "summarize_notes" => "No",
    "score_investors" => "No"
  ))
end

# ── Investor state mutations ───────────────────────────────────────────────────

Given('the investor has had no activity for {int} days') do |days|
  DealInvestor.where(id: @deal_investor.id).update_all(updated_at: days.days.ago)
  DealActivity.where(deal_investor_id: @deal_investor.id).update_all(updated_at: days.days.ago)
end

Given('the investor was updated {int} days ago') do |days|
  DealInvestor.where(id: @deal_investor.id).update_all(updated_at: days.days.ago)
  DealActivity.where(deal_investor_id: @deal_investor.id).update_all(updated_at: days.days.ago)
end

Given('the declined investor has had no activity for {int} days') do |days|
  DealInvestor.where(id: @deal_investor.id).update_all(updated_at: days.days.ago)
end

Given('the investor has an overdue activity {string} due {int} days ago') do |title, days|
  @overdue_activity = DealActivity.create!(
    deal:            @deal,
    deal_investor:   @deal_investor,
    entity:          @entity,
    title:           title,
    status:          "Incomplete",
    sequence:        1,
    days:            10,
    by_date:         days.days.ago.to_date
  )
end

Given('the investor has an upcoming activity {string} due in {int} days') do |title, days|
  DealActivity.create!(
    deal:          @deal,
    deal_investor: @deal_investor,
    entity:        @entity,
    title:         title,
    status:        "Incomplete",
    sequence:      1,
    days:          days,
    by_date:       days.days.from_now.to_date
  )
end

Given('the investor has {int} document(s) in their folder') do |count|
  count.times do |i|
    create_stub_doc(name: "Investor Document #{i + 1}", owner: @deal_investor)
  end
end

Given('the investor has no documents') do
  # ensure no documents attached — already true for a fresh deal_investor
  Document.where(owner_type: "DealInvestor", owner_id: @deal_investor.id).destroy_all
end

# ── Agent config mutations ─────────────────────────────────────────────────────

Given('the agent requires documents {string}') do |docs|
  @agent.update!(json_fields: @agent.json_fields.merge(
    "check_documents" => "Yes",
    "required_docs"   => docs
  ))
end

Given('the agent has required_docs set to {string}') do |docs|
  @agent.update!(json_fields: @agent.json_fields.merge(
    "check_documents" => "Yes",
    "required_docs"   => docs
  ))
end

Given('the agent has notify_email {string}') do |email|
  @agent.update!(json_fields: @agent.json_fields.merge("notify_email" => email))
end

Given('the agent has a scoring_skill_file uploaded') do
  # Create a FormCustomField of type File named scoring_skill_file on the agent's form type
  ft = @agent.form_type
  fcf = ft.form_custom_fields.find_or_create_by!(
    name: "scoring_skill_file", field_type: "File",
    label: "Scoring Skill File", position: 99
  )
  # Attach a stub document to the agent with the field's human_label as the name
  folder = @agent.document_folder
  skill_doc = Document.new(
    name:       fcf.human_label,
    entity:     @entity,
    owner:      @agent,
    user:       @user,
    folder:     folder,
    send_email: false
  )
  skill_doc.file_data = { "id" => "skill.txt", "storage" => "store",
                          "metadata" => { "filename" => "skill.txt", "size" => 30, "mime_type" => "text/plain" } }.to_json
  skill_doc.save!(validate: false)
  allow_any_instance_of(DealManagementAgent).to receive(:read_document_text).with(skill_doc).and_return("Score the investor on commitment and engagement.")
end

# ── Document data room helpers ─────────────────────────────────────────────────

Given('a new document {string} is added to the deal data room') do |doc_name|
  new_doc = create_stub_doc(name: doc_name, owner: @deal)
  folder  = @deal.deal_documents_folder
  new_doc.update_column(:folder_id, folder.id)
end

# ── Cache setup ───────────────────────────────────────────────────────────────

Given('a prior deal report exists with a valid term extraction cache') do
  docs              = @deal.deal_documents_folder.documents.to_a
  fingerprint       = Digest::SHA1.hexdigest(docs.sort_by(&:id).map { |d| "#{d.id}:#{d.updated_at.to_i}" }.join("|"))
  current_prompt    = @agent.json_fields["term_extraction_prompt"].to_s.strip

  prior_report = SupportAgentReport.find_or_initialize_by(owner: @deal, support_agent: @agent)
  prior_report.status = :completed
  prior_report.json_fields = {
    "term_extraction_fingerprint" => fingerprint,
    "term_extraction_prompt_used" => current_prompt,
    "extracted_terms"             => { "pre_money_valuation" => "CACHED_VALUE" },
    "final_status"                => "ready"
  }
  prior_report.json_fields_will_change!
  prior_report.save!
  prior_report.mark_as_latest!
  @cached_terms = prior_report.json_fields["extracted_terms"]
end

Given('the DealManagementAgent has already run once for the deal') do
  stub_llm("{}")
  DealManagementAgent.wtf?(support_agent_id: @agent.id, target: @deal)
end

# ── LLM response stubs ────────────────────────────────────────────────────────

Given('the LLM returns deal terms JSON with pre_money_valuation {string}') do |value|
  @llm_stubbed  = true
  @llm_response = %(```json\n{"pre_money_valuation":"#{value}","post_money_valuation":null}\n```)
  @agent.update!(json_fields: @agent.json_fields.merge("extract_terms" => "Yes"))
  stub_llm(@llm_response)
end

Given('the LLM returns a note summary {string}') do |summary|
  @llm_stubbed  = true
  @llm_response = summary
  stub_llm(@llm_response)
end

Given('the LLM returns a valid investor score of {int} grade {string}') do |score, grade|
  @llm_stubbed   = true
  score_json_str = JSON.generate(
    "overall_score" => score,
    "grade"         => grade,
    "summary"       => "Test investor summary",
    "dimensions"    => [
      { "name" => "Commitment", "score" => score, "weight" => 1.0,
        "rationale" => "Strong", "positives" => ["a", "b", "c"], "concerns" => ["x", "y", "z"] }
    ],
    "strengths"       => ["s1", "s2", "s3"],
    "risks"           => ["r1", "r2", "r3"],
    "recommendations" => ["rec1", "rec2", "rec3"]
  )
  @llm_response = "```json\n#{score_json_str}\n```"
  stub_llm(@llm_response)
end

Given('the LLM returns scores {int} and {int} for the two investors') do |score1, score2|
  @llm_stubbed = true
  @score_responses = [score1, score2].map do |score|
    "```json\n#{JSON.generate(
      'overall_score' => score, 'grade' => score >= 70 ? 'B+' : 'C',
      'summary' => 'Narrative', 'dimensions' => [
        { 'name' => 'Commitment', 'score' => score, 'weight' => 1.0, 'rationale' => 'OK',
          'positives' => %w[a b c], 'concerns' => %w[x y z] }
      ],
      'strengths' => %w[s1 s2 s3], 'risks' => %w[r1 r2 r3],
      'recommendations' => %w[rec1 rec2 rec3]
    )}\n```"
  end

  call_index = 0
  fake_chat  = double("llm_chat")
  allow(fake_chat).to receive(:ask) do |_prompt|
    resp = @score_responses[call_index] || "{}"
    call_index += 1
    resp
  end
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
end

# ── Agent enablement flags ─────────────────────────────────────────────────────

Given('the DealManagementAgent runs for the deal with check_progress enabled') do
  @agent.update!(json_fields: @agent.json_fields.merge("check_progress" => "Yes", "stagnant_days" => "7"))
  run_agent
end

Given('the DealManagementAgent runs for the deal with check_documents enabled') do
  run_agent
end

Given('the DealManagementAgent runs for the deal with extract_terms enabled') do
  @agent.update!(json_fields: @agent.json_fields.merge("extract_terms" => "Yes"))
  # Track every call to ask() so we can assert whether term extraction hit the LLM
  @llm_ask_calls = []
  fake_chat = double("llm_chat")
  allow(fake_chat).to receive(:ask) do |prompt|
    @llm_ask_calls << prompt
    @llm_response || %(```json\n{"pre_money_valuation":null}\n```)
  end
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
  @llm_stubbed = true
  run_agent
end

Given('the DealManagementAgent runs for the deal with summarize_notes enabled') do
  @agent.update!(json_fields: @agent.json_fields.merge("summarize_notes" => "Yes"))
  @llm_stubbed = true
  @llm_call_count = 0
  fake_chat = double("llm_chat")
  allow(fake_chat).to receive(:ask) do |_prompt|
    @llm_call_count += 1
    @llm_response || "Stub summary"
  end
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
  run_agent
end

Given('the DealManagementAgent runs for the deal with score_investors enabled') do
  @agent.update!(json_fields: @agent.json_fields.merge("score_investors" => "Yes"))
  run_agent
end

# ── Generic run (using current agent config) ───────────────────────────────────

When('the DealManagementAgent runs for the deal') do
  run_agent
end

# ── Assertions — gating ───────────────────────────────────────────────────────

Then('no deal-level SupportAgentReport is saved') do
  expect(deal_report).to be_nil
end

Then('a deal-level SupportAgentReport is saved') do
  expect(deal_report).to be_present
end

Then('the report has no blocking issues') do
  report = deal_report
  expect(report).to be_present
  all_issues = (report.json_fields || {})
    .values_at("progress_issues", "document_issues", "digest_issues")
    .compact.flatten
  blocking = all_issues.select { |i| (i["severity"] || i[:severity]).to_s == "blocking" }
  expect(blocking).to be_empty
end

# ── Assertions — progress ──────────────────────────────────────────────────────

Then('the deal report progress_issues contains {int} stagnant blocking issue(s)') do |count|
  issues = (deal_report&.json_fields || {})["progress_issues"] || []
  stagnant_blocking = issues.select { |i| i["type"] == "stagnant" && i["severity"] == "blocking" }
  expect(stagnant_blocking.size).to eq(count)
end

Then('the deal report progress_issues contains {int} stagnant issue(s)') do |count|
  issues  = (deal_report&.json_fields || {})["progress_issues"] || []
  stagnant = issues.select { |i| i["type"] == "stagnant" }
  expect(stagnant.size).to eq(count)
end

Then('the deal report progress_issues contains {int} overdue blocking issue(s) for {string}') do |count, title|
  issues  = (deal_report&.json_fields || {})["progress_issues"] || []
  overdue = issues.select { |i| i["type"] == "overdue" && i["severity"] == "blocking" && i["activity_title"] == title }
  expect(overdue.size).to eq(count)
end

# ── Assertions — document checklist ───────────────────────────────────────────

Then('the document_issues contain {int} blocking issue(s) for missing documents') do |count|
  issues   = (deal_report&.json_fields || {})["document_issues"] || []
  blocking = issues.select { |i| i["severity"] == "blocking" }
  expect(blocking.size).to eq(count)
end

Then('the document_issues contain {int} success issue(s) for {string}') do |count, doc_name|
  issues  = (deal_report&.json_fields || {})["document_issues"] || []
  present = issues.select { |i| i["severity"] == "success" && i["type"] == "present" && i["document_name"]&.casecmp?(doc_name) }
  expect(present.size).to eq(count)
end

Then('the document_issues contain {int} blocking issue(s)') do |count|
  issues   = (deal_report&.json_fields || {})["document_issues"] || []
  blocking = issues.select { |i| i["severity"] == "blocking" }
  expect(blocking.size).to eq(count)
end

# ── Assertions — term extraction ───────────────────────────────────────────────

Then('the deal report extracted_terms contains {string} with value {string}') do |key, value|
  terms = deal_report&.json_fields&.dig("extracted_terms") || {}
  expect(terms[key].to_s).to eq(value)
end

Then('the LLM is not called for term extraction') do
  # Cache hit: ask() should not have been invoked at all during this run
  expect(@llm_ask_calls.to_a).to be_empty
end

Then('the deal report extracted_terms are carried forward from the cache') do
  terms = deal_report&.json_fields&.dig("extracted_terms") || {}
  expect(terms).to eq(@cached_terms)
end

Then('the LLM is called for term extraction') do
  # Cache miss: ask() must have been called at least once
  expect(@llm_ask_calls.to_a).not_to be_empty
end

# ── Assertions — investor pipeline ────────────────────────────────────────────

Then('the investor-level SupportAgentReport has summary_text {string}') do |text|
  report = SupportAgentReport.find_by(owner: @deal_investor, support_agent: @agent)
  expect(report).to be_present
  expect(report.json_fields["summary_text"]).to include(text)
end

Then('the investor-level SupportAgentReport final_status is {string}') do |status|
  report = SupportAgentReport.find_by(owner: @deal_investor, support_agent: @agent)
  expect(report).to be_present
  expect(report.json_fields["final_status"]).to eq(status)
end

Then('the LLM is not called for summarization') do
  expect(@llm_call_count.to_i).to eq(0)
end

Then('the DealInvestor has ai_score {int} and ai_grade {string}') do |score, grade|
  pending("ai_score/ai_grade columns require migration add_ai_score_to_deal_investors") unless DealInvestor.column_names.include?("ai_score")
  @deal_investor.reload
  expect(@deal_investor.ai_score).to eq(score)
  expect(@deal_investor.ai_grade).to eq(grade)
end

Then('the investor-level SupportAgentReport contains the score data') do
  report = SupportAgentReport.find_by(owner: @deal_investor, support_agent: @agent)
  expect(report).to be_present
  expect(report.json_fields["score"]).to be_present
  expect(report.json_fields["score"]["overall_score"]).to be_present
end

Then('only {int} investor-level SupportAgentReport is saved') do |count|
  # Declined investor should produce no report
  investor_report_count = SupportAgentReport
    .joins("INNER JOIN deal_investors ON deal_investors.id = support_agent_reports.owner_id AND support_agent_reports.owner_type = 'DealInvestor'")
    .where("deal_investors.deal_id = ? AND support_agent_reports.support_agent_id = ?", @deal.id, @agent.id)
    .count
  expect(investor_report_count).to eq(count)
end

# ── Assertions — digest ───────────────────────────────────────────────────────
# The test environment uses queue_adapter = :inline so deliver_later runs
# synchronously — emails land in ActionMailer::Base.deliveries just like deliver_now.

Then('a DealManagementDigestMailer email is queued to {string}') do |email|
  digest_mails = ActionMailer::Base.deliveries.select do |mail|
    mail.to.include?(email) &&
      mail.subject.to_s.match?(/Deal Management Report|Deal Alert|Deal Digest/i)
  end
  expect(digest_mails).not_to be_empty,
    "Expected a digest email to #{email}. " \
    "Deliveries: #{ActionMailer::Base.deliveries.map { |m| "to=#{m.to} subject=#{m.subject.inspect}" }.inspect}"
end

Then('no DealManagementDigestMailer email is queued') do
  digest_mails = ActionMailer::Base.deliveries.select do |mail|
    mail.subject.to_s.match?(/Deal Management Report|Deal Alert|Deal Digest/i)
  end
  expect(digest_mails).to be_empty,
    "Expected no digest emails but found: #{digest_mails.map { |m| "to=#{m.to} subject=#{m.subject.inspect}" }.inspect}"
end

Then('the digest email subject contains {string}') do |text|
  digest_mail = ActionMailer::Base.deliveries.find do |mail|
    mail.subject.to_s.match?(/Deal Management Report|Deal Alert|Deal Digest/i)
  end
  expect(digest_mail).to be_present, "No digest email found in deliveries"
  expect(digest_mail.subject).to include(text)
end

Then('the digest email body contains {string}') do |text|
  digest_mail = ActionMailer::Base.deliveries.find do |mail|
    mail.subject.to_s.match?(/Deal Management Report|Deal Alert|Deal Digest/i)
  end
  expect(digest_mail).to be_present, "No digest email found in deliveries"
  body = digest_mail.body.parts.map(&:body).map(&:to_s).join + digest_mail.body.to_s
  expect(body).to include(text)
end

# ── Assertions — report idempotency + leaderboard ────────────────────────────

Then('there is exactly {int} deal-level SupportAgentReport for the deal') do |count|
  expect(SupportAgentReport.where(owner: @deal, support_agent: @agent).count).to eq(count)
end

Then('the deal report score_leaderboard first entry has ai_score {int}') do |score|
  leaderboard = deal_report&.json_fields&.dig("score_leaderboard") || []
  expect(leaderboard).not_to be_empty
  first_score = leaderboard.first["ai_score"] || leaderboard.first[:ai_score]
  expect(first_score).to eq(score)
end
