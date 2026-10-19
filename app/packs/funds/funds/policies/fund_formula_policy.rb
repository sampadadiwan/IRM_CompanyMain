class FundFormulaPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  # Only support can create / update formulas
  def create?
    support? || Rails.env.development?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  # E: the fields this user may send. Only support may send the fields that run as code or decide how code
  # runs: formula (eval-ed), meta_data (its scope key is called with .send, its where key goes into SQL),
  # rule_type (how the formula is applied) and is_template. Everyone else may edit the rest.
  def permitted_attributes
    fields = %i[fund_id name description sequence entity_id enabled entry_type roll_up rule_for generate_ytd_qtly
                add_to_commitment_cache explain]
    fields += if user.support? || Rails.env.local?
                %i[rule_type formula meta_data is_template]
              else
                %i[ai_generated]
              end
    fields + [{ tag_list: [] }]
  end

  def enable_formulas?
    update?
  end

  def edit?
    update?
  end

  def generate_ai_description?
    update?
  end

  def generate_ai_descriptions?
    user.enable_funds || support?
  end

  def dependencies?
    index?
  end

  def generate_formula?
    create?
  end

  def fetch_templates?
    support?
  end

  def destroy?
    update?
  end
end
