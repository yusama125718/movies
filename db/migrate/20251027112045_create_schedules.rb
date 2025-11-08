class CreateSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :schedules do |t|
      t.date :date
      t.time :start_time
      t.time :end_time
      t.string :screen
      t.references :movie, null: false
      t.references :cinema, null: false
      t.timestamps
    end
  end
end
