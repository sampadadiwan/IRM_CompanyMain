# H6 (OWASP review 2026-11) — document template merge fields cannot leave the record's own firm.
#
# Sablon resolves a merge field such as «=capital_commitment.investor.investor_name» by calling each segment with
# public_send (sablon 0.4.3, Sablon::Expression::LookupOrMethodCall#evaluate). Associations are returned
# undecorated, so a template uploaded by a GP user could hop to the class or drop a relation's scope:
#   «capital_commitment.investor.class.all:each(i)»«=i.PAN»«capital_commitment.investor.class.all:endEach»
#   «=capital_commitment.account_entries.unscoped.count»
# and put every firm's investors (or a whole-table load) into a generated document. Writes were already refused
# while rendering (DocumentGeneratorBase#render_read_only, M27); reads were not.
#
# The rule added here, on top of Sablon's own:
#   - never call a method on a class or module (whatever it is named)
#   - never take a hop in SafeAttributePath::CLASS_HOP_NAMES (class, klass, unscoped, default_scoped, connection, …)
# Everything else resolves exactly as before, including relation readers such as `.all`, `.count`, `.first`.
#
# A refused hop renders as blank and is logged (it does not fail the document), so a template that relied on one
# of these names keeps generating; nothing legitimate needs them.
module SablonSafeLookup
  # Same body as Sablon::Expression::LookupOrMethodCall#evaluate (0.4.3), with the two checks added
  def evaluate(context)
    receiver = receiver_expr.evaluate(context)
    return unless receiver

    expression.split(".").inject(receiver) do |local, m|
      case local
      when Hash
        local[m]
      else
        # H6 — refuse a hop onto (or from) a class, and the scope-dropping names
        if local.is_a?(Module) || SafeAttributePath::CLASS_HOP_NAMES.include?(m)
          Rails.logger.warn("[sablon] refused template field segment #{m.inspect} in «#{receiver_expr.name}.#{expression}»")
          break nil
        end

        local.public_send m if local.respond_to?(m)
      end
    end
  end
end

# Sablon is a gem, loaded once by Bundler (never reloaded), so prepending at boot is enough
Sablon::Expression::LookupOrMethodCall.prepend(SablonSafeLookup) unless Sablon::Expression::LookupOrMethodCall < SablonSafeLookup
