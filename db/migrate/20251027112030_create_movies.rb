class CreateMovies < ActiveRecord::Migration[8.1]
  def change
    create_table :movies do |t|
      t.string :title
      t.string :image_link
      t.references :cinema, null: false
      t.timestamps
    end
  end
end
