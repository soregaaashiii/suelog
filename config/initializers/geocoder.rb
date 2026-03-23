# frozen_string_literal: true

Geocoder.configure(
lookup: :google,
api_key: ENV["GOOGLE_MAPS_API_KEY"], # ← ここ修正（これが超重要）

use_https: true,
timeout: 5,
units: :km,
language: :ja,

always_raise: [
Geocoder::OverQueryLimitError,
Geocoder::RequestDenied,
Geocoder::InvalidRequest,
Geocoder::InvalidApiKey,
Geocoder::ServiceUnavailable
]
)