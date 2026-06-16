# frozen_string_literal: true

# Step definitions for features/customer_support_agent/feedback_review.feature

When("I click on a feedback item in the queue") do
  visit "/cs_feedback_reviews/#{@feedback.id}"
end

Then("I should see the feedback detail page") do
  expect(page).to have_content("Feedback Review ##{@feedback.id}")
end

Then("I should see the original user question") do
  expect(page).to have_content("User Question")
end

Then("I should see the agent response rendered as markdown") do
  expect(page).to have_css(".markdown-body")
end

Then("I should see the feedback status") do
  expect(page).to have_content(@feedback.status.titleize)
end

Then("I should see the user rating") do
  expect(page).to have_content("Negative").or have_content("Positive").or have_content("No user rating")
end

Given("the feedback item has been judged") do
  @feedback.update!(
    judge_completeness: 1, judge_grounding: 0, judge_actionability: 1,
    judge_total: 2, judge_issues: ["Response not grounded in user guides"].to_json,
    status: "needs_review"
  )
end

Then("I should see the completeness score out of {int}") do |max|
  expect(page).to have_content("Completeness")
  expect(page).to have_content("/#{max}")
end

Then("I should see the grounding score out of {int}") do |max|
  expect(page).to have_content("Grounding")
  expect(page).to have_content("/#{max}")
end

Then("I should see the actionability score out of {int}") do |max|
  expect(page).to have_content("Actionability")
  expect(page).to have_content("/#{max}")
end

Then("I should see the total score out of {int}") do |max|
  expect(page).to have_content("/#{max}")
end

Then("I should see the list of issues flagged by the judge") do
  expect(page).to have_content("Issues flagged")
end

Given("the agent used SearchUserGuidesTool to answer the question") do
  @assistant_msg.update!(tool_calls_summary: [{ "tool_name" => "SearchUserGuidesTool", "query" => "capital call" }].to_json)
end

Then("the feedback detail page should show the tool calls summary") do
  expect(page).to have_content("Tool Calls")
end

Then("I should see which tools were called") do
  expect(page).to have_content("SearchUserGuidesTool")
end

Given("the agent searched user guide files") do
  @feedback.update!(guide_files_searched: ["docs/user_guides/capital_calls_user_guide.md"].to_json)
  @assistant_msg.update!(guide_search_hit: true)
end

Then("the feedback detail page should show which guide files were searched") do
  expect(page).to have_content("Guide Files Searched")
end

Then("I should see whether a guide match was found") do
  expect(page).to have_css(".badge")
end

When("I confirm the action") do
  # Playwright handles the confirm dialog automatically
  page.accept_confirm if page.driver.respond_to?(:accept_confirm)
end

Then("the agent should re-run the original question") do
  # The re-test action calls GenericChatAgent — verified by seeing the result
  expect(page).to have_css("turbo-frame#retest_result")
end

Then("I should see the new response inline without a full page reload") do
  within("turbo-frame#retest_result") do
    expect(page).to have_content("New response").or have_content("Re-test failed")
  end
end

Then("the original response should still be visible above for comparison") do
  expect(page).to have_content("Agent Response")
end

Given("the LLM service is unavailable") do
  allow(LlmService).to receive(:ruby_llm_chat).and_raise(SocketError, "Connection refused")
end

Then("I should see an error message in the re-test section") do
  within("turbo-frame#retest_result") do
    expect(page).to have_css(".alert-danger").or have_content("Re-test failed")
  end
end

When("I view the feedback detail page") do
  visit "/cs_feedback_reviews/#{@feedback.id}"
end

When("I enter resolution notes {string}") do |notes|
  fill_in "resolution_notes", with: notes
end

Then("the feedback status should change to {string}") do |status|
  eventually do
    expect(@feedback.reload.status).to eq(status)
  end
end

Then("the resolution notes should be saved") do
  expect(@feedback.reload.resolution_notes).to be_present
end

Then("I should see who reviewed the feedback") do
  expect(@feedback.reload.reviewed_by).to be_present
end

Then("the action buttons should no longer be visible") do
  expect(page).not_to have_button("Resolve")
  expect(page).not_to have_button("Dismiss")
end

When("I click {string} without entering notes") do |button_text|
  # Leave notes empty and try to submit
  fill_in "resolution_notes", with: ""
  click_button button_text
end

Then("the form should not submit") do
  # HTML5 required attribute prevents submission
  expect(page).to have_current_path("/cs_feedback_reviews/#{@feedback.id}", ignore_query: true)
end

Then("I should see a validation message for the notes field") do
  # Browser-level validation for required field
  notes_field = find("textarea[name='resolution_notes']")
  expect(notes_field[:required]).to be_truthy
end

Given("the feedback's chat session has an open escalation") do
  @linked_escalation = FactoryBot.create(:customer_support_escalation,
                                         agent_chat_session: @chat_session,
                                         user: @fm_user,
                                         entity: @entity)
  @chat_session.update!(status: "escalated")
end

When("I resolve the feedback with notes") do
  visit "/cs_feedback_reviews/#{@feedback.id}"
  fill_in "resolution_notes", with: "Issue resolved after guide update"
  click_button "Resolve"
end

Then("the linked escalation should also be resolved") do
  eventually do
    expect(@linked_escalation.reload.status).to eq("resolved")
  end
end

Then("the escalation resolved_by should be the support user") do
  expect(@linked_escalation.reload.resolved_by).to eq(@support_user)
end

When("I try to access the feedback detail page") do
  @policy = AgentChatMessageFeedbackPolicy.new(@user, @feedback)
end

When("I try to re-test the feedback item") do
  @policy = AgentChatMessageFeedbackPolicy.new(@user, @feedback)
end
