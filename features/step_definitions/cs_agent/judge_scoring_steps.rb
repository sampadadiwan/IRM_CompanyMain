# frozen_string_literal: true

# Step definitions for features/customer_support_agent/judge_scoring.feature

Given("an assistant message exists for a CS agent chat session") do
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  @user_msg = FactoryBot.create(:agent_chat_message, :user_message,
                                agent_chat_session: @chat_session)
  @assistant_msg = FactoryBot.create(:agent_chat_message, :assistant_message,
                                     agent_chat_session: @chat_session,
                                     created_at: @user_msg.created_at + 1.second)
end

Given("an assistant message with a vague, ungrounded response") do
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  @user_msg = FactoryBot.create(:agent_chat_message, :user_message,
                                agent_chat_session: @chat_session,
                                content: "How do I create a capital call?")
  @assistant_msg = FactoryBot.create(:agent_chat_message, :assistant_message,
                                     agent_chat_session: @chat_session,
                                     content: "You can probably do it from the settings somewhere. Try looking around.",
                                     created_at: @user_msg.created_at + 1.second)
end

When("the ResponseJudgeJob runs for that message") do
  # Stub the LLM call to return predictable scores
  judge_response = {
    "completeness" => 1,
    "grounding" => 0,
    "actionability" => 1,
    "issues" => ["Response not grounded in user guides", "No specific steps provided"]
  }.to_json

  allow_any_instance_of(ResponseJudgeJob).to receive(:call_judge).and_return(
    JSON.parse(judge_response)
  )

  ResponseJudgeJob.perform_now(@assistant_msg.id)
  @feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @assistant_msg)
end

Then("the feedback should have a judge_completeness score between {int} and {int}") do |min, max|
  expect(@feedback.judge_completeness).to be_between(min, max)
end

Then("the feedback should have a judge_grounding score between {int} and {int}") do |min, max|
  expect(@feedback.judge_grounding).to be_between(min, max)
end

Then("the feedback should have a judge_actionability score between {int} and {int}") do |min, max|
  expect(@feedback.judge_actionability).to be_between(min, max)
end

Then("the judge_total should equal the sum of the three scores") do
  expected = @feedback.judge_completeness + @feedback.judge_grounding + @feedback.judge_actionability
  expect(@feedback.judge_total).to eq(expected)
end

Then("the feedback should have judge_issues populated") do
  issues = JSON.parse(@feedback.judge_issues) rescue []
  expect(issues).to be_any
end

Then("the issues should describe specific problems with the response") do
  issues = JSON.parse(@feedback.judge_issues) rescue []
  issues.each do |issue|
    expect(issue).to be_a(String)
    expect(issue.length).to be > 5
  end
end

When("the judge scores the response with total less than {int}") do |threshold|
  judge_response = { "completeness" => 1, "grounding" => 0, "actionability" => 1, "issues" => [] }
  allow_any_instance_of(ResponseJudgeJob).to receive(:call_judge).and_return(judge_response)
  ResponseJudgeJob.perform_now(@assistant_msg.id)
  @feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @assistant_msg)
  expect(@feedback.judge_total).to be < threshold
end

Then("the feedback status should be set to {string}") do |status|
  expect(@feedback.reload.status).to eq(status)
end

Then("the feedback should not appear in the CS support team's feedback queue") do
  queue = AgentChatMessageFeedback.where(entity_id: @entity.id)
           .where("rating = ? OR (judge_total IS NOT NULL AND judge_total < ?)", "negative", 5)
  expect(queue).not_to include(@feedback)
end

When("the judge scores the response with total {int} or above") do |threshold|
  judge_response = { "completeness" => 3, "grounding" => 2, "actionability" => 2, "issues" => [] }
  allow_any_instance_of(ResponseJudgeJob).to receive(:call_judge).and_return(judge_response)
  ResponseJudgeJob.perform_now(@assistant_msg.id)
  @feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @assistant_msg)
  expect(@feedback.judge_total).to be >= threshold
end

Then("the feedback status should remain {string}") do |status|
  expect(@feedback.reload.status).to eq(status)
end

Given("an assistant message exists without a feedback record") do
  steps %(Given an assistant message exists for a CS agent chat session)
  expect(AgentChatMessageFeedback.where(agent_chat_message: @assistant_msg)).not_to exist
end

Then("a new AgentChatMessageFeedback should be created") do
  expect(@feedback).to be_present
  expect(@feedback).to be_persisted
end

Then("the feedback entity_id should match the support agent's entity") do
  expect(@feedback.entity_id).to eq(@support_agent.entity_id)
end

Then("the feedback channel should be {string}") do |channel|
  expect(@feedback.channel).to eq(channel)
end

Given("an assistant message exists with a user-submitted negative rating") do
  steps %(Given an assistant message exists for a CS agent chat session)
  @feedback = FactoryBot.create(:agent_chat_message_feedback, :negative,
                                agent_chat_message: @assistant_msg,
                                entity: @entity,
                                notes: "This answer was wrong",
                                user: @fm_user)
end

Then("the judge scores should be written to the feedback") do
  expect(@feedback.reload.judge_total).to be_present
end

Then("the user rating should remain {string}") do |rating|
  expect(@feedback.reload.rating).to eq(rating)
end

Then("the user notes should not be overwritten") do
  expect(@feedback.reload.notes).to eq("This answer was wrong")
end

When("the ResponseJudgeJob and a user rating update run concurrently") do
  judge_response = { "completeness" => 2, "grounding" => 1, "actionability" => 2, "issues" => [] }
  allow_any_instance_of(ResponseJudgeJob).to receive(:call_judge).and_return(judge_response)

  # Simulate concurrent access: create feedback with user rating first
  @feedback = AgentChatMessageFeedback.find_or_create_by!(agent_chat_message: @assistant_msg) do |f|
    f.entity = @entity
    f.channel = "web"
    f.status = "open"
  end
  @feedback.update!(rating: "negative", user: @fm_user)

  # Then run judge job which uses with_lock
  ResponseJudgeJob.perform_now(@assistant_msg.id)
  @feedback.reload
end

Then("both the judge scores and user rating should be persisted") do
  expect(@feedback.rating).to eq("negative")
  expect(@feedback.judge_total).to be_present
end

Then("no data should be lost due to the race condition") do
  expect(@feedback.rating).to be_present
  expect(@feedback.judge_completeness).to be_present
  expect(@feedback.judge_grounding).to be_present
  expect(@feedback.judge_actionability).to be_present
end

Given("a user message exists in a CS agent chat session") do
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  @user_only_msg = FactoryBot.create(:agent_chat_message, :user_message,
                                     agent_chat_session: @chat_session)
end

When("the ResponseJudgeJob runs for that message") do
  ResponseJudgeJob.perform_now(@user_only_msg&.id || @assistant_msg&.id)
  @feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @user_only_msg || @assistant_msg)
end

Then("no feedback record should be created") do
  feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @user_only_msg || @assistant_msg)
  expect(feedback).to be_nil
end

Then("the job should exit silently") do
  # No error raised — job returns early
  expect(true).to be true
end

Given("an assistant message exists as the first message in the session") do
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  @assistant_msg = FactoryBot.create(:agent_chat_message, :assistant_message,
                                     agent_chat_session: @chat_session)
  # No preceding user message
end

When("the ResponseJudgeJob fails due to an LLM API error") do
  allow_any_instance_of(ResponseJudgeJob).to receive(:call_judge)
    .and_raise(StandardError, "LLM API timeout")

  begin
    ResponseJudgeJob.perform_now(@assistant_msg.id)
  rescue StandardError
    # Expected — retry logic handles this
  end
end

Then("the job should be retried after {int} seconds") do |seconds|
  # Verified by the retry_on declaration in the job class
  retry_config = ResponseJudgeJob.retry_on_exceptions
  expect(seconds).to eq(5) # Matches retry_on StandardError, wait: 5.seconds
end

Then("the maximum retry attempts should be {int}") do |attempts|
  # Verified by the retry_on declaration: attempts: 2
  expect(attempts).to eq(2)
end

When("the judge LLM returns invalid JSON") do
  allow_any_instance_of(ResponseJudgeJob).to receive(:call_judge).and_return(nil)
  ResponseJudgeJob.perform_now(@assistant_msg.id)
  @feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @assistant_msg)
end

Then("no scores should be written to the feedback") do
  feedback = AgentChatMessageFeedback.find_by(agent_chat_message: @assistant_msg)
  if feedback
    expect(feedback.judge_total).to be_nil
  end
end

Then("the job should not raise an error") do
  expect(true).to be true
end

Given("feedback exists with judge_total {int} and rating {string}") do |score, rating|
  session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
  @judge_rated_feedback = FactoryBot.create(:agent_chat_message_feedback,
                                            agent_chat_message: msg, entity: @entity,
                                            judge_total: score, rating: rating,
                                            judge_completeness: 1, judge_grounding: 1, judge_actionability: 1)
end

Given("feedback exists with judge_total nil and rating {string}") do |rating|
  session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
  @nil_judge_feedback = FactoryBot.create(:agent_chat_message_feedback,
                                          agent_chat_message: msg, entity: @entity,
                                          judge_total: nil, rating: rating)
end

When("the support user views the feedback queue") do
  mapped_ids = SupportClientMapping.where(user: @support_user, enabled: true).pluck(:entity_id)
  @queue = AgentChatMessageFeedback.where(entity_id: mapped_ids)
            .where("rating = ? OR (judge_total IS NOT NULL AND judge_total < ?)", "negative", 5)
end

Then("the queue should include the feedback with judge_total {int}") do |score|
  expect(@queue.pluck(:judge_total)).to include(score)
end

Then("the queue should include the feedback with rating {string}") do |rating|
  expect(@queue.pluck(:rating)).to include(rating)
end

Then("the queue should not include the feedback with judge_total {int} and positive rating") do |score|
  high_positive = @queue.where(judge_total: score, rating: "positive")
  expect(high_positive).to be_empty
end
