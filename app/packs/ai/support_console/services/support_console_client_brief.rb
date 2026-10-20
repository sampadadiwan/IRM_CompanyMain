# frozen_string_literal: true

# The per-client part of the system prompt, appended to the support brief on every turn.
# It is the first of the best-effort scoping layers (design card ⑥): Claude is told which
# client this conversation is about and how every lookup must be filtered.
#
# @see openspec/changes/support-console/design.md (card ③ Turn job, card ⑥ Scope guard)
class SupportConsoleClientBrief
  MAX_FUNDS = 50

  # @param entity [Entity] the conversation's client
  # @return [String]
  def self.call(entity)
    # Names and ids only; one query.
    funds = Fund.where(entity_id: entity.id).order(:name).limit(MAX_FUNDS).pluck(:id, :name)
    fund_lines = funds.map { |id, name| "- #{name} (fund_id #{id})" }
    fund_lines << "- (more funds not listed)" if funds.size == MAX_FUNDS

    <<~BRIEF
      You are investigating ONE client: #{entity.name} (entity_id #{entity.id}).
      Funds:
      #{fund_lines.presence&.join("\n") || '- none'}

      Every lookup on a table that has an entity_id column must filter `entity_id = #{entity.id}`.
      Do not query, compare or mention any other client. If the question needs another client's
      data, say that you can only look at #{entity.name} in this conversation, and stop.
      You cannot change anything. If a fix needs data changed, describe the change instead.
      End every answer with a "Where this comes from" section listing the code locations
      (file:line) and the lookups the answer relied on.
    BRIEF
  end
end
