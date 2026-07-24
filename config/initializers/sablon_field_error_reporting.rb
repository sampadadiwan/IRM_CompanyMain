# Sablon (the docx mail-merge gem used by the various DocGen classes, see
# DocumentGeneratorBase#convert) only ever raises the raw Ruby error that
# happened while evaluating a merge field (NoMethodError, ZeroDivisionError,
# a typo'd predicate on a `:if(...)` field, etc). That error message says
# nothing about *which* field in the .docx template caused it, which makes
# fixing broken templates a guessing game.
#
# Each merge field parsed out of the template (see Sablon::Parser::MailMerge)
# keeps its raw expression text (e.g. "fund.total_committed_amount" or
# "capital_commitment:if(active?)") on the Statement that evaluates it. We
# patch those Statement#evaluate methods to catch any error and re-raise it
# wrapped with that expression plus the docx part (word/document.xml,
# word/header2.xml, ...) it came from.
module SablonFieldErrorReporting
  class FieldEvaluationError < StandardError
    attr_reader :field_expression, :source_part

    def initialize(field_expression, source_part, original_error)
      @field_expression = field_expression
      @source_part = source_part
      super("Error evaluating template field \"#{field_expression}\" in #{source_part}: #{original_error.message}")
    end
  end

  module StatementPatch
    def evaluate(env)
      super
    rescue FieldEvaluationError
      raise
    rescue StandardError => e
      raise FieldEvaluationError.new(sablon_field_expression, env.document.current_entry, e)
    end
  end

  module InsertionPatch
    include StatementPatch

    def sablon_field_expression
      field.expression
    end
  end

  module LoopPatch
    include StatementPatch

    def sablon_field_expression
      self.block.start_field.expression
    end
  end

  module ImagePatch
    include StatementPatch

    def sablon_field_expression
      self.block.start_field.expression
    end
  end

  module ConditionPatch
    def evaluate(env)
      @sablon_conditions_snapshot = @conditions.dup
      super
    rescue FieldEvaluationError
      raise
    rescue StandardError => e
      raise FieldEvaluationError.new(sablon_failed_condition_expression, env.document.current_entry, e)
    end

    private

    # @conditions has the just-failed condition shifted off of it by the time
    # we get here (Statement::Condition#eval_conditional_blocks shifts before
    # evaluating), so recover it by diffing against the snapshot taken above.
    def sablon_failed_condition_expression
      original = @sablon_conditions_snapshot || []
      remaining = @conditions || []
      failed_index = original.length - remaining.length - 1
      failed = original[failed_index] || original.first

      if failed
        failed[:block].start_field.expression
      elsif @else_block
        @else_block.start_field.expression
      else
        "conditional"
      end
    end
  end
end

Rails.application.config.to_prepare do
  Sablon::Statement::Insertion.prepend(SablonFieldErrorReporting::InsertionPatch)
  Sablon::Statement::Loop.prepend(SablonFieldErrorReporting::LoopPatch)
  Sablon::Statement::Image.prepend(SablonFieldErrorReporting::ImagePatch)
  Sablon::Statement::Condition.prepend(SablonFieldErrorReporting::ConditionPatch)
end
