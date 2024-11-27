class AllocationRunPolicy < FundBasePolicy
  def unlock?
    FundPolicy.new(user, record.fund).update?
  end

  def lock?
    FundPolicy.new(user, record.fund).update?
  end
end
