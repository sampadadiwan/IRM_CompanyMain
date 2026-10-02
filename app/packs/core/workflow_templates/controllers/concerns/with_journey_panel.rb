# The journey panel on a record's page, shared by every type that declares has_journey (capital
# calls, capital distributions). The controller's show evaluates the journey, and its journey action
# renders just the panel for the frame a real-time update inserts (Workflowable#broadcast_journey_change).
#
#   def show
#     @journey = evaluate_journey(@capital_call)
#   end
#
#   def journey
#     render_journey_panel(@capital_call)
#   end
#
# GET requests read from the replica, so the evaluation (which may record history) runs on the
# writing connection; the page then uses the in-memory results rather than a replica that may lag.
# Worked examples H3, J2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
# Worked examples H3, E16, E17 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WithJourneyPanel
  extend ActiveSupport::Concern

  private

  # The record's evaluated journey (WorkflowEvaluator results), or nil when it has none
  def evaluate_journey(record)
    results = ActiveRecord::Base.connected_to(role: :writing) do
      WorkflowEvaluator.for(record, cause: :progress)&.[](:results)
    end
    # The memoized instance predates the evaluation that just ran
    record.forget_current_workflow_instance!
    results
  end

  # Just the panel (<plural>/_journey). By now nothing has changed, so evaluating again here never
  # triggers another broadcast.
  def render_journey_panel(record)
    render partial: "#{record.workflowable_type_name.underscore.pluralize}/journey",
           locals: { record:, journey: evaluate_journey(record), instance: nil }
  end
end
