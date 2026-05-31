class FundRatioRunsController < ApplicationController
  before_action :set_run, only: %i[show]
  after_action  :verify_authorized

  # GET /fund_ratio_runs
  def index
    authorize FundRatioRun
    @q = policy_scope(FundRatioRun).ransack(params[:q])
    @runs = @q.result.includes(:user).order(created_at: :desc)
    @pagy, @runs = pagy(@runs, limit: params[:per_page] || 25)
  end

  # GET /fund_ratio_runs/:id
  def show
    authorize @run
  end

  private

  def set_run
    @run = FundRatioRun.find(params[:id])
  end
end
