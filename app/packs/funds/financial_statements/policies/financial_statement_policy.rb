class FinancialStatementPolicy < FinancialStatementBasePolicy
  # Generate / Regenerate / Lock change what is published: fund update access
  def regenerate?
    update?
  end

  def lock?
    update?
  end

  def setup?
    update?
  end
end
