# frozen_string_literal: true

# Admin alerts for power changes (OWASP review 2026-11 M11, design card ⑦, D8). Called by SecurityEventWriteJob for
# a freshly written event only, so a retried write never alerts twice (E33).
#
# Alerts (email + bell, to every active company admin of the event's firm, including whoever made the change):
#   role.granted / role.revoked    only for company_admin and approver (H32), and not when the person holds the
#                                  support or investor_advisor role — a support switch or an advisor persona switch
#                                  re-grants roles on every switch, and support.firm_switched already tells the admins
#                                  (E42). Employee and investor grants alert nobody (E41).
#   support_access.enabled/disabled  a user's "Enable support" switch (H18); the system-wide switch-off has no firm
#   support.signed_in_as           CapHive support signed in as one of the firm's users (H33) — BELL ONLY
#   support.firm_switched          CapHive support switched into the firm (E42) — BELL ONLY
#                                  Support visits are announced in the bell only, never by email — user decision
#                                  2026-11-09. Every other alert above goes by email and bell.
# No firm, or no active admin, means no alert and no error (X12). Sign-in failures never alert here — M12's Grafana
# alert counts them.
class SecurityEventAlert
  # The roles whose change is worth an email
  POWER_ROLES = %w[company_admin approver].freeze
  # Roles whose holders have roles re-granted by a switch; their grants are not news
  SWITCHING_ROLES = %i[support investor_advisor].freeze
  ALWAYS = %w[support_access.enabled support_access.disabled support.signed_in_as support.firm_switched].freeze
  # C19 / H33 / E42 — support sign-ins and firm switches are announced in the bell only, never by email — user
  # decision 2026-11-09 ("no emails on sign in by support, other events can generate email", then the same for
  # firm switches). SecurityEventNotifier skips its email for these kinds.
  BELL_ONLY = %w[support.signed_in_as support.firm_switched].freeze

  class << self
    # @param event [SecurityEvent] a freshly written event
    def deliver(event)
      return unless alert?(event)

      # Active company admins of the firm, loaded once (a handful of people)
      people = recipients(event).to_a
      return if people.empty?

      SecurityEventNotifier.with(record: event, entity_id: event.entity_id).deliver(people)
    end

    # @return [Boolean]
    def alert?(event)
      return false if event.entity_id.nil?
      return true if ALWAYS.include?(event.kind)
      return false unless %w[role.granted role.revoked].include?(event.kind)

      # D8 — only power roles, and not the role swaps of a support / advisor switch
      POWER_ROLES.include?(event.details&.dig("role").to_s) && !switching_user?(event.user)
    end

    # H33 — true when the alert goes to the bell only (no email)
    # @return [Boolean]
    def bell_only?(event)
      BELL_ONLY.include?(event&.kind)
    end

    # The firm's active company admins — the actor included (a lone admin's self-grant still lands in an inbox) —
    # but never a CapHive support user switched into the firm (they hold company_admin there for the visit)
    # @return [ActiveRecord::Relation]
    def recipients(event)
      User.company_admins.active.where(entity_id: event.entity_id)
          .where.not(id: User.support_users.select(:id)).distinct
    end

    # The sentence the email subject, the bell and the email's first line share
    # @return [String]
    def headline(event)
      name = event.user&.full_name || "a user"
      role = event.details&.dig("role").to_s.humanize
      support = event.actor&.full_name || "CapHive support"
      case event.kind
      when "role.granted" then "#{role} role given to #{name}"
      when "role.revoked" then "#{role} role removed from #{name}"
      when "support_access.enabled" then "CapHive support access switched on for #{name}"
      when "support_access.disabled" then "CapHive support access switched off for #{name}"
      when "support.signed_in_as" then "CapHive support (#{support}) signed in as #{name}"
      when "support.firm_switched" then "CapHive support (#{event.user&.full_name || support}) switched into #{event.entity&.name}"
      else event.label
      end
    end

    private

    def switching_user?(user)
      # One query for both roles
      user.present? && user.roles.exists?(name: SWITCHING_ROLES.map(&:to_s))
    end
  end
end
