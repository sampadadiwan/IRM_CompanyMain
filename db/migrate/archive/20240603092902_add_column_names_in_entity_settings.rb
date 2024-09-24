class AddColumnNamesInEntitySettings < ActiveRecord::Migration[7.1]
  def change
    kanban_steps = {"Deal"=>
    ["Pre Term Sheet Memo",
     "Information Memorandum",
     "Business Plan",
     "IC Minutes",
     "Final Term Sheet",
     "Diligence Reports",
     "Closing Investment Memo",
     "Transaction Documents",
     "CP Confirmation Certificate"],
   "Blank"=>["Todo", "In Progres", "Done", "Validated"],
   "KanbanBoard"=>["Todo", "In Progres", "Done", "Validated"]}

   EntitySetting.update_all(kanban_steps: kanban_steps)
  end
end
