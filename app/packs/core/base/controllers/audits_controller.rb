class AuditsController < ApplicationController
  after_action :verify_policy_scoped, except: :index

  def index
    @q = Audit.ransack(params[:q])
    @audits = policy_scope(@q.result).includes(:user).order(id: :desc)
    # Filter
    @audits = @audits.where(auditable_type: params[:auditable_type]) if params[:auditable_type].present?
    @audits = @audits.where(auditable_id: params[:auditable_id]) if params[:auditable_id].present?
    @audits = @audits.where(user_id: params[:user_id]) if params[:user_id].present?
    @audits = @audits.where(created_at: ..Date.local_parse(params[:created_at_before])) if params[:created_at_before].present?
    @audits = @audits.where(created_at: Date.local_parse(params[:created_at_after])..) if params[:created_at_after].present?

    # Scoped to exactly one record: bounded to that record's own history (same
    # assumption the AuditTrail component already makes for its embedded,
    # unpaginated view), so it's safe to load in full and offer the Field
    # History pivot. Any broader/unscoped query stays paginated — never load
    # an unbounded slice of this table in one go.
    @single_record_scope = params[:auditable_type].present? && params[:auditable_id].present?

    if params[:format] == 'xlsx' && (params[:created_at_before].blank? || params[:created_at_after].blank?)
      @audits = @audits.limit(1000)
    elsif @single_record_scope
      @audits = @audits.to_a
      @field_history = AuditFieldHistory.new(@audits)
    else
      @pagy, @audits = pagy(@audits)
    end

    respond_to do |format|
      format.html
      format.xlsx do
        AuditDownloadJob.perform_later(params.to_unsafe_h, user_id: current_user.id)
        flash[:notice] = "Your request is being processed. You will receive an email shortly."
        redirect_to request.referer
      end
    end
  end
end
