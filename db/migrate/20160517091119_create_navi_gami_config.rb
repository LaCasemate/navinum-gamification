class CreateNaviGamiConfig < ActiveRecord::Migration
  def change
    create_table :navi_gami_configs do |t|
      t.text :external_space_url
      t.text :api_url
      t.text :context_id
      t.text :universe_id
    end
  end
end
