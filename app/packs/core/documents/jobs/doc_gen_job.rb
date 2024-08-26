class DocGenJob < ApplicationJob
  include ActionView::Helpers::TextHelper

  queue_as :doc_gen
  sidekiq_options retry: 1

  # Returns all the templates from which documents will be generated
  def templates(model = nil); end

  # Returns all the models for which documents will be generated
  def models; end

  # Validates the model before generating the document
  def validate(model); end

  def valid_inputs
    if templates.blank?
      send_notification("No templates found", @user_id, "danger")
      false
    end
    if models.blank?
      send_notification("No records found", @user_id, "danger")
      false
    end

    true
  end

  # The specific Generator used for document generation
  def generator; end

  def cleanup_previous_docs(model, template); end

  # The actual process of generating the document
  def generate(start_date, end_date, user_id)
    @error_msg = []
    succeeded = 0
    failed = 0

    send_notification("Documentation generation started", user_id, "info")

    # Loop through each template and model and generate the documents
    models.each do |model|
      templates(model).each do |template|
        # Validate the model before generating the document
        valid, msg = validate(model)
        if valid
          # Cleanup previously generated documents if required
          cleanup_previous_docs(model, template)
          # Generate the document
          generator.new(model, template, start_date, end_date, user_id)
          # Send notification if the document is generated successfully
          send_notification("Generated #{template.name} for #{model}", user_id, "success")
          succeeded += 1
        else
          # Send notification if the model is not valid
          send_notification(msg, user_id, "danger")
          @error_msg << { msg:, model: }
          failed += 1
        end
      rescue Exception => e
        Rails.logger.debug e.backtrace
        # Send notification if there is an error generating the document
        msg = "Error generating #{template.name} for #{model} #{e.message}"
        send_notification(msg, user_id, "danger")
        @error_msg << { msg:, model: }
      end

      logger.debug "DocGenJob: succeeded #{succeeded}, failed #{failed}"
    end

    # Send notification and cleanup
    completed(succeeded, failed, user_id)
  end

  def completed(succeeded, failed, user_id)
    # Send email if there are any errors
    if @error_msg.present?
      email_errors
    else
      msg = "#{pluralize(succeeded, 'document')} generated successfully."
      logger.info msg
      send_notification(msg, user_id, "success")
    end
    @error_msg
  end

  # email errors to the user
  def email_errors
    error_msg = @error_msg
    user_id = @user_id

    if error_msg.present?
      msg = "Document generation completed with #{error_msg.length} errors. Errors will be sent via email"
      logger.info msg
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg:).doc_gen_errors.deliver_now
    end
  end
end
