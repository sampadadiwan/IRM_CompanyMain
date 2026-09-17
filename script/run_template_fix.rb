# frozen_string_literal: true

# Runner script to execute TemplateFixAgent against a docx template.
#
# Usage:
#   bin/rails runner script/run_template_fix.rb [template_path] [issue_description] [model] [entity_id]
#
# Example:
#   bin/rails runner script/run_template_fix.rb public/sample_uploads/MessedUpDocTemplate.docx

template_path = ARGV[0] || "public/sample_uploads/MessedUpDocTemplate.docx"
issue_desc = ARGV[1] || <<~DESC.strip
  These are the issues we see when we generate a commitment agreement with this template:
  1. indenting of sub points under 2.2 has changed. also under 2.3
  2. Numbering and indenting of 5.3 has changed
  3. spacing and indenting inside 4.2.6 has changed
DESC
model = ARGV[2] || "gemini-3.7-flash"
entity_id = ARGV[3]

full_template_path = File.expand_path(template_path, Rails.root)
unless File.exist?(full_template_path)
  puts "Error: Template file not found at #{full_template_path}"
  exit 1
end

# Find an entity with configured API keys
entity = if entity_id.present?
           Entity.find(entity_id)
         else
           EntitySetting.where.not(gemini_api_key: [nil, ""]).first&.entity || Entity.first
         end

unless entity
  puts "Error: No entity found"
  exit 1
end

user = User.where(entity_id: entity.id).first || User.first

puts "========================================================================"
puts " RUNNING TEMPLATE FIX AGENT"
puts "========================================================================"
puts "Entity: #{entity.name} (ID: #{entity.id})"
puts "User: #{user&.email} (ID: #{user&.id})"
puts "Template file: #{template_path}"
puts "Model: #{model}"
puts "Issue Description:"
puts issue_desc.lines.map { |l| "  #{l}" }.join
puts "------------------------------------------------------------------------"

Chewy.strategy(:atomic) do
  # Find or create template document
  doc_name = File.basename(template_path, ".*")
  fund = entity.funds.first || entity.funds.create!(name: "#{entity.name} Fund")
  folder = fund.document_folder || entity.root_folder

  template_doc = Document.find_or_initialize_by(
    name: doc_name,
    entity: entity,
    owner: fund
  )
  template_doc.folder = folder
  template_doc.user = user
  template_doc.owner_tag = "Commitment Template"
  template_doc.template = true
  template_doc.file = File.open(full_template_path, "rb")
  template_doc.save!

  puts "Template Document ID: #{template_doc.id} (name: #{template_doc.name})"

  # Find or provision TemplateFixAgent
  support_agent = SupportAgent.find_or_create_by!(entity_id: entity.id, agent_type: "TemplateFixAgent") do |sa|
    sa.name = "Template Fix Agent"
    sa.category = "Ops"
    sa.llm_model = model
    sa.enabled = true
  end

  # Initialize report with steps
  report = TemplateFixAgent.new.initialize_report_with_steps(
    {},
    model: template_doc,
    support_agent: support_agent,
    user_id: user&.id
  )

  puts "Support Agent Report ID: #{report&.id}"
  puts "Starting Agent fix loop..."

  # Run the fix
  result = TemplateFixAgent.call(
    support_agent_id: support_agent.id,
    document: template_doc,
    issue_description: issue_desc,
    llm_model: model,
    support_agent: support_agent,
    support_agent_report: report
  )

  report&.reload

  puts "\n========================================================================"
  puts " AGENT RUN RESULTS"
  puts "========================================================================"
  puts "Success: #{result.success?}"
  puts "Report Status: #{report&.final_status}"

  if report&.json_fields.present?
    puts "\nFix Summary:"
    puts report.json_fields["fix_summary"]

    if report.json_fields["changes"].present?
      puts "\nChanges Made (#{report.json_fields['changes'].size}):"
      report.json_fields["changes"].each { |c| puts "  • #{c}" }
    end

    if report.json_fields["result_document_id"].present?
      draft = Document.find_by(id: report.json_fields["result_document_id"])
      if draft
        puts "\nDraft Document Created:"
        puts "  ID: #{draft.id}"
        puts "  Name: #{draft.name}"

        out_dir = Rails.root.join("tmp", "template_fix_output")
        FileUtils.mkdir_p(out_dir)
        out_docx = out_dir.join("#{draft.name.parameterize}.docx")
        draft.file.download { |f| FileUtils.cp(f.path, out_docx) }
        puts "  Saved DOCX to: #{out_docx}"

        # Generate PDF preview
        out_pdf = out_dir.join("#{draft.name.parameterize}.pdf")
        Open3.capture3("libreoffice", "--headless", "--convert-to", "pdf", "--outdir", out_dir.to_s, out_docx.to_s)
        puts "  Saved PDF to: #{out_pdf}"
      end
    end

    if report.json_fields["render_error"].present?
      puts "\nRender Error: #{report.json_fields['render_error']}"
    end
  end
  puts "========================================================================"
end
