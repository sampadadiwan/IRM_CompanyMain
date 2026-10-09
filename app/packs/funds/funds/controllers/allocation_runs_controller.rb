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
    # Locked financial statements this unlock touches (none: behaviour is exactly as before).
    # Worked examples H17, E8 — openspec/changes/fund-financial-statements/design.md#worked-examples
    affected_statements = FinancialStatementUnlockGuard.affected(fund, @allocation_run.start_date, @allocation_run.end_date).to_a
    # Unlock every locked run overlapping this one's period, not just an exact end_date
    # match -- locked_and_overlapping (the check that blocks a new run) matches on
    # fund + date-range overlap, so unlocking has to use the same definition or a
    # differently-dated overlapping run is left locked and still blocks new runs.
    result = AllocationRun.where(fund: fund).locked
                          .overlapping(@allocation_run.start_date, @allocation_run.end_date)
                          .update_all(locked: false)
    # Back to Draft + one notification to Fund accounting — only when runs really were unlocked
    demoted = result.positive? ? FinancialStatementUnlockGuard.demote!(affected_statements, user: current_user) : 0
    if result.positive?
      flash[:notice] = "Unlocked #{result} AllocationRun#{'s' if result != 1} for this period."
      flash[:notice] += " #{demoted} locked financial statement set#{'s' if demoted != 1} went back to Draft." if demoted.positive?
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

    # Every locked financial statement set of the fund (E15: one notification lists them all)
    affected_statements = FinancialStatementUnlockGuard.affected(fund).to_a
    # Unlock all Locked AllocationRuns for the fund
    result = AllocationRun.where(fund: fund).locked.update_all(locked: false)
    demoted = result.positive? ? FinancialStatementUnlockGuard.demote!(affected_statements, user: current_user) : 0

    if result.positive?
      # Display number of records unlocked
      flash[:notice] = "All #{result} AllocationRuns unlocked successfully."
      flash[:notice] += " #{demoted} locked financial statement set#{'s' if demoted != 1} went back to Draft." if demoted.positive?
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
