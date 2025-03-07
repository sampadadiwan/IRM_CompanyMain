# This job is used to generate a report for a folder. It will take all the pdf files in the folder and generate a report using the template.html file in the folder.
# It calls out to a python service which is in the xirr package. The service will generate a report and save it in the folder_path. The job will then check the folder_path for the output_report.html file and download it and save it as a document in the folder.
class FolderLlmReportJob < LlmReportJob
  queue_as :low

  def template_to_output_file_name(output_file_name_prefix, template_name)
    name = "#{template_name.parameterize(separator: '_').gsub('_template', '')}.html"
    output_file_name_prefix.present? ? "#{output_file_name_prefix}_#{name}" : name
  end

  def file_name_from_output_file_name(output_file_name)
    output_file_name.gsub(".html", "").gsub("html", "").humanize.titleize
  end

  def perform(folder_id, user_id, report_template_name: "Report Template", kpis: nil, apis: nil, notes: nil, output_folder_id: nil, output_file_name_prefix: nil)
    Chewy.strategy(:sidekiq) do
      folder = Folder.find(folder_id)
      output_folder = output_folder_id.present? ? Folder.find(output_folder_id) : folder
      # Find all the files in this folder and add it to the signed_urls
      doc_urls, template_url = get_documents(folder, report_template_name)

      if template_url.nil? || doc_urls.empty?
        # Send a notification to the user
        msg = "Failed to generate report. Template not found." if template_url.nil?
        msg = "Failed to generate report. No pdf files found." if doc_urls.empty?
        send_notification(msg, user_id, :danger)
      else
        # Now call the generate_report API
        output_file_name = template_to_output_file_name(output_file_name_prefix, report_template_name)
        name = file_name_from_output_file_name(output_file_name)

        # Check if the report has already been generated
        if output_folder.documents.exists?(name: name)
          msg = "Report already generated for #{output_folder.name}. Skipping report generation."
          Rails.logger.debug { msg }
          send_notification(msg, user_id, :info)
          return
        end

        # We need to send the kpis and apis as json data to the report server
        additional_data = {}
        additional_data[:kpis] = JSON.parse(kpis) if kpis.present?
        additional_data[:portfolio_investments] = JSON.parse(apis) if apis.present?
        additional_data[:notes] = JSON.parse(notes) if notes.present?

        response = generate_report(doc_urls, template_url, output_file_name, additional_data:)
        if response.code == 200
          folder_path = response["folder_path"]
          # Check for the output_report.html file in the folder_path
          check_for_output_report(folder_path, output_file_name)
          # Now download the output_report.html file and save it as a document in the folder
          upload_file(output_folder, folder_path, user_id, output_file_name)
        else
          msg = "Failed to generate report, report server not reachable. Please try again."
          send_notification(msg, user_id, :danger)
        end
      end
    end
  end

  private

  def get_documents(folder, report_template_name)
    doc_urls = []
    template_url = nil
    folder.documents.each do |doc|
      if doc.name == report_template_name
        # Report template specific to this folder
        template_url = doc.file.url
      elsif doc.pdf?
        doc_urls << doc.file.url
      else
        Rails.logger.debug { "Skipping #{doc.name} as it is not a pdf or template" }
      end
    end

    if template_url.nil?
      # Get the template url from Funds/
      folder.entity.folders.where(name: "Portfolio Report Templates").first&.documents&.each do |doc|
        next unless doc.name == report_template_name

        Rails.logger.debug { "Found #{doc.name} in Portfolio Report Templates folder" }
        template_url = doc.file.url
        break
      end
    end

    [doc_urls, template_url]
  end

  # rubocop:disable Rails/SkipsModelValidations
  def upload_file(folder, folder_path, user_id, output_file_name)
    # Now download the output_report.html file and save it as a document in the folder
    if File.exist?("#{folder_path}/#{output_file_name}")
      msg = "Found #{output_file_name} file in #{folder_path}"
      Rails.logger.debug msg
      file_name = file_name_from_output_file_name(output_file_name)
      tries = 0
      while tries < 3
        begin
          # Save the output_report.html file as a document in the folder
          doc_html = folder.documents.create!(file: File.open("#{folder_path}/#{output_file_name}"), name: file_name, entity_id: folder.entity_id, user_id:, orignal: true, download: true)
          # Save the output_report.html.docx file as a document in the folder
          doc_word = folder.documents.create!(file: File.open("#{folder_path}/#{output_file_name}.docx"), name: "#{file_name} Doc", entity_id: folder.entity_id, user_id:, orignal: true, download: true)
          # Update the orignal flag for both the documents
          Document.where(id: [doc_html.id, doc_word.id]).update_all(orignal: true)
          # Send a notification to the user
          send_notification("Sucessfully generated report in folder #{folder.name} for #{folder.owner.class.name}, #{folder.owner}. Please refresh the screen.", user_id, :success)
          # Break out of the loop, as we are done
          break
        rescue StandardError => e
          Rails.logger.error e.backtrace.join("\n")
          msg = "Failed to save #{output_file_name} file as a document in the folder"
          Rails.logger.error { "#{msg}: #{e.message}" }
          send_notification(msg, user_id, :danger) if tries == 2
          sleep(5)
        end
        # Sometimes we get an error while saving the document, so we will retry 3 times
        tries += 1
      end

      # Now delete the folder_path
      Rails.logger.debug { "Deleting folder_path: #{folder_path}" }
      FileUtils.rm_rf(folder_path)
    else
      msg = "Failed to generate report"
      send_notification(msg, user_id, :danger)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations
end
