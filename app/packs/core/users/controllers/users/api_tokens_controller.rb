module Users
  # Website › Profile › API tokens: named tokens for scripts and integrations, made from a signed-in
  # (two-factor-verified) session, shown once, revocable (funds-json-api-hardening card ①; H10 H12).
  class ApiTokensController < ApplicationController
    # X20: a bearer token can never make, list or revoke tokens — only a website session can
    before_action :refuse_bearer_tokens

    def index
      authorize ApiToken
      # A user has at most MAX_LIVE live rows plus whatever they revoked or let expire
      @api_tokens = policy_scope(ApiToken).order(Arel.sql("revoked_at IS NULL DESC"), created_at: :desc)
      @api_token = ApiToken.new
    end

    # H10: mint, then show the token string once in a modal
    def create
      authorize ApiToken
      @api_token, @access_token = ApiToken.mint!(user: current_user, name: params.dig(:api_token, :name).to_s.strip)
      # The token is a secret: keep the page that shows it out of every cache
      response.headers["Cache-Control"] = "no-store"
      @api_tokens = policy_scope(ApiToken).order(Arel.sql("revoked_at IS NULL DESC"), created_at: :desc)
      render :index
    rescue ActiveRecord::RecordInvalid => e
      # X18: name missing, or the 11th live token
      redirect_to users_api_tokens_path, alert: e.record.errors.full_messages.to_sentence
    end

    # H12: revoke now; X19: another user's token is not found in this user's scope
    def destroy
      @api_token = policy_scope(ApiToken).find(params[:id])
      authorize @api_token
      @api_token.revoke!
      redirect_to users_api_tokens_path, notice: "\"#{@api_token.name}\" has been revoked."
    end

    private

    def refuse_bearer_tokens
      return unless api_request?

      skip_authorization
      skip_policy_scope
      render json: { error: "Access Denied" }, status: :forbidden
    end
  end
end
