class UpdateSequence < Trailblazer::Operation
  step :update_sequence

  private

  def update_sequence(_ctx, params:, kanban_column:, **)
    kanban_column.sequence = params["new_position"]
    kanban_column.save!
    true
  end
end
