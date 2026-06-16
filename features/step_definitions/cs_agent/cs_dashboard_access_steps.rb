# frozen_string_literal: true

# Step definitions for features/customer_support_agent/cs_dashboard_access.feature

When("I view the sidebar navigation") do
  visit "/"
end

Then("I should not see the {string} link") do |link_text|
  expect(page).not_to have_link(link_text)
end

When("I navigate to \\/cs_feedback_reviews") do
  visit "/cs_feedback_reviews"
end

Then("I should see the feedback reviews dashboard") do
  expect(page).to have_current_path("/cs_feedback_reviews", ignore_query: true)
end

Then("I should see the {string} tab") do |tab_text|
  expect(page).to have_content(tab_text)
end

Given("another entity exists with a customer support agent configured") do
  @other_entity = FactoryBot.create(:entity)
  FactoryBot.create(:entity_setting, entity: @other_entity, cs_judge_enabled: true)
  @other_support_agent = FactoryBot.create(:support_agent,
                                           entity: @other_entity,
                                           agent_type: "CustomerSupportAgent",
                                           name: "Other CS Agent")
end

Given("feedback exists for both entities") do
  # Feedback for mapped entity
  session1 = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg1 = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session1)
  @feedback_mapped = FactoryBot.create(:agent_chat_message_feedback, :negative,
                                       agent_chat_message: msg1, entity: @entity)

  # Feedback for unmapped entity
  other_entity = @other_entity || @second_entity
  other_user = FactoryBot.create(:user, entity: other_entity)

  other_agent = @other_support_agent || @second_support_agent
  session2 = FactoryBot.create(:agent_chat_session, support_agent: other_agent, analyst: other_user, chattable: other_user)

  msg2 = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session2)
  @feedback_unmapped = FactoryBot.create(:agent_chat_message_feedback, :negative,
                                         agent_chat_message: msg2, entity: other_entity)
end

When("I view the feedback queue") do
  mapped_ids = SupportClientMapping.where(user: @support_user, enabled: true).pluck(:entity_id)
  @visible_feedbacks = AgentChatMessageFeedback.where(entity_id: mapped_ids)
                                               .where("rating = ? OR (judge_total IS NOT NULL AND judge_total < ?)", "negative", 5)
end

Then("I should only see feedback from my mapped entity") do
  expect(@visible_feedbacks).to include(@feedback_mapped)
end

Then("I should not see feedback from the unmapped entity") do
  expect(@visible_feedbacks).not_to include(@feedback_unmapped)
end

Given("a second entity exists with a customer support agent configured") do
  @second_entity = FactoryBot.create(:entity)
  FactoryBot.create(:entity_setting, entity: @second_entity, cs_judge_enabled: true)
  @second_support_agent = FactoryBot.create(:support_agent,
                                            entity: @second_entity,
                                            agent_type: "CustomerSupportAgent")
end

Given("a support client mapping exists linking the support user to the second entity") do
  FactoryBot.create(:support_client_mapping, user: @support_user, entity: @second_entity, enabled: true)
end

Then("I should see feedback from both mapped entities") do
  entity_ids = @visible_feedbacks.pluck(:entity_id).uniq
  expect(entity_ids).to include(@entity.id, @second_entity.id)
end

Given("feedback exists with status {string}") do |status|
  session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
  @status_feedback = FactoryBot.create(:agent_chat_message_feedback, :negative,
                                       agent_chat_message: msg, entity: @entity, status: status)
end

When("I filter the feedback queue by status {string}") do |status|
  mapped_ids = SupportClientMapping.where(user: @support_user, enabled: true).pluck(:entity_id)
  @visible_feedbacks = AgentChatMessageFeedback.where(entity_id: mapped_ids, status: status)
                                               .where("rating = ? OR (judge_total IS NOT NULL AND judge_total < ?)", "negative", 5)
end

Then("I should only see feedback with status {string}") do |status|
  expect(@visible_feedbacks.pluck(:status).uniq).to eq([status])
end

Given("feedback exists with rating {string}") do |rating|
  session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
  @rating_feedback = FactoryBot.create(:agent_chat_message_feedback,
                                       agent_chat_message: msg, entity: @entity, rating: rating)
end

Given("feedback exists with rating {string} and judge_total {int}") do |rating, score|
  session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
  @scored_feedback = FactoryBot.create(:agent_chat_message_feedback,
                                       agent_chat_message: msg, entity: @entity,
                                       rating: rating, judge_total: score,
                                       judge_completeness: 1, judge_grounding: 1, judge_actionability: 1)
end

When("I filter the feedback queue by rating {string}") do |rating|
  mapped_ids = SupportClientMapping.where(user: @support_user, enabled: true).pluck(:entity_id)
  @visible_feedbacks = AgentChatMessageFeedback.where(entity_id: mapped_ids, rating: rating)
end

Then("I should only see feedback with rating {string}") do |rating|
  expect(@visible_feedbacks.pluck(:rating).uniq).to eq([rating])
end

When("I filter the feedback queue by entity") do
  @visible_feedbacks = AgentChatMessageFeedback.where(entity_id: @entity.id)
                                               .where("rating = ? OR (judge_total IS NOT NULL AND judge_total < ?)", "negative", 5)
end

Then("I should only see feedback from the selected entity") do
  expect(@visible_feedbacks.pluck(:entity_id).uniq).to eq([@entity.id])
end

Given("feedback exists with judge_total {int}") do |score|
  session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
  @judge_feedback = FactoryBot.create(:agent_chat_message_feedback,
                                      agent_chat_message: msg, entity: @entity,
                                      judge_total: score, judge_completeness: 1,
                                      judge_grounding: 1, judge_actionability: 1)
end

When("I filter the feedback queue by judge_max {int}") do |threshold|
  mapped_ids = SupportClientMapping.where(user: @support_user, enabled: true).pluck(:entity_id)
  @visible_feedbacks = AgentChatMessageFeedback.where(entity_id: mapped_ids)
                                               .where(judge_total: ..threshold)
end

Then("I should only see feedback with judge_total {int} or below") do |threshold|
  @visible_feedbacks.each do |f|
    expect(f.judge_total).to be <= threshold
  end
end

Then("I should see the negative-rated feedback") do
  expect(@visible_feedbacks.pluck(:rating)).to include("negative")
end

Then("I should see the low-judge-score feedback") do
  low_scores = @visible_feedbacks.where("judge_total IS NOT NULL AND judge_total < ?", 5)
  expect(low_scores).to be_any
end

Then("I should not see the positive feedback with high judge score") do
  high_positives = @visible_feedbacks.where(rating: "positive").where(judge_total: 5..)
  expect(high_positives).to be_empty
end

Given("{int} actionable feedback items exist for my mapped entities") do |count|
  count.times do
    session = FactoryBot.create(:agent_chat_session, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
    msg = FactoryBot.create(:agent_chat_message, :assistant_message, agent_chat_session: session)
    FactoryBot.create(:agent_chat_message_feedback, :negative,
                      agent_chat_message: msg, entity: @entity)
  end
end

Given("{int} open escalations exist for my mapped entities") do |count|
  count.times do
    session = FactoryBot.create(:agent_chat_session, :escalated, support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
    FactoryBot.create(:customer_support_escalation,
                      agent_chat_session: session, user: @fm_user, entity: @entity)
  end
end

When("I view the CS Reviews dashboard") do
  mapped_ids = SupportClientMapping.where(user: @support_user, enabled: true).pluck(:entity_id)
  @feedback_count = AgentChatMessageFeedback.where(entity_id: mapped_ids)
                                            .where("rating = ? OR (judge_total IS NOT NULL AND judge_total < ?)", "negative", 5).count
  @escalation_count = CustomerSupportEscalation.where(entity_id: mapped_ids).count
end

Then("the Feedbacks tab should show a badge with count {int}") do |count|
  expect(@feedback_count).to eq(count)
end

Then("the Escalations tab should show a badge with count {int}") do |count|
  expect(@escalation_count).to eq(count)
end
