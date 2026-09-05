# Read-only history and progress of allocation run group executions.
class AllocationGroupRunsController < ApplicationController
  helper AllocationRunTemplatesHelper
  after_action :verify_authorized

  # GET /allocation_group_runs — every run for the entity, newest first
  def index
    authorize AllocationGroupRun
    @group_runs = policy_scope(AllocationGroupRun).includes(:items, :user, :allocation_run_template_group).recent
  end

  # GET /allocation_group_runs/:id — progress view; polled by the auto-refresh controller while active
  def show
    @group_run = policy_scope(AllocationGroupRun).find(params[:id])
    authorize @group_run
    @items = @group_run.items.includes(:fund, :allocation_run, :allocation_run_template)
    @tab = %w[progress details].include?(params[:tab]) ? params[:tab] : "progress"
  end
end
