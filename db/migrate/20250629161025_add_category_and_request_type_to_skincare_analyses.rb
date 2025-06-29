class AddCategoryAndRequestTypeToSkincareAnalyses < ActiveRecord::Migration[7.1]
  def change
    add_column :skincare_analyses, :category, :string
    add_column :skincare_analyses, :request_type, :boolean
  end
end
