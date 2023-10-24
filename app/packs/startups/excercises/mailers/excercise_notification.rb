class ExcerciseNotification < BaseNotification
  # Add required params
  param :excercise
  param :email_method

  def mailer_name
    ExcerciseMailer
  end

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      excercise_id: params[:excercise].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @excercise = params[:excercise]
    params[:msg] || "Excercise: #{@excercise}"
  end

  def url
    excercise_path(id: params[:excercise].id)
  end
end
