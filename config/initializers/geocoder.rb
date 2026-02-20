# /config/initializers/geocoder.rb
Geocoder.configure(
lookup: :google,
api_key: ENV.fetch("GOOGLE_MAPS_SERVER_KEY", ""),
timeout: 5,
units: :km,
language: :ja,

# これが空だと絶対に取れないので、起動時に気づけるようにする
always_raise: [
Geocoder::OverQueryLimitError,
Geocoder::RequestDenied,
Geocoder::InvalidRequest,
Geocoder::InvalidApiKey,
Geocoder::ServiceUnavailable
]
)