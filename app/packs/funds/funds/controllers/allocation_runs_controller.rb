class AllocationRunsController < ApplicationController
  before_action :set_allocation_run, only: %i[lock unlock]

  def lock
    if @allocation_run.update(locked: true)
      flash[:notice] = "AllocationRun locked successfully."
    else
      flash[:alert] = "Failed to lock AllocationRun."
    end
    redirect_back(fallback_location: allocate_form_fund_path(@allocation_run.fund))
  end

  def unlock
    fund = @allocation_run.fund
    if AllocationRun.where(fund: fund).update_all(locked: false).positive?
      flash[:notice] = "AllocationRun unlocked successfully."
    else
      flash[:alert] = "Failed to unlock AllocationRun."
    end
    redirect_back(fallback_location: allocate_form_fund_path(@allocation_run.fund))
  end

  private

  def set_allocation_run
    @allocation_run = AllocationRun.find(params[:id])
    authorize @allocation_run
  end
end
