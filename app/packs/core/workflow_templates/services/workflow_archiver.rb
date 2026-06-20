class WorkflowArchiver
  # Archives a stalled or superseded instance, which also unblocks template removal.
  def self.archive(instance)
    raise ArgumentError, "Only active instances can be archived." unless instance.instance_active?

    instance.update!(status: :archived)
  end
end
