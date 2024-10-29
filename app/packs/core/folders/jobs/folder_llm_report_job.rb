class FolderLlmReportJob < ApplicationJob
  queue_as :low

  def perform(folder_id, user_id)
    Chewy.strategy(:sidekiq) do
      folder = Folder.find(folder_id)
      # Find all the files in this folder and add it to the signed_urls
      doc_urls = []
      template_url = nil
      folder.documents.each do |doc|
        if doc.name == "Report Template"
          template_url = doc.file.url
        elsif doc.pdf?
          doc_urls << doc.file.url
        else
          Rails.logger.debug { "Skipping #{doc.name} as it is not a pdf or template" }
        end
      end

      # Make a rest call like so
      # curl -X POST "http://127.0.0.1:8000/generate-report/" -H "Content-Type: application/json" -d '{
      # "file_urls": ["https://example.com/file1.pdf", "https://example.com/file2.pdf"],
      # "template_html_url": "https://example.com/template.html",
      # "callback_url": "https://your-callback-endpoint.com/callback"
      # }'

      response = HTTParty.post(
        "http://127.0.0.1:8000/generate-report/",
        headers: {
          'Content-Type' => 'application/json'
        },
        body: {
          api_key: Rails.application.credentials["OPENAI_API_KEY"],
          file_urls: doc_urls,
          template_html_url: template_url
        }.to_json
      )

      # Now sleep for 2 mins and check the folder_path for the output_report.html file, and do this in a loop
      Rails.logger.debug response
      folder_path = response["folder_path"]
      tries = 0
      while tries < 8
        tries += 1
        msg = "Checking #{tries} for output_report.html file in #{folder_path}"
        Rails.logger.debug msg
        send_notification("Report generation in progress...", user_id, :info)
        sleep(30)
        break if File.exist?("#{folder_path}/output_report.html")
      end

      # Now download the output_report.html file and save it as a document in the folder
      if File.exist?("#{folder_path}/output_report.html")
        msg = "Found output_report.html file in #{folder_path}"
        Rails.logger.debug msg
        send_notification("Sucessfully generated report. Please refresh the screen.", user_id, :success)
        folder.documents.create(file: File.open("#{folder_path}/output_report.html"), name: "Output Report", entity_id: folder.entity_id, user_id:, orignal: true)

        folder.documents.create(file: File.open("#{folder_path}/output_report.html.docx"), name: "Output Report Doc", entity_id: folder.entity_id, user_id:, orignal: true)
      else
        msg = "Failed to generate report"
        send_notification(msg, user_id, :danger)
      end
    end
  end
end
