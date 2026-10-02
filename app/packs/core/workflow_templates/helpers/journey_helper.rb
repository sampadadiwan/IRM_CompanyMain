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

  # Tooltip body for one step: its name, what state it is in, and what kind of step it is.
  #
  # Returns a PLAIN String (never html_safe) whose own markup is literal `<b>`/`<br>` but whose
  # step-supplied text is already escaped. The view prints it into data-bs-title, so ERB escapes
  # the whole thing once: the browser then hands Bootstrap (data-bs-html="true") our tags as
  # markup and anything that came from the step as text. Marking it html_safe here would let a
  # step name or message inject HTML into the tooltip.
  def journey_step_tooltip(step)
    [
      "<b>#{h(step[:name])}</b>",
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

  private

  # The middle tooltip line: what state the step is in, with the pass time when there is one
  def journey_step_state_line(step)
    message = h(step[:message]) if step[:message].present?

    case step[:status].to_s
    when "passed" then [journey_passed_label(step), message].compact.join(" — ")
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
