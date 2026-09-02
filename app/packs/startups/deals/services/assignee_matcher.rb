# frozen_string_literal: true

# Matches an assignee name from a parsed email against team members
# who have access to the deal.
#
# Best-effort matching — if no confident match is found, returns nil
# and the task falls back to being assigned to the sender.
# Never raises, never blocks task creation.
#
# Matching strategy:
#   1. Exact match on full name (case-insensitive)
#   2. Exact match on first name (case-insensitive)
#   3. Exact match on last name (case-insensitive)
#   4. If multiple matches at any step, no match (ambiguous)
#
# @example
#   AssigneeMatcher.call(assignee_string: "Neil", deal: deal)
#   # => #<User id: 42, first_name: "Neil", ...> or nil
#
# @see DealIngestProcessor where this is called
class AssigneeMatcher
  # Match an assignee name against deal team members.
  #
  # @param assignee_string [String, nil] the name extracted by the LLM
  # @param deal [Deal] the deal to scope team members
  # @return [User, nil] the matched user, or nil if no confident match
  def self.call(assignee_string:, deal:)
    return nil if assignee_string.blank?

    new(assignee_string:, deal:).match
  end

  def initialize(assignee_string:, deal:)
    @name = assignee_string.strip.downcase
    @deal = deal
  end

  # Run the matching logic.
  #
  # @return [User, nil]
  def match
    candidates = deal_team_members
    return nil if candidates.empty?

    by_full_name = candidates.select { |u| u.name&.downcase == @name }
    return by_full_name.first if by_full_name.size == 1

    by_first_name = candidates.select { |u| u.first_name&.downcase == @name }
    return by_first_name.first if by_first_name.size == 1

    by_last_name = candidates.select { |u| u.last_name&.downcase == @name }
    return by_last_name.first if by_last_name.size == 1

    nil
  end

  private

  # Fetch all users who have access to this deal.
  # Includes users with AccessRight on the deal and company_admins.
  #
  # @return [Array<User>]
  def deal_team_members
    access_user_ids = AccessRight.where(owner: @deal).pluck(:user_id)
    admin_user_ids = User.with_role(:company_admin, @deal.entity).pluck(:id)

    User.where(id: (access_user_ids + admin_user_ids).uniq)
  end
end
