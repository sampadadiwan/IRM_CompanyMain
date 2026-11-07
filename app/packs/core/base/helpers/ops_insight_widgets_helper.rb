# Ops Dashboard insight widgets that read core data only: Overdue Tasks by Assignee and Stuck Workflows.
# Worked examples H22, H23, E59–E63, X11 — openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#7
module OpsInsightWidgetsHelper
  UNASSIGNED_LABEL = "Unassigned".freeze
  OTHERS_LABEL = "Others".freeze

  # Open tasks past their due date, as [[label, count], ...] largest first, the rest beyond top_n as "Others".
  # H22 — Meera 3, Unassigned 2, Ravi 1; E59 — 12 assignees with top_n 10 give 10 bars plus Others;
  # X11 — counted through the task policy scope, so a non-admin employee counts only the tasks he may see.
  def overdue_tasks_by_assignee(top_n)
    # One grouped query: open tasks whose due date is before today (E54 — due today is not overdue)
    counts = overdue_tasks_scope.unscope(:order).group(:assigned_to_id).count
    return [] if counts.empty?

    # Assignee names in one query, never one per bar
    names = User.where(id: counts.keys.compact).pluck(:id, :first_name, :last_name)
                .to_h { |id, first, last| [id, [first, last].compact_blank.join(" ")] }
    # Label each group; tasks with no assignee are "Unassigned" (H22)
    rows = counts.map { |user_id, count| [user_id ? names.fetch(user_id, "User ##{user_id}") : UNASSIGNED_LABEL, count] }
    # Largest first, ties by name so the order is stable
    rows.sort_by! { |label, count| [-count, label] }
    # E59 — keep top_n bars and fold the rest into one "Others" bar
    return rows if rows.size <= top_n

    rows.first(top_n) << [OTHERS_LABEL, rows.drop(top_n).sum(&:last)]
  end

  # The tasks list showing exactly the tasks the chart counts: open (the list's default) and due before today
  def overdue_tasks_path
    tasks_path(q: ransack_query_params("due_date", :lt, Time.zone.today))
  end

  # Active journeys whose current step started `days` or more days ago, longest wait first, at most `limit`.
  # Returns [rows, total]. H23 — on "Approve notice" since 15 Sep 2026 → 15 days; E61 — exactly 7 days counts;
  # E62 — complete/archived left out; E63 — 6 days is not stuck. A journey whose step start is not recorded
  # (current_step_since blank) has no known wait, so it is not listed.
  def stuck_workflows(days, limit)
    # The cut-off: a step that started on or before this moment has waited `days` days or more (E61)
    cutoff = Time.zone.today.end_of_day - days.days
    scope = policy_scope(WorkflowInstance).instance_active.where(current_step_since: ..cutoff)
    # Total for the "Showing n of m" line, in SQL
    total = scope.count
    # The rows: longest wait first, with the record and template preloaded so no row queries
    rows = scope.order(:current_step_since).limit(limit).includes(:workflowable, :workflow_template).to_a
    [rows, total]
  end

  # Whole days the journey has been on its current step
  def workflow_days_on_step(instance)
    (Time.zone.today - instance.current_step_since.to_date).to_i
  end

  # The record a journey runs on, as the user knows it (e.g. the capital call's name)
  def workflow_record_label(instance)
    record = instance.workflowable
    # Prefer the record's own name; fall back to "<Type> #id" for records without one
    label = record.try(:name).presence || record.try(:to_s)
    label.present? && !label.start_with?("#<") ? label : "#{instance.workflowable_type.titleize} ##{instance.workflowable_id}"
  end

  private

  # Open tasks with a due date before today, through the same policy scope the tasks list uses (X11)
  def overdue_tasks_scope
    policy_scope(Task).where(completed: false).where(due_date: ...Time.zone.today)
  end
end
