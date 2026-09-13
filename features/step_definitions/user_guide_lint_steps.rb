# frozen_string_literal: true

# Step definitions for features/core/user_guide_lint.feature — runs UserGuideLint over
# docs/user_guides/**/*.md against the real router and file tree, no browser or DB involved.

When("the user guides are linted") do
  @user_guide_lint = UserGuideLint.new
end

Then("no user guide should show a raw app path in backticks") do
  errors = @user_guide_lint.route_errors
  expect(errors).to be_empty, "raw app paths in user guides (use a link or describe the page):\n#{errors.join("\n")}"
end

Then("every relative link in the user guides should point to an existing guide") do
  errors = @user_guide_lint.link_errors
  expect(errors).to be_empty, "dangling guide links:\n#{errors.join("\n")}"
end

Then("every FAQ question in the user guides should be directly followed by its answer") do
  errors = @user_guide_lint.faq_shape_errors
  expect(errors).to be_empty, "FAQ questions with no answer on the next line:\n#{errors.join("\n")}"
end

Then("no FAQ answer in the user guides should exceed {int} lines") do |max|
  expect(UserGuideLint::MAX_ANSWER_LINES).to eq(max)
  errors = @user_guide_lint.faq_length_errors
  expect(errors).to be_empty, "FAQ answers longer than #{max} lines:\n#{errors.join("\n")}"
end

Then("every FAQ entry in the user guides should render as an accordion item") do
  errors = @user_guide_lint.faq_render_errors
  expect(errors).to be_empty, "FAQ entries the guide renderer does not turn into accordion items:\n#{errors.join("\n")}"
end
