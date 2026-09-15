# frozen_string_literal: true

# Step definitions for features/customer_support_agent/guide_search_ranking.feature
# Exercises SearchUserGuidesTool directly against docs/user_guides, no LLM involved.

When("the guide search tool is called with keywords {string}") do |keywords|
  @guide_search_keywords = keywords.downcase.scan(/[[:alnum:]_-]+/) - SearchUserGuidesTool::STOP_WORDS
  @guide_search_tool = SearchUserGuidesTool.new
  @guide_search_output = @guide_search_tool.execute(keywords: keywords)
  @guide_search_results = @guide_search_tool.last_search_results
  expect(@guide_search_tool.guide_search_hit?).to be(true), "expected guide matches for #{keywords.inspect}, got:\n#{@guide_search_output}"
end

Then("the top result should come from {string}") do |file|
  expect(@guide_search_results.first[:file]).to eq(file),
                                                "top result was #{@guide_search_results.first[:file]}:#{@guide_search_results.first[:line]}"
end

Then("the top result should come from a guide named like {string}") do |fragment|
  expect(@guide_search_results.first[:file]).to include(fragment),
                                                "top result was #{@guide_search_results.first[:file]}:#{@guide_search_results.first[:line]}"
end

Then("the top result should mention {string}") do |text|
  expect(@guide_search_results.first[:snippet]).to include(text)
end

Then("the results should include {string}") do |file|
  expect(@guide_search_results.pluck(:file)).to include(file)
end

Then("every result should contain at least {int} of the keywords") do |min_hits|
  @guide_search_results.each do |result|
    hits = @guide_search_keywords.count { |k| result[:snippet].match?(@guide_search_tool.send(:term_pattern, k)) }
    expect(hits).to be >= min_hits, "#{result[:file]}:#{result[:line]} matched only #{hits} keyword(s)"
  end
end

Then("no guide should appear more than {int} times in the results") do |max|
  counts = @guide_search_results.pluck(:file).tally
  expect(counts.values.max).to be <= max, "per-file counts: #{counts.inspect}"
end

Then("the top result should be a heading or FAQ question line") do
  top = @guide_search_results.first
  expect(top[:heading]).to be(true),
                           "top result #{top[:file]}:#{top[:line]} is a body line, not a heading/FAQ question"
end
