class ExcerciseNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "ExcerciseMailer", method: :email_method, format: :email_data

  # Add required params
  param :excercise_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      excercise_id: params[:excercise_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @excercise = Excercise.find(params[:excercise_id])
    params[:msg] || "Excercise: #{@excercise}"
  end

  def url
    excercise_path(id: params[:excercise_id])
  end
end
