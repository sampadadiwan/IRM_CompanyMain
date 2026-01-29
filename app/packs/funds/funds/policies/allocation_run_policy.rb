class AllocationRunPolicy < FundBasePolicy
  def unlock?
    FundPolicy.new(user, record.fund).update?
  end

  def lock?
    FundPolicy.new(user, record.fund).update?
  end

  def unlock_all?
    support?
  end
end
