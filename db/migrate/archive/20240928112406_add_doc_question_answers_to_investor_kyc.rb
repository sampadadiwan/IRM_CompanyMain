class AddDocQuestionAnswersToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :doc_question_answers, :json
  end
end
