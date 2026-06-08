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

  # insert_all bypasses AR callbacks, so we validate here before any batch write reaches SQLite.
  # MySQL cannot represent NaN/Infinity in numeric columns (it parses "NaN" as a column name),
  # so catching it here — with formula/commitment context — is far more actionable than the
  # cryptic "Unknown column 'NaN' in 'field list'" raised during migration to primary DB.
  FINITE_CHECKED_COLUMNS = %w[amount_cents folio_amount_cents].freeze

  def self.insert_all(attributes, **kwargs)
    Array(attributes).each_with_index do |attrs, idx|
      FINITE_CHECKED_COLUMNS.each do |col|
        value = attrs[col] || attrs[col.to_sym]
        next unless value.respond_to?(:finite?) && !value.finite?

        kind = value.nan? ? "NaN" : (value.positive? ? "Infinity" : "-Infinity")
        context = "fund_formula_id=#{attrs['fund_formula_id']}, " \
                  "capital_commitment_id=#{attrs['capital_commitment_id']}, " \
                  "name=#{attrs['name']}"
        raise ZeroDivisionError,
              "#{kind} in '#{col}' (row #{idx}) — likely divide-by-zero in formula. #{context}"
      end
    end
    super
  end

  def to_s
    "#{name} #{I18n.l(reporting_date)}"
  end
end
