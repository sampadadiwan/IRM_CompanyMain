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
    # Offering the exact label the extraction agent watches for is what lets an
    # upload auto-trigger obligation extraction — a hand-typed name never matches.
    docs << side_letter_document_label if side_letter_document_label
    docs += ["Other"] if docs.present?
    docs.uniq.sort
  end

  # The side letter document label for this tenant, or nil when the Side Letter
  # Obligation agent is off. The flag is a cheap bitmask read, so the agent row
  # is only fetched for tenants actually running the feature.
  def side_letter_document_label
    return nil unless entity&.support_agents&.set?(:side_letter_obligation_agent)

    agent = SupportAgent.where(entity_id: entity_id, agent_type: "SideLetterObligationAgent").last
    SideLetterObligationAgent.doc_label(agent)
  end

  def docs_for_investor
    documents.where(owner_tag: "Generated", approved: true).or(documents.where.not(owner_tag: "Generated")).or(documents.where(owner_tag: nil)).not_template
  end

  # Retrieves the templates to be used for rendering as Investor Statement, FRA etc.
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

    # Legacy data can hold two live templates with the same owner_tag AND name on one owner
    # (a revised template uploaded without deleting the old one; Document now validates
    # against this, but rows created before that validation still exist). Every DocGenJob
    # subclass keys its "delete the previous generated doc" step on template.name, so feeding
    # it two same-named templates makes it generate a notice, delete it, and generate it again
    # — which the investor sees as a document link that goes "access denied" seconds later.
    # Collapse to one template per name, preferring the newest upload (highest id): that's
    # the one the user most recently intended to use, and it's stable across runs.
    dedupe_templates_by_name(commitment_templates + fund_templates)
  end

  private

  # Keeps one Document per name, the most recently created (highest id). Commitment-level
  # overrides are listed before fund-level ones by the caller, and the two sets never share
  # a name (fund templates overridden by the commitment are excluded above), so the
  # collapse only ever removes true duplicates within the same owner. Order of first
  # appearance is preserved so job notification numbering stays deterministic.
  def dedupe_templates_by_name(templates)
    templates.group_by(&:name).values.map { |same_name| same_name.max_by(&:id) }
  end
end
