# frozen_string_literal: true

# Adapter chat provider that bridges the support_agents chat harness
# to the existing BaseAssistant-based PortfolioAssistant /
# PortfolioCompanyAssistant services in the assistants/ pack.
#
# Routing is driven by the `target` (chattable) passed in from the
# chat panel:
#   - target is an Investor with category "Portfolio Company"
#       → wraps PortfolioCompanyAssistant (single-company scope)
#   - otherwise (target is the FM Entity, or anything else)
#       → wraps PortfolioAssistant (cross-company scope)
#
# This is a pure adapter: it does not reimplement tools or prompts.
# The harness (GenericChatAgent) drives the RubyLLM loop using the
# wrapped assistant's `tools` and `system_prompt`.
class PortfolioAssistantChatProvider < BaseChatProvider
  # @!method system_prompt
  #   @return [String] system prompt sourced from the wrapped assistant
  # @!method tools
  #   @return [Array<RubyLLM::Tool>] tool list sourced from the wrapped assistant
  delegate :system_prompt, :tools, to: :wrapped_assistant

  private

  # @return [Symbol] :single when scoped to one portfolio company, :cross otherwise
  def mode
    @mode ||= portfolio_company_target? ? :single : :cross
  end

  # True only when the chat target is a portfolio-company Investor *belonging to
  # the same FM as this SupportAgent*. Cross-tenant targets fall through to the
  # cross-portfolio assistant, which scopes to the analyst's own access — this
  # prevents `target.investor_name`/`id` interpolation in the wrapped assistant's
  # system prompt from echoing another tenant's record back to the user.
  # @return [Boolean]
  def portfolio_company_target?
    target.is_a?(Investor) &&
      target.category == "Portfolio Company" &&
      target.entity_id == support_agent.entity_id
  end

  # @return [BaseAssistant] memoized assistant instance for this chat
  def wrapped_assistant
    @wrapped_assistant ||= if portfolio_company_target?
                             PortfolioCompanyAssistant.new(user: analyst, portfolio_company: target)
                           else
                             log_cross_tenant_target if cross_tenant_portfolio_company?
                             PortfolioAssistant.new(user: analyst)
                           end
  end

  # True when target *looks* like a portfolio company but is from another FM —
  # we deliberately fall back to cross mode rather than raising, but the event
  # is worth logging.
  # @return [Boolean]
  def cross_tenant_portfolio_company?
    target.is_a?(Investor) &&
      target.category == "Portfolio Company" &&
      target.entity_id != support_agent.entity_id
  end

  # @return [void]
  def log_cross_tenant_target
    Rails.logger.warn(
      "[PortfolioAssistantChatProvider] cross-tenant target rejected: " \
      "agent=##{support_agent.id} (entity=#{support_agent.entity_id}) " \
      "target=Investor##{target.id} (entity=#{target.entity_id}) — falling back to cross mode"
    )
  end
end
