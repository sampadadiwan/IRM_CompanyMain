# frozen_string_literal: true

# Chatbot questions from the last 30 days where guide search found nothing, or nothing that
# matched two-thirds of the search terms. Each row links to a prefilled new FAQ.
class GuideSearchMissesController < ApplicationController
  DAYS = 30
  LIMIT = 100

  def index
    authorize :guide_search_miss
    # Scoped by GuideSearchMissPolicy#scope_messages (support users see only mapped entities).
    skip_policy_scope
    messages = GuideSearchMissPolicy.new(current_user, :guide_search_miss)
                                    .scope_messages(AgentChatMessage.guide_misses.where(created_at: DAYS.days.ago..))
    @misses = messages.includes(agent_chat_session: { support_agent: :entity })
                      .order(created_at: :desc).limit(LIMIT).to_a
    @questions = @misses.index_with { |m| m.preceding_user_message&.content }
    @term_counts = @misses.map(&:guide_search_terms).tally.sort_by { |_, count| -count }.first(15)
  end
end
