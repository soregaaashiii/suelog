class CreateHotpepperApiReconciliation < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :hotpepper_api_identity_key, :string
    add_index :shops, :hotpepper_api_identity_key
    add_column :shops, :hotpepper_api_url_key, :string
    add_index :shops, :hotpepper_api_url_key
    create_table :hotpepper_api_batches do |t|
      t.string :filename, null: false
      t.string :sha256, null: false
      t.binary :source_bytes, null: false
      t.string :state, null: false, default: "queued"
      t.string :matching_basis, null: false, default: "shop"
      t.string :phase, null: false, default: "queued"
      t.boolean :trial_mode, null: false, default: true
      t.string :area_filter
      t.integer :total_rows, null: false, default: 0
      t.integer :target_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.text :message
      t.timestamps
    end
    add_index :hotpepper_api_batches, :sha256
    create_table :hotpepper_api_rows do |t|
      t.references :hotpepper_api_batch, null: false, foreign_key: true, index: false
      t.integer :line_number, null: false
      t.text :raw_row
      t.text :raw_fields
      t.string :csv_name
      t.text :csv_address
      t.text :csv_url
      t.text :canonical_url
      t.string :normalized_name
      t.text :normalized_address
      t.string :municipality
      t.string :classification, null: false, default: "pending"
      t.string :state, null: false, default: "pending"
      t.text :reason
      t.bigint :selected_match_id
      t.timestamps
    end
    add_index :hotpepper_api_rows, [ :hotpepper_api_batch_id, :line_number ], unique: true, name: "index_hapi_rows_line"
    add_index :hotpepper_api_rows, [ :hotpepper_api_batch_id, :classification ], name: "index_hapi_rows_class"
    add_index :hotpepper_api_rows, [ :hotpepper_api_batch_id, :normalized_name, :normalized_address ], name: "index_hapi_rows_identity"
    add_index :hotpepper_api_rows, [ :hotpepper_api_batch_id, :canonical_url ], name: "index_hapi_rows_url", unique: true
    create_table :hotpepper_api_matches do |t|
      t.references :hotpepper_api_row, null: false, foreign_key: true
      t.bigint :shop_id, null: false
      t.string :classification, null: false
      t.string :state, null: false, default: "pending"
      t.text :reason
      t.text :shop_snapshot
      t.boolean :allow_replace, null: false, default: false
      t.text :before_values
      t.text :after_values
      t.string :applied_version
      t.datetime :applied_at
      t.datetime :rolled_back_at
      t.timestamps
    end
    add_index :hotpepper_api_matches, :shop_id
    add_index :hotpepper_api_matches, [ :hotpepper_api_row_id, :shop_id ], unique: true, name: "index_hapi_match_identity"
    create_table :hotpepper_api_executions do |t|
      t.references :hotpepper_api_batch, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :state, null: false, default: "queued"
      t.string :run_token, null: false
      t.text :selection
      t.integer :total_count, null: false, default: 0
      t.integer :processed_count, null: false, default: 0
      t.text :message
      t.datetime :heartbeat_at
      t.timestamps
    end
    create_table :hotpepper_api_events do |t|
      t.references :hotpepper_api_batch, null: false, foreign_key: true
      t.bigint :hotpepper_api_row_id
      t.bigint :hotpepper_api_match_id
      t.bigint :hotpepper_api_execution_id
      t.string :action, null: false
      t.text :payload
      t.timestamps
    end
    create_table :hotpepper_api_write_locks do |t|
      t.string :name, null: false
    end
    add_index :hotpepper_api_write_locks, :name, unique: true
    create_table :hotpepper_api_targets do |t|
      t.references :hotpepper_api_batch, null: false, foreign_key: true
      t.bigint :shop_id, null: false
      t.text :shop_snapshot
      t.string :classification, null: false, default: "pending"
      t.string :state, null: false, default: "pending"
      t.text :reason
      t.bigint :selected_match_id
      t.timestamps
    end
    add_index :hotpepper_api_targets, [ :hotpepper_api_batch_id, :shop_id ], unique: true, name: "index_hapi_target_shop"
    add_index :hotpepper_api_targets, [ :hotpepper_api_batch_id, :classification ], name: "index_hapi_target_class"
    add_reference :hotpepper_api_matches, :hotpepper_api_target, foreign_key: true
    add_column :hotpepper_api_targets, :confidence, :integer, default: 0, null: false
    add_column :hotpepper_api_matches, :confidence, :integer, default: 0, null: false
    reversible do |dir|
      dir.up do
        model = Class.new(ActiveRecord::Base) { self.table_name = "shops" }
        model.reset_column_information
        model.select(:id, :name, :address, :hotpepper_url).find_in_batches(batch_size: 500) do |shops|
          identities, urls = [], []
          shops.each do |shop|
            identities << "WHEN #{shop.id.to_i} THEN #{connection.quote(GurunaviCsv::Normalizer.identity(shop.name, shop.address))}"
            urls << "WHEN #{shop.id.to_i} THEN #{connection.quote(RestaurantUrlSearch::Provider.new('hotpepper').canonical_url(shop.hotpepper_url))}"
          end
          execute "UPDATE shops SET hotpepper_api_identity_key = CASE id #{identities.join(' ')} END, hotpepper_api_url_key = CASE id #{urls.join(' ')} END WHERE id IN (#{shops.map { |shop| shop.id.to_i }.join(',')})"
        end
      end
    end
  end
end
