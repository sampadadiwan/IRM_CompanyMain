# Overrides Devise's default mailer so subjects can be interpolated with
# per-entity branding (e.g. "Welcome to CapHive (Acme Capital)") instead of the static
# strings in devise.en.yml. Wired up via config.mailer in config/initializers/devise.rb.
class DeviseMailer < Devise::Mailer
  def confirmation_instructions(record, token, opts = {})
    opts[:subject] = "Welcome to #{branding_entity_name(record)}"
    super
  end

  private

  # Always brand with "CapHive", parenthesizing the specific entity name when we have one
  # to attribute the invite to. Falls back to bare "CapHive" if no entity name is resolvable.
  def branding_entity_name(record)
    name = stakeholder_entity_name(record) || (record.entity_name if record.respond_to?(:entity_name))
    name.present? ? "CapHive (#{name})" : "CapHive"
  end

  # Investors are usually invited by a fund granting them an InvestorAccess on the fund's
  # entity, rather than belonging to their own entity directly. In that case the fund (the
  # actual inviter) should be the name in the subject, not record.entity_name. We only do this
  # when the user has exactly one InvestorAccess across all entities -- if they have several,
  # there's no single fund to attribute the invite to, so we fall back to the default.
  def stakeholder_entity_name(record)
    return nil unless record.respond_to?(:curr_role_investor?) && record.curr_role_investor?

    accesses = InvestorAccess.where(user_id: record.id).limit(2).to_a
    accesses.first.entity_name if accesses.size == 1
  end
end
