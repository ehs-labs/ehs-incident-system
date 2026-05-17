class EnableExtensions < ActiveRecord::Migration[7.2]
  def change
    enable_extension "pgcrypto"  # gen_random_uuid()
    enable_extension "pg_trgm"   # trigram indexes for fuzzy search
  end
end
