class CapitalCommitmentDf < ApplicationDataframe
  def df(capital_commitments, _current_user, params)
    # The account entries DF.
    sql = capital_commitments.joins(:investor_kyc, :fund, :investor).select("investor_kycs.*, capital_commitments.*, funds.*", "funds.name AS fund_name").to_sql
    # Create the dataframe and return it
    super(sql, params)
  end

  # This is called by the ApplicationDataframe class to enhance the dataframe
  def enhance_df(dataframe)
    # Create an amount column by dividing 'amount_cents' by 100 and rounding to 2 decimal places
    dataframe = dataframe.with_column((Polars.col("committed_amount_cents").cast(:f64) / 100).alias("committed_amount"))
    dataframe = dataframe.with_column((Polars.col("collected_amount_cents").cast(:f64) / 100).alias("collected_amount"))
    dataframe = dataframe.with_column((Polars.col("distribution_amount_cents").cast(:f64) / 100).alias("distribution_amount"))
    dataframe.with_column((Polars.col("call_amount_cents").cast(:f64) / 100).alias("call_amount"))
  end
end
