class UserNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    UserMailer
  end

  def email_data(notification)
    data_hash = {
      filename: params[:filename],
      model_name: params[:model_name],
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      message: notification.message
    }
    data_hash[:document] = params[:document] if params[:document].present?
    data_hash
  end

  notification_methods do
    def message
      @message = params[:subject]
      @message
    end

    def email_delay
      @email_delay = params[:email_delay] || 30.seconds
      @email_delay
    end

    def url
      if %w[model_download].include? params[:email_method]
        if params[:document].present?
          document_path(params[:document], sub_domain: record.entity.sub_domain)
        else
          user_path(id: params[:user_id], sub_domain: record.entity.sub_domain)
        end
      end
    end
  end
end
