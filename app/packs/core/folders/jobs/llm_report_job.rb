class LlmReportJob < ApplicationJob
  queue_as :low

  def generate_report(doc_urls, template_url, output_file_name, additional_data: nil)
    # This is part of the xirr_py package
    # https://github.com/ausangshukla/xirr_py
    response = HTTParty.post(
      "http://localhost:8000/generate-report/",
      headers: {
        'Content-Type' => 'application/json'
      },
      body: {
        openai_api_key: Rails.application.credentials["OPENAI_API_KEY"],
        anthropic_api_key: Rails.application.credentials["ANTHROPIC_API_KEY"],
        file_urls: doc_urls,
        template_html_url: template_url,
        additional_data: additional_data&.to_json,
        output_file_name:
      }.to_json
    )

    Rails.logger.debug response
    response
  end

  def check_for_output_report(folder_path, output_file_name)
    tries = 0
    # Now sleep for 2 mins and check the folder_path for the output_report.html file, and do this in a loop
    while tries < 8
      tries += 1
      msg = "Checking #{tries} for #{output_file_name} file in #{folder_path}"
      Rails.logger.debug msg
      sleep(30)
      break if File.exist?("#{folder_path}/#{output_file_name}")
    end
  end
end
