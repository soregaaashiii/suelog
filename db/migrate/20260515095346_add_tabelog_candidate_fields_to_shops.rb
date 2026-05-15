class AddTabelogCandidateFieldsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :tabelog_candidate_url, :string
    add_column :shops, :tabelog_candidate_affiliate_url, :string
    add_column :shops, :tabelog_candidate_matched_at, :datetime
    add_column :shops, :tabelog_candidate_method, :string
  end
end
