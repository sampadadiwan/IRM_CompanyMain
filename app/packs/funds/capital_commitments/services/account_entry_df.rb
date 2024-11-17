class AccountEntryDf < ApplicationDataframe
  def df(account_entries, _current_user, params)
    # The account entries DF.
    sql = account_entries.joins(:capital_commitment, :fund).select("account_entries.*, capital_commitments.*, funds.*", "funds.name AS fund_name", "account_entries.name as account_entry_name").to_sql
    # Create the dataframe and return it
    super(sql, params)
  end

  # This is called by the ApplicationDataframe class to enhance the dataframe
  def enhance_df(dataframe)
    # Create an amount column by dividing 'amount_cents' by 100 and rounding to 2 decimal places
    dataframe.with_column((Polars.col("amount_cents").cast(:f64) / 100).alias("amount"))
  end
end
