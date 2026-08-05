class DocGenJob < ApplicationJob
  include ActionView::Helpers::TextHelper

  queue_as :doc_gen
  sidekiq_options retry: 1

  # The Document records successfully created by the most recent #generate call.
  # Portfolio report gen needs this to combine all portfolio reports into one
  attr_reader :generated_documents

  # Returns all the templates from which documents will be generated
  def templates(_model = nil)
    []
  end

  # Returns all the models for which documents will be generated
  def models
    []
  end

  # Validates the model before generating the document
  def validate(model); end

  def signed_document_already_exists?(model, doc_name)
    signed_or_sent_for_esign = model.documents.signed.or(model.documents.sent_for_esign)
    # exists? issues SELECT 1 LIMIT 1; present? loaded every matching document row
    signed_or_sent_for_esign.exists?(["name like ?", "%#{doc_name}%"])
  end

  def approved_document_already_exists?(model, doc_name)
    # exists? issues SELECT 1 LIMIT 1; present? loaded every matching document row
    model.documents.approved.exists?(["name like ?", "%#{doc_name}%"])
  end

  def generate_doc_name(model, template, start_date, end_date)
    if start_date && end_date
      "#{template.name} #{start_date} to #{end_date} - #{model}"
    else
      "#{template.name} - #{model}"
    end
  end

  def valid_inputs
    @error_msg ||= []
    if templates.blank?
      send_notification("No templates found", @user_id, "danger")
      @error_msg << { msg: "No templates found" }
      false
    end
    if models.blank?
      send_notification("No records found", @user_id, "danger")
      @error_msg << { msg: "No records found" }
      false
    end

    true
  end

  # The specific Generator used for document generation
  def generator
    raise "Generator not specified"
  end

  def cleanup_previous_docs(model, template); end

  # The actual process of generating the document
  def generate(start_date, end_date, user_id, options: nil)
    @error_msg ||= []
    @generated_documents = []
    succeeded = 0
    failed = 0

    send_notification("Documentation generation started", user_id, "info")

    # Loop through each template and model and generate the documents
    models.each_with_index do |model, midx|
      templates_to_use = Array(templates(model))
      ActiveRecord::Associations::Preloader.new(records: templates_to_use, associations: %i[e_signatures stamp_papers]).call
      templates_to_use.each_with_index do |template, tidx|
        # Validate the model before generating the document
        valid, msg = validate(model)
        doc_name = generate_doc_name(model, template, Time.zone.parse(start_date.to_s).strftime("%d %B,%Y"), Time.zone.parse(end_date.to_s).strftime("%d %B,%Y"))
        signed_document_already_exists = signed_document_already_exists?(model, doc_name)
        approved_document_already_exists = approved_document_already_exists?(model, doc_name)

        if valid && !signed_document_already_exists && !approved_document_already_exists
          # Cleanup previously generated documents if required
          cleanup_previous_docs(model, template)
          # Generate the document
          gen = generator.new(model, template, start_date, end_date, user_id, options:)
          @generated_documents << gen.generated_document if gen.respond_to?(:generated_document) && gen.generated_document
          # Send notification if the document is generated successfully
          count = (midx * templates_to_use.length) + tidx + 1
          send_notification("#{count}: Generated #{template.name} for #{model}", user_id, "success")
          succeeded += 1
        else
          msg = "Signed document already exists for #{model} with template #{template.name}" if signed_document_already_exists
          msg = "Approved document already exists for  #{model} with template #{template.name}" if approved_document_already_exists
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

  def completed(succeeded, _failed, user_id)
    # Send email if there are any errors
    if @error_msg.present?
      @main_error = "#{generator} Document generation completed with #{@error_msg.length} errors."
      email_errors
      send_errors_notification("#{generator} Document generation completed with #{@error_msg.length} errors. Error email sent with details.", @error_msg, user_id, "danger")
    else
      msg = "#{generator} #{pluralize(succeeded, 'document')} generated successfully."
      logger.info msg
      send_notification(msg, user_id, "success")
    end
    @error_msg
  end
end
