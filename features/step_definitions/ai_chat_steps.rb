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
