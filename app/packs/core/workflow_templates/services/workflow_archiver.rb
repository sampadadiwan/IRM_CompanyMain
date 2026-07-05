class WorkflowArchiver < Trailblazer::Operation
  # Archives a stalled or superseded instance, which also unblocks template removal.
  step :check_active
  step :archive

  def check_active(ctx, instance:, **)
    return true if instance.instance_active?

    ctx[:errors] = "Only active instances can be archived."
    false
  end

  def archive(_ctx, instance:, **)
    instance.update!(status: :archived)
  end
end
