class TasksMailbox < ApplicationMailbox
  def process
    Chewy.strategy(:sidekiq) do
      if owner.instance_of?(::Task)
        owner.response += "</br> #{user.email}: #{mail.subject}. #{mail.body} </br>"
        owner.save
      else
        task = Task.new(details: "#{mail.subject}. #{mail.body}", owner:,
                        entity_id: owner.entity_id, user_id: user.id, for_entity_id: user.entity_id,
                        due_date: Time.zone.today + 7.days, tags: "Email")
        task.save
      end
    end
  end

  REGEXP = /(?<owner>[a-zA-Z_]*)-(?<owner_id>\d+)/

  def owner
    if mail.to.is_a?(String)
      res = mail.to.match(REGEXP)
    elsif mail.to.is_a?(Array)
      # Sometimes we get multiple emails in to, but only one of them will be in the format we need
      res = mail.to.map { |email| email.match(REGEXP) }.find(&:present?)
    end

    owner_id = res[:owner_id]
    owner_name = res[:owner].camelize
    @owner ||= owner_name.constantize.find(owner_id)
  end

  def user
    @user ||= User.find_by(email: mail.from[0])
  end
end
