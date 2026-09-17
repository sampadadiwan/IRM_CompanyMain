# frozen_string_literal: true

# View helpers for the weekly task digest email (TaskDigestMailer#weekly_digest).
#
# The links here matter as much as the numbers: every "View all" must land on the
# same set the section counted, or the reader stops trusting the mail. Each one
# reproduces its section's filter through the params TaskList already understands.
#
# sub_domain is a query param, not a host rewrite — WithAuthentication#set_current_entity
# reads params[:sub_domain] specifically for links arriving from email. Same shape as
# TaskNotifier#url.
module TaskDigestHelper
  # A single task's page.
  def digest_task_url(task, entity)
    task_url(id: task.id, sub_domain: entity.sub_domain)
  end

  # The task board, for the closing call to action.
  def digest_board_url(entity)
    tasks_url(board: true, sub_domain: entity.sub_domain)
  end

  # Open tasks overdue within DELAYED_WINDOW.
  #
  # An explicit date range rather than due_filter=overdue: that filter is unbounded,
  # so it would show tasks older than the window and disagree with the "+N more"
  # count printed next to the link. TaskList defaults to incomplete-only, so open-ness
  # needs no param.
  def digest_delayed_url(digest)
    tasks_url(
      sub_domain: digest.entity.sub_domain,
      q: { due_date_gteq: digest.as_of - WeeklyTaskDigest::DELAYED_WINDOW, due_date_lteq: digest.as_of - 1.day }
    )
  end

  # Open tasks due next week.
  #
  # An explicit date range, NOT due_filter=next_week. That key looks nicer (the landing
  # page shows the dropdown already selected) but Task.due_filter_range resolves it
  # against Time.zone.today when the link is CLICKED, not when the digest was built.
  # The digest goes out Friday; a recipient who opens it on Monday would land on the
  # following week — a set with no overlap at all with the rows and the count printed
  # next to the link.
  def digest_due_next_week_url(digest)
    week = digest.next_week_range
    tasks_url(
      sub_domain: digest.entity.sub_domain,
      q: { due_date_gteq: week.first, due_date_lteq: week.last }
    )
  end

  # Tasks closed this week. completed=all lifts TaskList's incomplete-only default;
  # completed_eq then narrows to the closed ones.
  def digest_completed_url(digest)
    week = digest.week_range
    tasks_url(
      sub_domain: digest.entity.sub_domain,
      completed: "all",
      q: { completed_eq: true, completed_on_gteq: week.first, completed_on_lteq: week.last }
    )
  end

  # The four numbers across the top, mirroring the in-app stat cards
  # (tasks/_stats.html.erb) so the email and the dashboard teach the same thing.
  #
  # "Open total" is the denominator: 7 delayed reads very differently against 12 open
  # tasks than against 300.
  def digest_stat_tiles(digest)
    counts = digest.counts
    [
      { value: counts[:completed_this_week], label: "Done this week", tone: :success },
      { value: counts[:due_next_week], label: "Due next week", tone: :info },
      { value: counts[:delayed], label: "Delayed", tone: counts[:delayed].zero? ? :muted : :danger },
      { value: counts[:open_total], label: "Open total", tone: :warning }
    ]
  end

  # The muted one-liner under the tiles: week-over-week movement, how far the oldest
  # delayed task has drifted, and (fund-wide recipients only) how many people the open
  # work is spread across. Returns nil when there is nothing worth saying.
  def digest_context_note(digest)
    parts = [digest_delta_phrase(digest)]
    parts << "oldest delayed #{pluralize(digest.oldest_delayed_days, 'day')}" if digest.oldest_delayed_days
    parts << "across #{pluralize(digest.counts[:open_assignees], 'assignee')}" if digest.team_view? && digest.counts[:open_assignees].positive?
    parts.compact!
    return nil if parts.empty?

    # A literal middot rather than the entity, so this stays a plain String: nothing
    # here is markup or user input, and both the HTML and the text part can use it
    # verbatim without an html_safe.
    parts.join(" \u00B7 ")
  end

  # Days late for the delayed table's badge.
  def digest_days_late(task, digest)
    (digest.as_of - task.due_date).to_i
  end

  # Task text for a row. display_details, not details: it falls back to the legacy
  # pre-ActionText column, so tasks created years ago render their text instead of
  # a blank cell.
  def digest_task_label(task)
    task.display_details.to_s.squish.truncate(90).presence || "Task ##{task.id}"
  end

  # The running note a fund user keeps on the task — the "Response" field on the task
  # form. Rendered as a quiet second line under the title so the digest carries the
  # latest word on a delayed item, not just the fact that it is delayed.
  # nil when the task has no note, in which case the row simply omits the line.
  def digest_task_note(task)
    task.display_response.to_s.squish.truncate(140).presence
  end

  # "Echo Inc : Portfolio Company · FM7 User1" — who the task is for and who owns it,
  # collapsed onto one metadata line under the title.
  #
  # These used to be two more table columns. At email width that squeezed the title
  # into three wrapped lines per row; as metadata they cost no width at all and the
  # table drops to three columns.
  def digest_task_meta(task)
    parts = [task.owner_display_name.presence, task.assigned_to&.full_name.presence || "Unassigned"]
    parts.compact.join(" \u00B7 ")
  end

  private

  def digest_delta_phrase(digest)
    delta = digest.completed_delta
    return "same as last week" if delta.zero?

    delta.positive? ? "#{delta} more than last week" : "#{delta.abs} fewer than last week"
  end
end
