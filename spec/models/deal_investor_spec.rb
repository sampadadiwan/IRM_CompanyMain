require 'rails_helper'

# The deals grid sorts on DealInvestor#last_interaction_date. Three things feed it:
# a note's `on`, the day a task was completed, and a meaningful edit to the investor
# itself (completing a step, changing the status or the amounts), which counts as
# today. The first two are dates the user asserts rather than timestamps we observe,
# so a note typed today about a meeting in March must not move the row.
RSpec.describe DealInvestor, type: :model do
  let(:entity) { FactoryBot.create(:entity, entity_type: "Company") }
  let(:user) { FactoryBot.create(:user, entity: entity) }
  let(:investor_entity) { FactoryBot.create(:entity, entity_type: "Investor") }
  let(:investor) do
    FactoryBot.create(:investor, entity: entity, investor_entity: investor_entity,
                                 investor_name: investor_entity.name)
  end
  let(:deal) { FactoryBot.create(:deal, entity: entity) }
  let(:deal_investor) do
    FactoryBot.create(:deal_investor, deal: deal, entity: entity, investor: investor, status: "Active")
  end

  # Creating the investor sets its status, which is itself an interaction, so every
  # group below starts from a clean slate. The create-and-update rule is proved on
  # its own in "when the investor itself is saved".
  before { deal_investor.update_column(:last_interaction_date, nil) }

  def add_note(on:, details: "Call notes")
    note = Note.new(entity: entity, user: user, owner: deal_investor, on: on)
    note.details = details
    note.save!
    note
  end

  def add_task(details: "Send the SHA", completed: false)
    task = Task.new(entity: entity, user: user, owner: deal_investor, completed: completed)
    task.details = details
    task.save!
    task
  end

  describe "#register_interaction" do
    it "sets the date when there is none yet" do
      deal_investor.register_interaction(Date.new(2026, 3, 1))

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 3, 1))
    end

    it "moves the date forward" do
      deal_investor.register_interaction(Date.new(2026, 3, 1))
      deal_investor.register_interaction(Date.new(2026, 5, 20))

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 5, 20))
    end

    it "never moves the date backwards" do
      deal_investor.register_interaction(Date.new(2026, 5, 20))
      deal_investor.register_interaction(Date.new(2026, 3, 1))

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 5, 20))
    end

    it "ignores a blank date" do
      deal_investor.register_interaction(Date.new(2026, 5, 20))
      deal_investor.register_interaction(nil)

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 5, 20))
    end

    it "does not bump updated_at, which is the tiebreaker for rows with no interaction" do
      original = deal_investor.updated_at

      deal_investor.register_interaction(Date.new(2026, 5, 20))

      expect(deal_investor.reload.updated_at).to eq(original)
    end
  end

  describe "#recompute_last_interaction_date!" do
    it "takes the max `on` across the investor's notes" do
      add_note(on: Date.new(2026, 1, 1))
      add_note(on: Date.new(2026, 4, 15))
      add_note(on: Date.new(2026, 2, 20))

      deal_investor.recompute_last_interaction_date!

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 4, 15))
    end

    it "ignores notes with no `on` date" do
      add_note(on: nil)
      add_note(on: Date.new(2026, 1, 1))

      deal_investor.recompute_last_interaction_date!

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 1, 1))
    end

    it "is nil when no note carries a date" do
      add_note(on: nil)

      deal_investor.recompute_last_interaction_date!

      expect(deal_investor.reload.last_interaction_date).to be_nil
    end

    it "includes completed tasks and ignores incomplete ones" do
      add_note(on: Date.new(2026, 1, 1))
      add_task(completed: false)
      completed = add_task(completed: true)
      completed.update_columns(completed_on: Date.new(2026, 6, 30))

      deal_investor.recompute_last_interaction_date!

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 6, 30))
    end

    it "recomputes downwards, unlike register_interaction" do
      deal_investor.update_column(:last_interaction_date, Date.new(2026, 12, 31))
      add_note(on: Date.new(2026, 1, 1))

      deal_investor.recompute_last_interaction_date!

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 1, 1))
    end
  end

  # The third source. Not every save counts: WithFolder saves the record the first
  # time its document folder is needed — which is what opening the sidepanel does —
  # and messages_viewed writes read counters. Neither is an interaction, and both
  # would otherwise reshuffle the grid just for looking at a row.
  describe "when the investor itself is saved" do
    let(:other_investor) do
      FactoryBot.create(:investor, entity: entity,
                                   investor_entity: FactoryBot.create(:entity, entity_type: "Investor"))
    end

    it "registers today when the investor is created" do
      fresh = FactoryBot.create(:deal_investor, deal: deal, entity: entity,
                                                investor: other_investor, status: "Active")

      expect(fresh.reload.last_interaction_date).to eq(Time.zone.today)
    end

    it "registers today when the status changes" do
      deal_investor.update!(status: "Pending")

      expect(deal_investor.reload.last_interaction_date).to eq(Time.zone.today)
    end

    # How a completed step reaches this model: PerformActivityAction moves the
    # investor on to the next step and saves it.
    it "registers today when the investor moves to another step" do
      activity = DealActivity.create!(deal: deal, entity: entity, title: "Term Sheet", days: 5)

      deal_investor.update!(deal_activity_id: activity.id)

      expect(deal_investor.reload.last_interaction_date).to eq(Time.zone.today)
    end

    it "ignores a save that changes nothing meaningful" do
      deal_investor.update!(unread_messages_investor: 3)

      expect(deal_investor.reload.last_interaction_date).to be_nil
    end

    it "does not pull a later note's date back to today" do
      deal_investor.update_column(:last_interaction_date, Date.new(2026, 12, 31))

      deal_investor.update!(status: "Pending")

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 12, 31))
    end
  end

  describe "when a note is saved" do
    it "moves the investor to the note's `on` date" do
      add_note(on: Date.new(2026, 4, 15))

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 4, 15))
    end

    it "leaves the date alone when the note is undated" do
      deal_investor.update_column(:last_interaction_date, Date.new(2026, 4, 15))

      add_note(on: nil)

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 4, 15))
    end

    it "leaves the date alone when the note is backdated" do
      deal_investor.update_column(:last_interaction_date, Date.new(2026, 4, 15))

      add_note(on: Date.new(2026, 1, 1))

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 4, 15))
    end

    it "follows an edit that pushes the `on` date forward" do
      note = add_note(on: Date.new(2026, 1, 1))

      note.update!(on: Date.new(2026, 4, 15))

      expect(deal_investor.reload.last_interaction_date).to eq(Date.new(2026, 4, 15))
    end

    it "no longer touches the investor" do
      original = deal_investor.updated_at

      add_note(on: Date.new(2026, 4, 15))

      expect(deal_investor.reload.updated_at).to eq(original)
    end
  end

  describe "when a task is saved" do
    it "does nothing while the task is incomplete" do
      original = deal_investor.updated_at

      task = add_task(completed: false)

      expect(task.completed_on).to be_nil
      expect(deal_investor.reload.last_interaction_date).to be_nil
      expect(deal_investor.updated_at).to eq(original)
    end

    it "stamps completed_on and moves the investor on completion" do
      task = add_task(completed: false)

      task.update!(completed: true)

      expect(task.reload.completed_on).to eq(Time.zone.today)
      expect(deal_investor.reload.last_interaction_date).to eq(Time.zone.today)
    end

    it "clears completed_on when the task is re-opened" do
      task = add_task(completed: true)

      task.update!(completed: false)

      expect(task.reload.completed_on).to be_nil
    end

    # Re-opening removes the reason for the date but not the fact that the work
    # happened, so the investor keeps its position.
    it "leaves last_interaction_date in place when the task is re-opened" do
      task = add_task(completed: true)

      task.update!(completed: false)

      expect(deal_investor.reload.last_interaction_date).to eq(Time.zone.today)
    end
  end
end
