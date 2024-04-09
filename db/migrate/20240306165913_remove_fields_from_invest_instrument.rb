class RemoveFieldsFromInvestInstrument < ActiveRecord::Migration[7.1]
  def change
    if column_exists? :investment_instruments, :type_of_investee_company
      # remove_column :investment_instruments, :type_of_investee_company
    end
    if column_exists? :investment_instruments, :type_of_security
      # remove_column :investment_instruments, :type_of_security
    end
    if column_exists? :investment_instruments, :details_of_security
      # remove_column :investment_instruments, :details_of_security
    end
    if column_exists? :investment_instruments, :offshore_investment
      # remove_column :investment_instruments, :offshore_investment
    end
    if column_exists? :investment_instruments, :isin
      # remove_column :investment_instruments, :isin
    end
    if column_exists? :investment_instruments, :sebi_registration_number
      # remove_column :investment_instruments, :sebi_registration_number
    end
    if column_exists? :investment_instruments, :is_associate
      # remove_column :investment_instruments, :is_associate
    end
    if column_exists? :investment_instruments, :is_managed_or_sponsored_by_aif
      # remove_column :investment_instruments, :is_managed_or_sponsored_by_aif
    end
    if column_exists? :investment_instruments, :amount_invested_in_offshore
      # remove_column :investment_instruments, :amount_invested_in_offshore
    end
  end
end
