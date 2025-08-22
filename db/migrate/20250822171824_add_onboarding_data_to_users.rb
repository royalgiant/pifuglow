class AddOnboardingDataToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :skin_concerns, :json
    add_column :users, :skin_profile, :json
    add_column :users, :skin_goal, :string
    add_column :users, :attribution_source, :string
  end
end
