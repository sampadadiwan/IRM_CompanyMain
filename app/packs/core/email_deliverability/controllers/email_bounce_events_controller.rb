class EmailBounceEventsController < ApplicationController
  after_action :verify_authorized, except: [:index]
  helper_method :affected_investor_access_count

  # GET /email_bounce_events
  def index
    @email_bounce_events = policy_scope(EmailBounceEvent).includes(:entity).order(occurred_at: :desc)
    @email_bounce_events = @email_bounce_events.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @email_bounce_events = @email_bounce_events.where(event_type: params[:event_type]) if params[:event_type].present?
    @email_bounce_events = @email_bounce_events.where(bounce_type: params[:bounce_type]) if params[:bounce_type].present?
    @email_bounce_events = @email_bounce_events.where(occurred_at: ..Date.local_parse(params[:occurred_at_before])) if params[:occurred_at_before].present?
    @email_bounce_events = @email_bounce_events.where(occurred_at: Date.local_parse(params[:occurred_at_after])..) if params[:occurred_at_after].present?

    @pagy, @email_bounce_events = pagy(@email_bounce_events)

    # Internal admins can filter by entity; everyone else is already scoped to their own.
    # Subquery avoids materialising the full id list into Ruby memory on large tables.
    @entities = Entity.where(id: EmailBounceEvent.select(:entity_id).distinct).order(:name) if current_user.support?

    # One batched query for the whole page instead of one COUNT per row (see
    # affected_investor_access_count) — avoids N+1 on the "Disable Email" button labels.
    recipient_emails = @email_bounce_events.map(&:recipient_email)
    scope = InvestorAccess.where(email: recipient_emails, email_enabled: true)
    scope = scope.where(entity_id: current_user.entity_id) unless current_user.support?
    @investor_access_counts = scope.group(:email).count
  end

  # POST /email_bounce_events/:id/disable_recipient_email
  #
  # Manual, admin-triggered only — bounce/complaint detection itself never touches
  # InvestorAccess.email_enabled automatically (see docs/modules/notifications/
  # email_bounce_complaint_detection_prd.md, Non-Goals). Updates records individually
  # (not update_all) so InvestorAccess's existing `audited` tracking (via `Trackable.new`)
  # captures who did this and when.
  def disable_recipient_email
    email_bounce_event = policy_scope(EmailBounceEvent).find(params[:id])
    authorize email_bounce_event, :disable_recipient_email?

    count = 0
    InvestorAccess.transaction do
      affected_investor_accesses(email_bounce_event).find_each do |access|
        access.update!(email_enabled: false)
        count += 1
      end
    end

    redirect_to email_bounce_events_path, notice: "Disabled email for #{count} InvestorAccess #{'record'.pluralize(count)} sharing #{email_bounce_event.recipient_email}."
  end

  private

  # Scoped identically for both the confirmation-count preview (index) and the actual
  # bulk update (disable_recipient_email), so the count shown to the user is always
  # exactly what the action will affect.
  def affected_investor_accesses(email_bounce_event)
    scope = InvestorAccess.where(email: email_bounce_event.recipient_email, email_enabled: true)
    current_user.support? ? scope : scope.where(entity_id: current_user.entity_id)
  end

  # Uses the batched @investor_access_counts computed in #index when available (the normal
  # path — avoids N+1). Falls back to a live count so this stays correct if ever called
  # outside #index (e.g. a future single-event view).
  def affected_investor_access_count(email_bounce_event)
    if @investor_access_counts
      @investor_access_counts.fetch(email_bounce_event.recipient_email, 0)
    else
      affected_investor_accesses(email_bounce_event).count
    end
  end
end
