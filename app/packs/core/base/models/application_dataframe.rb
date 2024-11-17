class ApplicationDataframe
  def df(sql, params)
    begin
      # Read the database and create a dataframe
      df = Polars.read_database(sql)

      # Enhance the dataframe, in case additional cols need to be added for processing
      df = enhance_df(df)

      # Group the dataframe if group fields are present
      if params[:group_fields].present?
        agg_field = params[:agg_field]
        agg_type = params[:agg_type]
        # Group the DF based on the group fields and aggregate the field
        df = df.group_by(params[:group_fields]).agg(Polars.col(agg_field).send(agg_type))
      end
    rescue Exception => e
      # Log the error and notify the exception
      Rails.logger.debug e.backtrace
      ExceptionNotifier.notify_exception(e, data: { message: "Error in generating account entries DF" })
    end

    # Return the dataframe
    df
  end

  # This is called by the ApplicationDataframe class to enhance the dataframe, override this method in the subclass, to add additional columns
  def enhance_df(_df)
    raise "This method should be overridden in the subclass"
  end
end
