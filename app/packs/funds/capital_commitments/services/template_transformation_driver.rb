# AI Template Transformation Driver Class
# Usage in Rails Console:
# transformer = TemplateTransformationDriver.new
# transformer.run

class TemplateTransformationDriver
  def initialize(descriptive_doc_path = "lib/templates/descriptive_commitment_agreement.docx")
    @descriptive_doc = descriptive_doc_path
  end

  def run
    # 1. Setup Sample Context
    Rails.logger.debug "--- Setting up Sample Context ---"
    context = build_sample_context
    return unless context

    # 2. Check for file
    unless File.exist?(@descriptive_doc)
      Rails.logger.debug { "Descriptive document not found at #{@descriptive_doc}" }
      return
    end

    # 3. Initialize and run the Transformer
    Rails.logger.debug "--- Initializing TemplateTransformer ---"
    transformer = TemplateTransformer.new(@descriptive_doc, context)

    Rails.logger.debug "--- Running Transformation (Placeholder Extraction -> AI Mapping -> XML Replacement) ---"
    output_path = transformer.perform

    if output_path && File.exist?(output_path)
      Rails.logger.debug "SUCCESS!"
      Rails.logger.debug { "Sablon Template generated at: #{output_path}" }
      Rails.logger.debug "Mapping found by AI:"
      Rails.logger.debug transformer.mapping
      output_path
    else
      Rails.logger.debug "FAILED! Check logs for errors."
      nil
    end
  end

  private

  def build_sample_context
    capital_commitment = CapitalCommitment.last
    unless capital_commitment
      Rails.logger.debug "No CapitalCommitment found in DB. Please ensure test data exists."
      return nil
    end

    {
      date: Time.zone.today.strftime("%d %B %Y"),
      entity: capital_commitment.entity,
      fund: TemplateDecorator.decorate(capital_commitment.fund),
      capital_commitment: TemplateDecorator.decorate(capital_commitment),
      investor_kyc: TemplateDecorator.decorate(capital_commitment.investor_kyc),
      fund_unit_setting: TemplateDecorator.decorate(capital_commitment.fund_unit_setting)
    }
  end
end
