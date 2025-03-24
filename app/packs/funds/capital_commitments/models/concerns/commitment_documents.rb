module CommitmentDocuments
  extend ActiveSupport::Concern

  def folder_path
    "#{fund.folder_path}/Commitments/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def document_list
    # fund.commitment_doc_list&.split(",")
    docs = fund.documents.templates.map(&:name)
    docs += fund.documents.templates.map { |d| ["#{d.name} Header", "#{d.name} Footer"] }.flatten
    docs += fund.commitment_doc_list.split(",").map(&:strip) if fund.commitment_doc_list.present?
    docs += ["Other"] if docs.present?
    docs.sort
  end

  def docs_for_investor
    documents.where(owner_tag: "Generated", approved: true).or(documents.where.not(owner_tag: "Generated")).or(documents.where(owner_tag: nil)).not_template
  end

  # Retrieves the templates to be used for rendering as SOA, FRA etc.
  def templates(owner_tag, name: nil, id: nil)
    fund_templates = fund.documents.templates.where(owner_tag:)
    fund_templates = fund_templates.where(name:) if name
    fund_templates = fund_templates.where(id:) if id
    fund_template_names = fund_templates.pluck(:name)
    # Try and get the template from the capital_commitment which override the fund templates
    commitment_templates = documents.templates.where(name: fund_template_names)

    if commitment_templates.present?
      template_names = commitment_templates.pluck(:name)
      # Get the fund templates that are not overridden by the commitment
      # If a name is specified and we found commitment_templates, then dont get any fund_templates
      fund_templates = name ? [] : fund.documents.where(owner_tag:).where.not(name: template_names)
    end

    commitment_templates + fund_templates
  end
end
