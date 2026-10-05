# Presentation for the journey card (workflow_instances/_journey_panel.html.erb), shared by every
# record type with a journey (capital calls, capital distributions): how each evaluated step is
# drawn in the rail, what its tooltip says, and how far the journey has got.
#
# Moved here from CapitalCallJourneyHelper so distributions reuse it instead of copying it
# (capital-distribution-journey design Decision 3). Nothing in it is call-specific.
# Worked examples H3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
# UI journey J2.1 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#what-users-see
#
# Kept out of the view because every step in the rail needs the same three decisions
# (icon, modifier class, tooltip) and the view would otherwise repeat them inline.
module JourneyHelper
  # Icon + modifier class per evaluated step status. The icon SHAPE differs per status, not just
  # the colour, so the rail is still readable without colour vision.
  JOURNEY_STEP_VIEWS = {
    "passed" => { icon: "ti-check", modifier: "cc-step--passed" },
    "current" => { icon: "ti-circle-dot", modifier: "cc-step--current" },
    "error" => { icon: "ti-alert-triangle", modifier: "cc-step--error" },
    "not_yet" => { icon: "ti-circle", modifier: "" },
    # A slash inside the dot: the universal "does not apply", and unmistakable next to the tick,
    # the ring and the dot even in grey (a bare minus read as an unfinished dash)
    "na" => { icon: "ti-slash", modifier: "cc-step--na" }
  }.freeze

  # A current step that was done before and got undone: drawn amber with a "went backwards" icon
  JOURNEY_REGRESSED_VIEW = { icon: "ti-rotate-2", modifier: "cc-step--moved" }.freeze

  # What kind of work a step is. Shown in the tooltip because `kind` is on every evaluator result
  # but is invisible on the page today — it is the difference between "this will tick itself off"
  # and "this is waiting for me".
  JOURNEY_KIND_LABELS = {
    "system" => "Checked automatically",
    "acknowledge" => "Needs your review",
    "human" => "Needs sign-off"
  }.freeze

  # Plain-word status, used for the pill's aria-label (a tooltip is mouse-only)
  JOURNEY_STATUS_WORDS = {
    "passed" => "done", "current" => "in progress", "error" => "could not be checked",
    "not_yet" => "not started", "na" => "not applicable"
  }.freeze

  # Icon + callout modifier for the "What's needed now" panel, keyed by the current step's state
  def journey_now_view(step)
    return { icon: "ti-rotate-2", modifier: "cc-now--moved" } if step[:regressed]
    return { icon: "ti-alert-triangle", modifier: "cc-now--error" } if step[:status].to_s == "error"
    return { icon: "ti-eye-check", modifier: "" } if step[:kind].to_s == "acknowledge"

    { icon: "ti-progress", modifier: "" }
  end

  # Icon + modifier class for one step in the rail
  def journey_step_view(step)
    return JOURNEY_REGRESSED_VIEW if step[:status].to_s == "current" && step[:regressed]

    JOURNEY_STEP_VIEWS.fetch(step[:status].to_s, JOURNEY_STEP_VIEWS["not_yet"])
  end

  # Tooltip body for one step: what state it is in, and what kind of step it is. The step's name is
  # left out — it is already printed under the pill the tooltip hangs off.
  #
  # Returns a PLAIN String (never html_safe) whose own markup is literal `<br>` but whose
  # step-supplied text is already escaped. The view prints it into data-bs-title, so ERB escapes
  # the whole thing once: the browser then hands Bootstrap (data-bs-html="true") our tags as
  # markup and anything that came from the step as text. Marking it html_safe here would let a
  # step name or message inject HTML into the tooltip.
  def journey_step_tooltip(step)
    [
      journey_step_state_line(step),
      JOURNEY_KIND_LABELS[step[:kind].to_s]
    ].compact_blank.join("<br>")
  end

  # Short text alternative to the tooltip, for screen readers
  def journey_step_aria(step)
    word = step[:regressed] && step[:status].to_s == "current" ? "moved back" : JOURNEY_STATUS_WORDS[step[:status].to_s]
    "#{step[:name]} — #{word}"
  end

  # How far the journey has got, as [done, total, percent].
  #
  # Counts only steps that apply to this record: an n/a step can never be passed, so leaving it in
  # the denominator would park the bar below 100% for the whole journey.
  def journey_progress(steps)
    applicable = steps.reject { |s| s[:status].to_s == "na" }
    done = applicable.count { |s| s[:status].to_s == "passed" }
    percent = applicable.any? ? (done * 100.0 / applicable.size).round : 0
    [done, applicable.size, percent]
  end

  # How long a finished journey stays on the record's page before it folds itself away. Long enough
  # that whoever ticked off the last task sees it finish, and that a colleague reading the record
  # the same day still sees what happened.
  JOURNEY_HIDE_COMPLETED_AFTER = 1.day

  # True when a complete journey has been complete long enough to get out of the way: the card is
  # rendered hidden and the breadcrumb's journey icon brings it back (journey_reveal_controller).
  #
  # A journey that has only just finished stays on the page — hiding it the instant the last task
  # passes would make the card seem to vanish just as the user finished it, which is the one moment
  # they want to see it. An instance with no completed_at (complete only because every step turned
  # out to be n/a, so nothing ever "finished") is never hidden: there is no clock to measure from.
  def journey_hide_completed?(instance)
    instance.completed_at.present? && instance.completed_at < JOURNEY_HIDE_COMPLETED_AFTER.ago
  end

  # True once a step has been current for longer than its own reminder interval — the same
  # threshold the auto-reminder job uses, so the chip turns amber exactly when nagging starts.
  def journey_step_overdue?(step_data, days)
    interval = step_data[:reminder_interval_days].to_i
    interval.positive? && days > interval
  end

  # Sign-off (human) steps have no check, so their popup copy is shared; "why" prefers the step's
  # own description, which names who signs off and when (e.g. "The CFO signs off before…")
  JOURNEY_HUMAN_HOW = "The assigned approvers sign off from their email or from the workflow page.".freeze
  JOURNEY_HUMAN_WHY = "A named person accepts the work so far before the record moves on.".freeze
  JOURNEY_HUMAN_EFFECTS = "Records the approval and moves the journey on. If earlier work is undone later, sign-offs " \
                          "are reset and the approvers emailed. Investors are not emailed.".freeze

  # Everything the step popup (workflow_instances/_step_info) shows for one step:
  #   result  — the step's stored result (what the panel shows; never re-evaluated here)
  #   status  — "passed" / "current" / "error" / "not_yet" / "na"
  #   how/why/effects — the check's fixed copy (WorkflowChecks::Base), or the sign-off defaults
  #   notify  — [[icon, text], ...] built from the step's real settings, so it never promises an
  #             email the system doesn't send (WorkflowEvaluator#mails, WorkflowAutoReminderJob)
  def journey_step_info(instance, step)
    result = (instance.step_result(step[:position]) || {}).with_indifferent_access
    kind = step[:kind].to_s.presence || "human"
    check = WorkflowChecks::Registry.fetch(step[:check_key]) if step[:check_key].present? && WorkflowChecks::Registry.registered?(step[:check_key])
    steps = instance.snapshot_steps

    {
      name: step[:name], kind:, result:,
      status: result[:status].presence || "not_yet",
      how: check&.how || (JOURNEY_HUMAN_HOW if kind == "human"),
      why: check&.why || journey_step_first_sentence(step[:description]) || (JOURNEY_HUMAN_WHY if kind == "human"),
      effects: check&.effects || (JOURNEY_HUMAN_EFFECTS if kind == "human"),
      notify: journey_step_notify_lines(instance, step, kind, steps)
    }
  end

  private

  # A sign-off step's description opens with who signs off and when ("The CFO signs off before the
  # call is approved."); what follows is setup advice for admins, which doesn't belong in the popup
  def journey_step_first_sentence(text)
    text.to_s.split(/(?<=\.)\s+/).first.presence
  end

  # "Who's notified" for a step: at most three short lines — when it starts, if it stalls, when done
  def journey_step_notify_lines(instance, step, kind, steps)
    lines = []
    interval = step[:reminder_interval_days].to_i
    owner = WorkflowAutoReminderJob.owner_for(instance, step) unless kind == "human"

    # When it starts: approvers of a sign-off are emailed; a review step's owner is emailed
    case kind
    when "human"
      approvers = User.where(id: Array(step[:actor_ids])).map(&:full_name)
      if step[:notify_on_activation] && approvers.any?
        lines << ["ti-mail", "When it starts: #{approvers.to_sentence} #{approvers.one? ? 'is' : 'are'} emailed to sign off"]
      elsif approvers.empty?
        lines << ["ti-user-off", "No approvers yet: edit this step on the journey template to pick them"]
      end
    when "acknowledge"
      lines << ["ti-mail", "When it starts: #{owner.full_name} is emailed to review"] if step[:notify_on_activation] && owner
    end

    # If it stalls: sign-offs chase the approvers who haven't answered; other steps chase the owner
    if interval.positive?
      who = if kind == "human"
              "approvers who haven't signed off are"
            else
              (owner ? "#{owner.full_name} is" : nil)
            end
      lines << ["ti-clock", "If it stalls: #{who} reminded every #{pluralize(interval, 'day')}"] if who
    end
    lines << ["ti-user-off", "Nobody is reminded: set an owner on the journey template"] if kind != "human" && owner.nil?

    # When done: the next step starts, or the owner hears the journey is complete
    # (skipping steps that don't apply to this record — they never start)
    following = steps.find { |s| s[:position].to_i > step[:position].to_i && instance.step_result(s[:position])&.dig("status") != "na" }
    if following
      lines << ["ti-arrow-right", "When done: \"#{following[:name]}\" starts"]
    else
      last_owner = WorkflowAutoReminderJob.owner_for(instance, step)
      lines << ["ti-flag", "When done: #{last_owner ? last_owner.full_name : 'the owner'} is emailed that the journey is complete"]
    end
    lines
  end

  # The middle tooltip line: what state the step is in, with the pass time when there is one
  def journey_step_state_line(step)
    message = h(step[:message]) if step[:message].present?

    case step[:status].to_s
    # Done date on its own line, the step's message underneath
    when "passed" then [journey_passed_label(step), message].compact.join("<br>")
    when "na" then "Not applicable — #{message}"
    when "error" then "Could not be checked — #{message}"
    when "current" then "#{step[:regressed] ? 'Moved back' : 'In progress'} — #{message}"
    else "Not started"
    end
  end

  def journey_passed_label(step)
    return "Done" if step[:passed_at].blank?

    "Done #{l(Time.zone.parse(step[:passed_at]), format: :abbr_date_time)}"
  end
end
