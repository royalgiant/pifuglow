class CreateSkincareAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :skincare_analyses do |t|
      t.string :image_url
      t.string :diagnosis
      t.string :email
      t.references :user, foreign_key: true

      t.timestamps
    end
  end
end
