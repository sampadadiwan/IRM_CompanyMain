class CommitmentAdjustmentSqlite < ApplicationRecordSqlite
  self.table_name = 'commitment_adjustments'
  self.primary_key = :id

  include CommitmentAdjustmentShared

  belongs_to :capital_commitment, class_name: 'CapitalCommitmentSqlite'
  belongs_to :owner, polymorphic: true, optional: true
end
