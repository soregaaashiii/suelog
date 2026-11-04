class CreateGurunaviCsvReconciliation < ActiveRecord::Migration[8.1]
  class MigrationShop < ActiveRecord::Base
    self.table_name = "shops"
  end

  def change
    add_column :shops, :gurunavi_csv_identity_key, :string
    add_index :shops, :gurunavi_csv_identity_key
    add_column :shops, :gurunavi_csv_url_key, :string
    add_index :shops, :gurunavi_csv_url_key
    create_table :gurunavi_csv_batches do |t|
      t.string :filename, null: false
      t.string :sha256, null: false
      t.binary :source_bytes, null: false
      t.string :state, null: false, default: "queued"
      t.string :phase, null: false, default: "queued"
      t.boolean :trial_mode, null: false, default: true
      t.string :area_filter
      t.integer :total_rows, null: false, default: 0
      t.integer :target_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.text :message
      t.timestamps
    end
    add_index :gurunavi_csv_batches, :sha256
    create_table :gurunavi_csv_rows do |t|
      t.references :gurunavi_csv_batch, null: false, foreign_key: true, index: false
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
    add_index :gurunavi_csv_rows, [:gurunavi_csv_batch_id, :line_number], unique: true, name: "index_gcsv_rows_line"
    add_index :gurunavi_csv_rows, [:gurunavi_csv_batch_id, :classification], name: "index_gcsv_rows_class"
    add_index :gurunavi_csv_rows, [:gurunavi_csv_batch_id, :normalized_name, :normalized_address], name: "index_gcsv_rows_identity"
    add_index :gurunavi_csv_rows, [:gurunavi_csv_batch_id, :canonical_url], name: "index_gcsv_rows_url"
    create_table :gurunavi_csv_matches do |t|
      t.references :gurunavi_csv_row, null: false, foreign_key: true
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
    add_index :gurunavi_csv_matches, :shop_id
    add_index :gurunavi_csv_matches, [:gurunavi_csv_row_id, :shop_id], unique: true, name: "index_gcsv_match_identity"
    create_table :gurunavi_csv_executions do |t|
      t.references :gurunavi_csv_batch, null: false, foreign_key: true
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
    create_table :gurunavi_csv_events do |t|
      t.references :gurunavi_csv_batch, null: false, foreign_key: true
      t.bigint :gurunavi_csv_row_id
      t.bigint :gurunavi_csv_match_id
      t.bigint :gurunavi_csv_execution_id
      t.string :action, null: false
      t.text :payload
      t.timestamps
    end
    create_table :gurunavi_csv_write_locks do |t|
      t.string :name, null: false
    end
    add_index :gurunavi_csv_write_locks, :name, unique: true
    reversible do |dir|
      dir.up do
        require "uri"
        model = MigrationShop
        model.reset_column_information
        model.select(:id, :name, :address, :gurunavi_url).find_in_batches(batch_size: 500) do |rows|
          identities, urls = [], []
          rows.each do |shop|
            identity = GurunaviCsv::Normalizer.identity(shop.name, shop.address)
            key = nil
            begin
              uri = URI.parse(shop.gurunavi_url.to_s.strip)
              if uri.is_a?(URI::HTTP) && uri.host.to_s.downcase == "r.gnavi.co.jp" && uri.userinfo.nil? && uri.port == uri.default_port && uri.path.match?(%r{\A/[a-z0-9]{6,32}/?\z}i)
                key = "https://r.gnavi.co.jp#{uri.path.sub(%r{/?$}, '/')}"
              end
            rescue URI::InvalidURIError
              key = nil
            end
            identities << "WHEN #{shop.id.to_i} THEN #{connection.quote(identity)}"
            urls << "WHEN #{shop.id.to_i} THEN #{connection.quote(key)}"
          end
          execute "UPDATE shops SET gurunavi_csv_identity_key = CASE id #{identities.join(' ')} END, gurunavi_csv_url_key = CASE id #{urls.join(' ')} END WHERE id IN (#{rows.map { |r| r.id.to_i }.join(',')})"
        end
      end
    end
  end
end
