# Demo data for a deal's Tasks and Notes — for exercising the deal task list,
# the deal kanban board (tasks?board=true&deal_id=ID) and the notes timeline
# without hand-creating records.
#
# Records are spread across the deal itself AND its DealInvestors, because that
# split is the whole point of the deal scope: the board shows both. Tasks land in
# all three kanban columns, with a mix of overdue, upcoming and undated due dates
# so the column ordering is visible, and touch points are attached wherever the
# LP has contacts recorded.
#
# Development only — it writes rows that look real, which has no business on a
# staging or production tenant.
#
# Every generated record is tagged "demo-seed" so you can find (and delete) them:
#   Task.where("tags LIKE '%demo-seed%'")  /  Note.where("tags LIKE '%demo-seed%'")
#
# Usage:
#   bundle exec rake deal:demo_activity[DEAL_ID]
#   bundle exec rake deal:demo_activity[DEAL_ID,30,20]   # 30 tasks, 20 notes

namespace :deal do
  desc "Generate fake tasks and notes for a deal and its investors (development only)"
  task :demo_activity, %i[deal_id task_count note_count] => :environment do |_, args|
    abort "Refusing to run outside development (Rails.env=#{Rails.env})" unless Rails.env.development?

    deal_id = args[:deal_id].to_i
    abort "Usage: rake deal:demo_activity[DEAL_ID,TASK_COUNT,NOTE_COUNT]" if deal_id.zero?

    deal = Deal.find_by(id: deal_id)
    abort "Deal #{deal_id} not found" unless deal

    task_count = (args[:task_count].presence || 24).to_i
    note_count = (args[:note_count].presence || 16).to_i

    entity = deal.entity
    deal_investors = deal.deal_investors.to_a
    abort "Deal #{deal_id} (#{deal.name}) has no investors — add some first" if deal_investors.empty?

    # Whoever the records are attributed to. Employees of the deal's own entity so
    # the assignee dropdown and the board's assignee filter have something to show.
    users = entity.employees.to_a
    abort "Entity #{entity.id} has no employees to attribute records to" if users.empty?

    puts "Deal #{deal.id}: #{deal.name}"
    puts "  investors: #{deal_investors.size}, users: #{users.size}"

    tag = "demo-seed"

    task_titles = [
      "Send the latest data room index",
      "Chase signed NDA",
      "Prepare the diligence Q&A pack",
      "Confirm wire instructions",
      "Schedule the management call",
      "Circulate the revised term sheet",
      "Collect KYC documents",
      "Review the side letter draft",
      "Follow up on the allocation request",
      "Share the quarterly reporting sample"
    ]

    note_bodies = [
      "Call with the team — walked through the fund strategy and the pipeline.",
      "They asked for a breakdown of fees and the GP commitment.",
      "Met at the industry conference; introduced to their head of private markets.",
      "Diligence questionnaire returned with follow-ups on valuation policy.",
      "Investment committee slot confirmed for next month.",
      "Discussed ticket size; indicated appetite subject to allocation.",
      "Legal flagged two points on the side letter — passed to counsel.",
      "Quiet since the last update; agreed to reconnect after their board meeting."
    ]

    # Contacts usable as touch points, keyed by deal investor. A DealInvestor's
    # touch points are its LP's contacts (DealInvestor#touch_point_options).
    contacts_by_investor = deal_investors.index_with do |di|
      InvestorAccess.where(investor_id: di.investor_id).to_a
    end

    investors_with_contacts = contacts_by_investor.count { |_di, contacts| contacts.any? }
    if investors_with_contacts.zero?
      puts "  WARNING: none of this deal's LPs have contacts recorded, so nothing can carry a"
      puts "           touch point. Add contacts on the stakeholders first (Investor > Users)."
    else
      puts "  investors with contacts: #{investors_with_contacts} (touch points will be attached)"
    end

    created_tasks = 0
    tasks_with_touch_point = 0
    task_count.times do |i|
      # Roughly a quarter of the work sits on the deal itself, the rest on
      # individual investors — the mix the board is meant to show.
      owner = (i % 4).zero? ? deal : deal_investors.sample
      status = %w[todo todo in_progress done].sample

      task = Task.new(
        entity: entity,
        for_entity: entity,
        user: users.sample,
        assigned_to: users.sample,
        details: "#{task_titles.sample} (#{Faker::Company.buzzword})",
        category: Task::CATEGORIES.sample,
        tags: [tag, %w[priority follow-up legal ops].sample].join(","),
        owner: owner
      )

      # A spread of due dates: overdue, upcoming, and some with none at all, so
      # the board's ordering (overdue first, undated last) is visible.
      task.due_date = case i % 5
                      when 0, 1 then Time.zone.today - rand(1..45).days
                      when 2, 3 then Time.zone.today + rand(1..60).days
                      end

      if status == "done"
        task.completed = true
        task.completed_on = Time.zone.today - rand(0..25).days
      else
        task.status = status
      end

      # Touch point: only for investor-owned tasks, and only where the LP has
      # contacts — the model rejects a contact belonging to another stakeholder.
      # Two in every three get one (not random), so a run always produces a solid
      # set of tasks that name a person, alongside some that don't.
      contacts = owner.is_a?(DealInvestor) ? contacts_by_investor[owner] : []
      if contacts.any? && (i % 3) != 2
        task.touch_point = contacts.sample
        tasks_with_touch_point += 1
      end

      # Demo data must not email anyone
      task.send_notification_flag = false
      completed_on = task.completed_on
      task.save!
      # stamp_completed_on resets completed_on to today on save — put the
      # backdated value back so the board's 30-day Done window has a spread
      Task.where(id: task.id).update_all(completed_on: completed_on) if task.completed
      created_tasks += 1
    end

    created_notes = 0
    notes_with_touch_point = 0
    note_count.times do |i|
      # Notes hang off investors, not the deal — Note::OWNER_TYPES is
      # User / Investor / DealInvestor.
      owner = deal_investors.sample
      contacts = contacts_by_investor[owner]

      note = Note.new(
        entity: entity,
        user: users.sample,
        owner: owner,
        details: note_bodies.sample,
        # Backdated so the timeline (and last-interaction dates) look lived-in
        on: Time.zone.today - rand(0..120).days,
        tags: [tag, %w[call meeting email].sample].join(",")
      )
      # Same two-in-three rule as the tasks: a note that names who it was with is
      # the point of the touch point, so most of them should have one.
      if contacts.any? && (i % 3) != 2
        note.touch_point = contacts.sample
        notes_with_touch_point += 1
      end
      note.save!
      created_notes += 1
    end

    puts "  created #{created_tasks} tasks (#{tasks_with_touch_point} with a touch point) " \
         "and #{created_notes} notes (#{notes_with_touch_point} with a touch point), all tagged #{tag}"
    puts "  board: /tasks?board=true&deal_id=#{deal.id}"
  end
end
