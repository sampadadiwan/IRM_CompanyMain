module AccountEntryAllocation
  # Raised by a pre/post-run check to report a problem without stopping the allocation run.
  # Carries the same summary and rows as CheckFailed; RunChecks tells the two apart by class.
  class CheckWarning < CheckFailed
  end
end
