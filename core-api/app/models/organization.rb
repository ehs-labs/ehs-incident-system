class Organization < ApplicationRecord
  has_many :users,     dependent: :destroy
  has_many :sites,     dependent: :destroy
  has_many :incidents, dependent: :destroy
  has_one  :setting,   class_name: "OrganizationSetting", dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, format: { with: /\A[a-z0-9\-]+\z/ },
                   length: { maximum: 80 }, uniqueness: true
end
