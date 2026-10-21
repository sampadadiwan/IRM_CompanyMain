# The start and end dates a user submits to generate an Investor Statement for a capital
# commitment. Not persisted: it exists so the validation rule engine can check those dates
# (investor_statement_date_out_of_range) before any statement job is enqueued.
#
#   request = InvestorStatementRequest.new(entity_id: commitment.entity_id, start_date:, end_date:)
#   ValidationRuleEvaluator.call(record: request, entity: request.entity)
class InvestorStatementRequest
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :entity_id, :integer
  # Unparseable strings cast to nil, which the date rule skips
  attribute :start_date, :date
  attribute :end_date, :date

  def entity
    @entity ||= Entity.find(entity_id)
  end
end
