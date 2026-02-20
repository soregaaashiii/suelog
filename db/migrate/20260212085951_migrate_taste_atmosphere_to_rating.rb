class MigrateTasteAtmosphereToRating < ActiveRecord::Migration[7.0]
  def up
    Review.find_each do |review|
      if review.taste && review.atmosphere
        review.update_column(
          :rating,
          ((review.taste + review.atmosphere) / 2.0).round
        )
      end
    end
  end

  def down
    # 戻さない（不要）
  end
end
