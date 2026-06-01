# frozen_string_literal: true

# Setup steps
Given('there is a fund with call templates configured') do
  @fund = FactoryBot.create(:fund, entity: @entity)
  @call_template = FactoryBot.create(:document,
    owner: @fund,
    owner_tag: "Call Template",
    template: true,
    entity: @entity,
    user: @user
  )
end

Given('there is an investor_kyc for the investor') do
  @investor_kyc = FactoryBot.create(:investor_kyc,
    entity: @entity,
    investor: @investor,
    verified: false
  )
end


Given('there is a capital commitment for the investor') do
  @capital_commitment = FactoryBot.create(:capital_commitment,
    fund: @fund,
    entity: @entity,
    investor: @investor,
    investor_kyc: @investor_kyc
  )
end

Given('there is a capital call for the fund') do
  @capital_call = FactoryBot.create(:capital_call,
    fund: @fund,
    entity: @entity
  )
  # Create remittance for the commitment
 @capital_remittance = FactoryBot.create(:capital_remittance,
  capital_call: @capital_call,
  capital_commitment: @capital_commitment,
  fund: @fund,
  entity: @entity,
  investor: @investor,
  folio_id: @capital_commitment.folio_id,
  folio_committed_amount_cents: @capital_commitment.folio_committed_amount_cents
)

end

# KYC steps
Given('all investors have verified KYC') do
  @investor_kyc.update!(verified: true)
end

Given('an investor has unverified KYC') do
  @investor_kyc.update!(verified: false)
end

# Document steps
Given('all remittances have generated documents') do
  @capital_call.capital_remittances.each do |remittance|
    FactoryBot.create(:document,
      owner: remittance,
      template: false,
      approved: false,
      entity: @entity,
      user: @user
    )
  end
end

Given('remittances are missing call notice documents') do
  # Ensure no documents exist for remittances
  @capital_call.capital_remittances.each do |remittance|
    remittance.documents.destroy_all
  end
end

Given('the fund has no call templates') do
  @fund.documents.templates.where(owner_tag: "Call Template").destroy_all
end

Given('all documents are approved') do
  @capital_call.capital_remittances.each do |remittance|
    remittance.documents.update_all(approved: true)
  end
end

Given('some documents are not approved') do
  # Documents exist but are not approved (default state from creation)
  @capital_call.capital_remittances.first.documents.update_all(approved: false)
end

# Notification steps
Given('email notification template is configured') do
  CustomNotification.create!(
    owner: @capital_call,
    email_method: "notify_capital_remittance",
    subject: "Capital Call Notice",
    body: "Your capital call notice is ready.",
    enabled: true,
    entity: @entity
  )
end

Given('no email notification template is configured') do
  @capital_call.custom_notifications.where(email_method: "notify_capital_remittance").destroy_all
end

# Skip call notice steps
Given('a commitment has skip_doc_gen enabled') do
  @skip_commitment = FactoryBot.create(:capital_commitment,
    fund: @fund,
    entity: @entity,
    investor: @investor,
    skip_doc_gen: true
  )
  @skip_commitment.update!(json_fields: { "skip_doc_gen" => "yes" })
  @skip_remittance = FactoryBot.create(:capital_remittance,
    capital_call: @capital_call,
    capital_commitment: @skip_commitment,
    fund: @fund,
    entity: @entity,
    investor: @investor
  )
end

Given('all other remittances have generated and approved documents') do
  @capital_call.capital_remittances.each do |remittance|
    next if remittance.capital_commitment.skip_doc_gen?

    doc = FactoryBot.create(:document,
      owner: remittance,
      template: false,
      approved: true,
      entity: @entity,
      user: @user
    )
  end
end

# Agent execution
When('I run the call notice agent') do
  # CallNoticeAgent is deterministic and never uses the LLM, but SupportAgentService#initialize_agent
  # calls LlmService.ruby_llm_chat which requires API keys. Stub at the service layer, not RubyLLM directly.
  mock_chat = double('chat', ask: double(content: 'mocked response'))
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
  # broadcast_step calls Turbo::StreamsChannel.broadcast_replace_to which requires ActionCable.
  allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

  @support_agent = SupportAgent.find_or_create_by!(
    agent_type: 'CallNoticeAgent',
    entity_id: @entity.id
  ) do |agent|
    agent.name = 'Call Notice Validator'
    agent.enabled = true
  end

  # Create the report before calling the agent
  @report = SupportAgentReport.find_or_create_by!(
    owner: @capital_call,
    support_agent: @support_agent
  ) do |report|
    steps = CallNoticeAgent.step_definitions.map do |step_def|
      {
        "step" => step_def[:step],
        "id" => step_def[:id],
        "label" => step_def[:label],
        "short_label" => step_def[:short_label],
        "status" => "pending"
      }
    end
    report.json_fields = {
      "steps" => steps,
      "final_status" => "running",
      "triggered_by" => "manual",
      "triggered_by_user_id" => @user.id,
      "run_at" => Time.current.iso8601
    }
    report.status = :pending
  end

  @result = CallNoticeAgent.call(
    support_agent_id: @support_agent.id,
    target: @capital_call,
    user_id: @user.id,
    support_agent_report: @report
  )

  @report.reload
end



# Assertion steps
Then('the agent should complete successfully') do
  expect(@result).to be_truthy
  expect(@report.final_status).to eq("ready")
end

Then('the final status should be {string}') do |status|
  expect(@report.final_status).to eq(status)
end

Then('all steps should have status {string}') do |status|
  @report.steps.each do |step|
    expect(step["status"]).to eq(status), "Step #{step['id']} has status #{step['status']}, expected #{status}"
  end
end

Then('the agent should stop at step {string}') do |step_id|
  failed_step = @report.failed_step
  expect(failed_step).to be_present
  expect(failed_step["id"]).to eq(step_id)
end

Then('the step {string} should have failed records') do |step_id|
  step = @report.steps.find { |s| s["id"] == step_id }
  expect(step).to be_present
  expect(step["failed_records"]).to be_present
  expect(step["failed_records"]).not_to be_empty
end

Then('the step message should contain {string}') do |text|
  failed_step = @report.failed_step
  expect(failed_step).to be_present
  expect(failed_step["message"]).to include(text)
end

Then('the skipped commitment should not cause failures') do
  # The agent should complete without the skipped commitment causing issues
  expect(@report.final_status).to eq("ready")
end
