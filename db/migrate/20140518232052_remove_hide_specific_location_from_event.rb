class RemoveHideSpecificLocationFromEvent < ActiveRecord::Migration
  def change
    remove_column :events, :hide_specific_location
  end
end