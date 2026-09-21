# frozen_string_literal: true

# Builds one recipient's weekly task digest — the three row sets and the summary
# stats behind them. See docs/modules/tasks/weekly_task_digest_prd.md.
#
# Called once per (entity, recipient) pair by WeeklyTaskDigestJob, and rendered by
# TaskDigestMailer. Kept out of the mailer so the buckets and the numbers can be
# tested without rendering anything.
#
# Every query runs through TaskPolicy::Scope for the recipient, so the email shows
# exactly what that person can open in the app: a company admin gets the whole fund
# (including tasks another entity logged FOR it, via the policy's for_entity_id arm),
# an employee gets their own assignments plus deal tasks. Nothing in the mail is a
# task whose link would 404 for the person who received it.
class WeeklyTaskDigest
  # How far back the "Delayed" section reaches. A fund with years of abandoned tasks
  # would otherwise open the digest onto a section nobody reads.
  #
  # Deliberately NOT on Task: Task.delayed and Task#delayed? drive the "Delayed" badge
  # on the list row and the board card and must keep meaning "overdue at all".
  # Narrowing them here would silently change the UI.
  DELAYED_WINDOW = 90.days

  # Rows rendered per section before the email switches to a "+N more" link. An
  # unbounded table is both an unreadable email and an unbounded render.
  ROW_LIMIT = 15

  Result = Struct.new(:user, :entity, :as_of, :counts, :delayed, :due_next_week, :completed, keyword_init: true) do
    # Nothing closed, nothing coming, nothing overdue — no email. A recurring
    # "you have nothing" message is the fastest way to get a sender filtered.
    # Reads the aggregate counts, never the relations (CLAUDE.md: no blank?/present?
    # on a relation).
    def empty?
      counts[:completed_this_week].zero? && counts[:due_next_week].zero? && counts[:delayed].zero?
    end

    def week_range = as_of.all_week
    def next_week_range = (as_of + 1.week).all_week

    # Rows that matched but did not fit under ROW_LIMIT, per section.
    def more_delayed = [counts[:delayed] - delayed.size, 0].max
    def more_due_next_week = [counts[:due_next_week] - due_next_week.size, 0].max
    def more_completed = [counts[:completed_this_week] - completed.size, 0].max

    # Colour and headline for the banner: the delayed count decides the mood of the
    # whole email before a single number is read.
    def tone
      case counts[:delayed]
      when 0 then :success
      when 1..5 then :warning
      else :danger
      end
    end

    def headline
      counts[:delayed].zero? ? "All on track" : "#{counts[:delayed]} delayed"
    end

    # Week-over-week completion movement — the one number in a weekly digest that
    # anybody feels. nil when there is nothing to compare against.
    def completed_delta
      counts[:completed_this_week] - counts[:completed_last_week]
    end

    def oldest_delayed_days
      due = counts[:oldest_delayed_due_date]
      return nil if due.blank?

      (as_of - due).to_i
    end

    # True when this recipient's scope spans more than their own work, which is the
    # only case where an assignee spread is worth printing.
    def team_view?
      user.support? || user.has_cached_role?(:company_admin)
    end
  end

  # @param user [User] the recipient; also the subject of the policy scope
  # @param entity [Entity] the fund the digest is about
  # @param as_of [Date] treated as "today" — the send date
  def initialize(user, entity, as_of: Time.zone.today)
    @user = user
    @entity = entity
    @as_of = as_of
  end

  # The aggregate pass on its own — six numbers, one query, no rows loaded.
  # WeeklyTaskDigestJob uses this to decide whether a recipient is worth an email
  # without paying for the three row queries first.
  def counts
    @counts ||= Task.digest_counts(scope, as_of: @as_of, delayed_window: DELAYED_WINDOW)
  end

  # True when at least one of the three sections has something in it.
  def any?
    counts.values_at(:completed_this_week, :due_next_week, :delayed).sum.positive?
  end

  def call
    Result.new(
      user: @user,
      entity: @entity,
      as_of: @as_of,
      counts: counts,
      # Delayed leads the email: it is the only section that needs action today.
      delayed: rows(scope.incomplete.where(due_date: delayed_range), :due_date, :asc),
      due_next_week: rows(scope.incomplete.where(due_date: next_week_range), :due_date, :asc),
      completed: rows(scope.completed.where(completed_on: week_range), :completed_on, :desc)
    )
  end

  private

  # Task.all, not entity.tasks: TaskPolicy::Scope resolves
  # `entity_id = ? OR for_entity_id = ?` for admins, and pre-narrowing to
  # entity.tasks would drop the for_entity arm before the policy ever sees it.
  def scope
    @scope ||= TaskPolicy::Scope.new(@user, Task.all).resolve
  end

  def week_range = @as_of.all_week
  def next_week_range = (@as_of + 1.week).all_week

  # Half-open at today's end: a task due today is not yet delayed, matching
  # Task#delayed?. Bounded below by DELAYED_WINDOW.
  def delayed_range = ((@as_of - DELAYED_WINDOW)..(@as_of - 1.day))

  # Loaded (to_a) rather than left lazy so the view can ask .size for the "+N more"
  # arithmetic without issuing a second COUNT over rows it is about to iterate anyway.
  #
  # Preloads are exactly what a row renders: the task text, its response note, the
  # owner label (Task#owner_display_name) and the assignee. rich_text_response is
  # here and NOT in TaskList on purpose — the list views don't show the response, the
  # digest row does. Still nothing speculative: task_template, for_entity and user are
  # left out because no part of the email touches them.
  def rows(relation, order_column, direction)
    relation.includes(:assigned_to, :owner, :rich_text_details, :rich_text_response)
            .reorder(order_column => direction, :id => :asc)
            .limit(ROW_LIMIT)
            .to_a
  end
end
