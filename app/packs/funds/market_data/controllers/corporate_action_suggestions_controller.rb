# Portfolio › Corporate actions: confirm or dismiss suggestions from the price feed.
# Worked examples H10, E46 — openspec/changes/fund-market-data/business-rules.md
class CorporateActionSuggestionsController < ApplicationController
  before_action :set_suggestion, only: %i[confirm dismiss]

  def index
    authorize(CorporateActionSuggestion)
    @bread_crumbs = { 'Corporate actions': corporate_action_suggestions_path }
    @status = params[:status].presence_in(%w[pending confirmed dismissed]) || "pending"
    @suggestions = policy_scope(CorporateActionSuggestion).where(status: @status).includes(:investment_instrument).order(:ex_date)
  end

  def confirm
    @suggestion.confirm!(current_user)
    # Back to where the button was pressed — the Corporate actions list or an instrument's tab
    redirect_back_or_to corporate_action_suggestions_path, notice: "Corporate action confirmed."
  rescue CorporateActionSuggestion::InvalidTransition, ActiveRecord::RecordInvalid => e
    redirect_back_or_to corporate_action_suggestions_path, alert: e.message
  end

  def dismiss
    @suggestion.dismiss!(current_user)
    # Back to where the button was pressed — the Corporate actions list or an instrument's tab
    redirect_back_or_to corporate_action_suggestions_path, notice: "Corporate action dismissed."
  rescue CorporateActionSuggestion::InvalidTransition => e
    redirect_back_or_to corporate_action_suggestions_path, alert: e.message
  end

  private

  def set_suggestion
    @suggestion = CorporateActionSuggestion.find(params[:id])
    authorize(@suggestion)
  end
end
