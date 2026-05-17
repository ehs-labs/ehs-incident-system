namespace :users do
  desc "Republish every active user to users.v1 (idempotent — log-compacted topic)."
  task backfill_cdc: :environment do
    count = 0
    User.find_each(batch_size: 200) do |user|
      UserEventPublisher.publish_upsert!(user)
      count += 1
    end
    puts "[users:backfill_cdc] Queued #{count} UserUpserted events to the outbox."
  end
end
