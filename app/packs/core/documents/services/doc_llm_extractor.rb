class DocLlmExtractor < DocLlmBase
  INSTRUCTIONS = "You're a helpful Investment Analyst with an eye for numbers. Please look at the document carefully, and extract all financial information from it in the form of json. As an example {'Jan 2024': {revenue: 100000, EBITDA: 20000, ...and all other extracted info}}, the keys in the json are only examples, you must put all financial information in the json, not just those specified in the example. Do NOT leave out any information. Do not add any ```json to the output".freeze

  step :init
  step :convert_file_to_image
  step :run_checks_with_llm
  step :save_check_results
  step :cleanup
  left :handle_errors

  # Run the checks with the llm
  def run_checks_with_llm(ctx, open_ai_client:, **)
    messages = [
      { type: "text", text: INSTRUCTIONS },
      { type: "image_url",
        image_url: {
          url: ImageService.encode_image(ctx[:image_path])
        } }
    ]

    # Run the checks with the llm
    response = open_ai_client.chat(
      parameters: {
        model: "gpt-4o", # Required.
        response_format: { type: "json_object" },
        messages: [{ role: "user", content: messages }] # Required.
      }
    )

    # Get the results from the response
    ctx[:extracted_info] = response.dig("choices", 0, "message", "content")
    Rails.logger.debug ctx[:extracted_info]
    true
  end

  def save_check_results(_ctx, **)
    true
  end
end
