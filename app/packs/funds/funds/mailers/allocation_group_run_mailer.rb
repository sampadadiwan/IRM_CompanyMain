# Emails the employee who triggered an allocation run group when it finishes (decision 19(b)):
# a close runs long enough that they will have moved on, and a failure must reach them even
# after they have logged out.
class AllocationGroupRunMailer < ApplicationMailer
  # Called with .with(allocation_group_run_id:). setup_defaults (ApplicationMailer) needs
  # entity_id and user_id in params to resolve @to/@from/@cc and the sandbox redirect, so
  # those are derived from the run here before it runs.
  before_action :load_group_run

  def completed
    outcome = @group_run.success? ? "finished successfully" : "stopped after a failure"
    send_mail(subject: "Allocation run group \"#{@group_run.group_name}\" #{outcome} — #{@group_run.entity.name}")
  end

  private

  def load_group_run
    @group_run = AllocationGroupRun.find(params[:allocation_group_run_id])
    @entity = @group_run.entity
    @user = @group_run.user
    @items = @group_run.items.includes(:fund, :allocation_run)
    # setup_defaults reads params for entity_id / user_id; they are not passed by the job,
    # so set the ivars it would have set from the run itself.
    @from = from_email(@entity)
    @to = @entity.entity_setting.sandbox ? @entity.entity_setting.sandbox_emails : @user.email
    @cc = nil
    @reply_to = @from
  end
end
