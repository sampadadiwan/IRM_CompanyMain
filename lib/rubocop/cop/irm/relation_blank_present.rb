module RuboCop
  module Cop
    module IRM
      # Flags `blank?` / `present?` called directly on an ActiveRecord query chain.
      #
      # `ActiveRecord::Relation#blank?` (and `present?`, which negates it) materializes
      # the ENTIRE relation just to check emptiness — on large tables (account_entries,
      # capital_distribution_payments, documents, ...) that loads every matching row
      # into memory. This caused a production memory incident in doc generation where
      # `fund.account_entries.blank?` loaded a fund's whole ledger.
      #
      # Use instead:
      #   - `none?` / `exists?` / `empty?` — issue a cheap `SELECT 1 ... LIMIT 1`
      #   - or, if you iterate the same relation immediately afterwards, load it once
      #     into a variable (`records = scope.to_a`) and call `empty?` on the array —
      #     in that case the load is intentional and this cop does not apply.
      #
      # The cop is deliberately narrow: it only flags receivers that are unambiguously
      # relations (a call to where/includes/joins/order/distinct/not/rewhere/reorder/
      # left_joins), so plain-object blank?/present? checks are never flagged.
      #
      # @example
      #   # bad — loads every matching row
      #   return if fund.account_entries.where(fund_id: id).blank?
      #   if model.documents.where("name like ?", name).present?
      #
      #   # good — SELECT 1 LIMIT 1
      #   return if fund.account_entries.where(fund_id: id).none?
      #   if model.documents.where("name like ?", name).exists?
      class RelationBlankPresent < Base
        MSG = "`%<method>s` on an ActiveRecord relation loads every matching row into memory. " \
              "Use `none?`/`exists?` (SELECT 1 LIMIT 1) instead — or, if you iterate the " \
              "relation right after, load it into a variable once and check that.".freeze

        RESTRICT_ON_SEND = %i[blank? present?].freeze

        # Methods that make the receiver unambiguously an ActiveRecord relation
        QUERY_METHODS = %i[where rewhere not includes joins left_joins order reorder distinct].freeze

        # Argless query methods that still mark a chain as a relation (e.g. `.distinct.blank?`)
        ARGLESS_QUERY_METHODS = %i[distinct not].freeze

        # Safe-navigation chains (`scope&.where(...)&.blank?`) are deliberately out of
        # scope: they parse as csend nodes and their nil-propagation semantics make an
        # automatic none?/exists? rewrite unsafe, so we don't flag them.
        def on_send(node)
          receiver = node.receiver
          return unless receiver&.send_type?
          return unless QUERY_METHODS.include?(receiver.method_name)
          # Must be a chained call (`scope.where(...)`), not a bare method that happens to
          # share a query-method name (e.g. a local `joins` attribute) — and must take
          # arguments, unless the method is meaningful argless (distinct/not)
          return if receiver.receiver.nil?
          # rubocop:disable Rails/NegateInclude -- exclude? is ActiveSupport; unavailable inside the RuboCop process
          return if receiver.arguments.empty? && !ARGLESS_QUERY_METHODS.include?(receiver.method_name)
          # rubocop:enable Rails/NegateInclude

          add_offense(node, message: format(MSG, method: node.method_name))
        end
      end
    end
  end
end
