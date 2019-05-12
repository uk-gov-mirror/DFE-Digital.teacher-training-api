# == Schema Information
#
# Table name: site
#
#  id            :integer          not null, primary key
#  address2      :text
#  address3      :text
#  address4      :text
#  code          :text             not null
#  location_name :text
#  postcode      :text
#  address1      :text
#  provider_id   :integer          default(0), not null
#  region_code   :integer
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

require 'rails_helper'

describe Provider, type: :model do
  subject { create(:site) }

  describe 'auditing' do
    it { should be_audited.associated_with(:provider) }
  end

  it { is_expected.to validate_presence_of(:location_name) }
  it { is_expected.to validate_presence_of(:address1) }
  it { is_expected.to validate_presence_of(:address3) }
  it { is_expected.to validate_presence_of(:postcode) }
  it { is_expected.to validate_uniqueness_of(:location_name).scoped_to(:provider_id) }
  it { is_expected.to validate_uniqueness_of(:code).case_insensitive.scoped_to(:provider_id) }
  it { is_expected.to validate_presence_of(:code) }
  it { is_expected.to validate_inclusion_of(:code).in_array(Site::POSSIBLE_CODES).with_message('must be A-Z, 0-9 or -') }

  describe 'associations' do
    it { should belong_to(:provider) }
  end

  describe '#touch_provider' do
    let(:site) { create(:site) }

    it 'sets changed_at to the current time' do
      Timecop.freeze do
        site.touch
        expect(site.provider.changed_at).to eq Time.now.utc
      end
    end

    it 'leaves updated_at unchanged' do
      timestamp = 1.hour.ago
      site.provider.update updated_at: timestamp
      site.touch
      expect(site.provider.updated_at).to eq timestamp
    end
  end

  describe 'after running validation' do
    let(:provider) { create(:provider, site_count: 0) }
    subject { build(:site, provider: provider) }

    it 'is assigned a valid code by default' do
      expect { subject.valid? }.to change { subject.code.blank? }.from(true).to(false)
      expect(subject.errors[:code]).to be_empty
    end
  end
end
