class CreateChallenges < ActiveRecord::Migration
  def change
    create_table :navi_gami_challenges do |t|
      t.string :key
      t.belongs_to :training, index: true, foreign_key: true
      t.boolean :active, default: true
      t.string :medal_id
      t.timestamps null: false
    end
  end
end
