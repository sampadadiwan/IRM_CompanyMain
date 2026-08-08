# frozen_string_literal: true

# Consolidated due-date alert for side letter obligations — one email per
# recipient per enforcement run, listing all their upcoming / due / overdue
# obligation tasks.
#
# @see ObligationEnforcement
# @see ObligationAlertNotifier
class SideLetterObligationMailer < SupportAgentBaseMailer
  def obligation_reminder
    @user = User.find(params[:user_id])
    @support_agent = SupportAgent.find(params[:support_agent_id])
    @entity = @support_agent.entity
    @items = Array(params[:items])
    # Overdue first, then by due date — the email leads with the worst news
    kind_rank = { "overdue" => 0, "due" => 1, "upcoming" => 2 }
    @items = @items.sort_by { |i| [kind_rank[i["kind"]] || 3, i["due_date"].to_s] }

    counts = @items.group_by { |i| i["kind"] }.transform_values(&:count)
    subject_parts = %w[overdue due upcoming].filter_map do |kind|
      "#{counts[kind]} #{kind}" if counts[kind]
    end

    mail(to: @user.email, subject: "Side Letter Obligations — #{subject_parts.join(', ')}")
  end
end
