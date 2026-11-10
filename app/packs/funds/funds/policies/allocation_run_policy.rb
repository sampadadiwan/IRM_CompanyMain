class AllocationRunPolicy < FundBasePolicy
  def unlock?
    FundPolicy.new(user, record.fund).update?
  end

  def lock?
    FundPolicy.new(user, record.fund).update?
  end

  # Same people who may lock or unlock the fund's runs. Whether the run may be marked (it is
  # unfinished and no engine is running on the fund) is the model's rule: AllocationRun#mark_crashed!
  def mark_crashed?
    FundPolicy.new(user, record.fund).update?
  end

  def unlock_all?
    support?
  end
end
