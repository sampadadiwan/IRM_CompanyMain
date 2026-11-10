# Finding "the row for X" (or the card / column for X) without paying the wait once per element.
#
# Capybara's has_content?/has_button?/has_css? wait up to Capybara.default_max_wait_time (15 s,
# features/support/env.rb) before answering "no". Steps used to write
#
#   page.all("tr").find { |r| r.has_content?(investor_name) }
#
# which asks that question of every row in turn, so every row BEFORE the match cost a full 15 s:
# on a cap table with a header row and four investors the fourth lookup waited 60 s, and
# captable_shareholder_positions.feature:34 spent ~150 of its 162 s just waiting.
#
# find_first_matching waits ONCE for the whole lookup - Capybara retries the selector + filter
# together until something matches or the wait runs out - so a page that is still loading is
# still waited for. Filters that call has_*? inside the block must pass wait: false, otherwise
# each candidate waits again and the saving is lost.
module FindFirstMatchingHelpers
  # Returns the first element matching `selector` (plus Capybara options such as text:) for which
  # the optional filter block is true, searching inside `scope`. Raises ElementNotFound with
  # `not_found` as the message, so step failures still say what was missing in plain words.
  def find_first_matching(selector, not_found:, scope: page, **, &filter)
    # match: :first keeps the old Array#find meaning - first match in document order, never
    # an Ambiguous error when several elements qualify
    scope.find(selector, match: :first, **, &filter)
  rescue Capybara::ElementNotFound
    raise Capybara::ElementNotFound, not_found
  end
end

World(FindFirstMatchingHelpers)
