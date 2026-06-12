class AllocationRunsController < ApplicationController
  before_action :set_allocation_run, only: %i[lock unlock]

  def lock
    if @allocation_run.update(locked: true)
      flash[:notice] = "AllocationRun locked successfully."
    else
      flash[:alert] = "Failed to lock AllocationRun."
    end
    redirect_back_or_to(allocate_form_fund_path(@allocation_run.fund))
  end

  def unlock
    fund = @allocation_run.fund
    # We want to unlock AllocationRuns with the same end_date
    if AllocationRun.where(fund: fund, end_date: @allocation_run.end_date).update_all(locked: false).positive?
      flash[:notice] = "AllocationRun unlocked successfully."
    else
      flash[:alert] = "Failed to unlock AllocationRun."
    end
    redirect_back_or_to(allocate_form_fund_path(@allocation_run.fund))
  end

  def unlock_all
    authorize(AllocationRun, :unlock_all?)
    if params[:fund_id].blank?
      flash[:alert] = "Fund ID is required to unlock all AllocationRuns."
      redirect_to(funds_path) && return
    end

    fund = Pundit.policy_scope(current_user, Fund).find_by(id: params[:fund_id])
    if fund.blank?
      flash[:alert] = "Fund not found or you do not have access."
      redirect_to(funds_path) && return
    end

    # Unlock all Locked AllocationRuns for the fund
    result = AllocationRun.where(fund: fund).locked.update_all(locked: false)

    if result.positive?
      # Display number of records unlocked
      flash[:notice] = "All #{result} AllocationRuns unlocked successfully."
    else
      flash[:alert] = "Failed to unlock AllocationRuns."
    end
    redirect_back_or_to(allocate_form_fund_path(fund))
  end
  # rubocop :enable Rails/SkipsModelValidations

  private

  def set_allocation_run
    @allocation_run = AllocationRun.find(params[:id])
    authorize @allocation_run
  end
end
