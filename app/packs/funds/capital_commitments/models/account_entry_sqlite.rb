class AccountEntrySqlite < ApplicationRecordSqlite
  self.table_name = 'account_entries'
  self.primary_key = :id
  attr_accessor :skip_cf_before_save

  include AccountEntryShared

  belongs_to :capital_commitment, optional: true, class_name: 'CapitalCommitmentSqlite'
  belongs_to :investor, optional: true, class_name: 'InvestorSqlite'
  belongs_to :parent, polymorphic: true, optional: true
  belongs_to :fund_formula, optional: true
  belongs_to :exchange_rate, class_name: 'ExchangeRateSqlite', optional: true

  scope :for_parent_account_entries, lambda {
    joins("INNER JOIN account_entries AS parent_account_entries ON account_entries.parent_id = parent_account_entries.id AND account_entries.parent_type in ('AccountEntrySqlite', 'AccountEntry')")
  }

  def to_s
    "#{name} #{I18n.l(reporting_date)}"
  end
end
