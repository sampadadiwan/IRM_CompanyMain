module DatabaseRoleHelper
  def with_writing_role(&)
    if Rails.env.test?
      # Directly execute the block in the test environment
      yield
    else
      # Wrap the block in the writing role in other environments
      ActiveRecord::Base.connected_to(role: :writing, &)
    end
  end
end
