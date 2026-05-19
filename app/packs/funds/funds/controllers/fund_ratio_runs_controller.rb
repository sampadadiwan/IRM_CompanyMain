class FundRatioRunsController < ApplicationController
  before_action :set_run
  after_action  :verify_authorized

  # GET /fund_ratio_runs/:id
  def show
    authorize @run
  end

  private

  def set_run
    @run = FundRatioRun.find(params[:id])
  end
end
