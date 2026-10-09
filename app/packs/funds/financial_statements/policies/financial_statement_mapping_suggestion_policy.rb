class FinancialStatementMappingSuggestionPolicy < FinancialStatementBasePolicy
  def approve?
    update?
  end

  def discard?
    update?
  end

  def retry_draft?
    update?
  end

  def move?
    update?
  end

  def flip?
    update?
  end
end
