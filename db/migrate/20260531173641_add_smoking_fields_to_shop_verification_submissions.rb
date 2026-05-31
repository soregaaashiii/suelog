class AddSmokingFieldsToShopVerificationSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_verification_submissions, :smoking_location, :string
    add_column :shop_verification_submissions, :tobacco_type, :string

    add_index :shop_verification_submissions, :smoking_location
    add_index :shop_verification_submissions, :tobacco_type
  end
end