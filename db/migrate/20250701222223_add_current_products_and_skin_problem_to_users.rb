class AddCurrentProductsAndSkinProblemToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :current_products, :text
    add_column :users, :skin_problem, :string
  end
end
