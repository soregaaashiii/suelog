namespace :shops do
  namespace :business_hours do
    desc "Rebuild searchable business-hour windows without updating shops"
    task rebuild: :environment do
      processed = 0
      windows = 0

      ShopBusinessHoursProjection.rebuild! do |shop_count, window_count|
        processed += shop_count
        windows += window_count
        puts "processed=#{processed} windows=#{windows}"
      end
    end
  end
end
