FactoryBot.define do
  factory :zoho_sign_connection do
    entity
    region { "com" }
    client_id { "1000.ARKACLIENT" }
    client_secret { "arka-client-secret" }
    refresh_token { "arka-refresh-token" }
    webhook_secret { "arka-secret" }
    connected_at { 1.hour.ago.change(usec: 0) }
  end
end
