# ② The inputs the entity's attached packs need, with ✓ / ✗ and the checks each missing input blocks (US-3).
# Monitoring cannot be turned on while a required input is missing (X15).
class ComplianceInputs
  Input = Struct.new(:key, :label, :type, :optional, :packs, :mapped, :missing_funds, keyword_init: true) do
    def missing?
      !optional && (type == "fund_figure" ? missing_funds.any? : !mapped)
    end
  end

  def self.for(entity)
    new(entity).inputs
  end

  def initialize(entity)
    @entity = entity
    @setup = ComplianceEntitySetup.for(entity)
  end

  def inputs
    by_key = {}
    FundCompliancePack.active.where(entity_id: @entity.id).includes(:fund, :compliance_pack, :compliance_pack_version).find_each do |fp|
      next if fp.compliance_pack_version.nil?

      used = used_inputs(fp)
      fp.compliance_pack_version.inputs.each do |inp|
        next unless used.include?(inp["key"])

        rec = by_key[inp["key"]] ||= Input.new(key: inp["key"], label: inp["label"].presence || inp["key"].humanize, type: inp["type"],
                                               optional: inp["optional"] == true, packs: [], mapped: mapped?(inp), missing_funds: [])
        rec.packs |= [fp.pack_name]
        rec.missing_funds |= [fp.fund.name] if inp["type"] == "fund_figure" && @setup.fund_figure(inp["key"], fp.fund).nil?
      end
    end
    by_key.values
  end

  # Labels of required inputs still missing: "Estimated expenses"
  def self.missing_labels(entity)
    self.for(entity).select(&:missing?).map { |i| i.label.upcase_first }
  end

  private

  # Inputs referenced by the checks that apply to this attachment's classification
  def used_inputs(fund_pack)
    v = fund_pack.compliance_pack_version
    checks = v.checks.select { |c| c["applies_to"].nil? || c["applies_to"] == "all" || Array(c["applies_to"]).include?(fund_pack.classification) }
    refs = checks.flat_map { |c| [c["figure"], c.dig("limit", "expr"), c["document_input"]] }
    measure_keys = expand(refs, v)
    input_refs = v.measures.select { |m| measure_keys.include?(m["key"]) }
                  .flat_map { |m| [m["input"]] + Array(m["filters"]).select { |f| f.first == "investor_group" }.map(&:last) }
    (input_refs + checks.pluck("document_input")).compact.uniq
  end

  def expand(refs, version)
    keys = []
    stack = refs.flatten.compact.grep(String)
    while (k = stack.pop)
      next if keys.include?(k)

      keys << k
      m = version.measures.detect { |x| x["key"] == k }
      stack.concat(Array(m&.dig("expr")).flatten.grep(String)) if m
    end
    keys
  end

  def mapped?(inp)
    case inp["type"]
    when "investor_group" then @setup.group_categories(inp["key"]).present?
    when "document" then @setup.document_mapping(inp["key"]).present?
    else true
    end
  end
end
