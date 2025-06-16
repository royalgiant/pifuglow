class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.string :title, null: false
      t.string :url
      t.string :category
      t.json :images
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end

    add_index :products, :url, unique: true
  end
end
