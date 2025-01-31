require "rails_helper"

describe Provider, type: :model do
  let(:accrediting_provider_enrichments) { [] }
  let(:courses) { [] }
  let(:provider) do
    create(:provider,
           provider_name: "ACME SCITT",
           provider_code: "A01",
           accrediting_provider_enrichments: accrediting_provider_enrichments,
           courses: courses)
  end

  subject { provider }

  its(:to_s) { should eq("ACME SCITT (A01) [#{provider.recruitment_cycle}]") }

  describe "auditing" do
    it { should be_audited.except(:changed_at) }
    it { should have_associated_audits }
  end

  describe "associations" do
    it { should have_many(:sites) }
    it { should have_many(:users).through(:organisations) }
    it { should have_one(:ucas_preferences).class_name("ProviderUCASPreference") }
    it { should have_many(:contacts) }
    it { should have_many(:user_notifications) }
  end

  describe "urn validations" do
    context "when provider_type is lead_schools" do
      let(:invalid_provider) { build(:provider, urn: "1") }
      let(:valid) { build(:provider, urn: "12345") }

      it "validates a urn of length 5 - 6" do
        expect(invalid_provider).to_not be_valid
        expect(provider).to be_valid
      end
    end
  end

  describe "organisation" do
    it "returns the only organisation a provider has" do
      expect(subject.organisation).to eq subject.organisations.first
    end
  end

  describe "users" do
    let(:discarded_user) { create(:user, :discarded) }

    before do
      provider.organisation.users << discarded_user
    end

    it "returns users who haven't been discarded" do
      expect(subject.users).not_to include(discarded_user)
    end
  end

  describe "changed_at" do
    it "is set on create" do
      provider = Provider.create(
        recruitment_cycle: find_or_create(:recruitment_cycle),
        email: "email@test.com",
        telephone: "0123456789",
      )

      expect(provider.changed_at).to be_present
      expect(provider.changed_at).to eq provider.updated_at
    end

    it "is set on update" do
      Timecop.freeze do
        provider = create(:provider, updated_at: 1.hour.ago)
        provider.touch
        expect(provider.changed_at).to eq provider.updated_at
        expect(provider.changed_at).to eq Time.now.utc
      end
    end
  end

  context "order" do
    let(:provider_a) { create(:provider, provider_name: "Provider A") }
    let(:provider_b) { create(:provider, provider_name: "Provider B") }
    describe "#by_name_ascending" do
      it "orders the providers by name in ascending order" do
        provider_a
        provider_b
        expect(Provider.by_name_ascending).to eq([provider_a, provider_b])
      end
    end

    describe "#by_name_descending" do
      it "orders the providers by name in descending order" do
        provider_a
        provider_b
        expect(Provider.by_name_descending).to eq([provider_b, provider_a])
      end
    end

    describe "#by_provider_name" do
      it "orders the providers by name in descending order" do
        provider_a
        provider_b
        expect(Provider.by_provider_name(provider_b.provider_name)).to eq([provider_b, provider_a])
      end
    end
  end

  describe "#changed_since" do
    context "with a provider that has been changed after the given timestamp" do
      let(:provider) { create(:provider, changed_at: 5.minutes.ago) }

      subject { Provider.changed_since(10.minutes.ago) }

      it { should include provider }
    end

    context "with a provider that has been changed less than a second after the given timestamp" do
      let(:timestamp) { 5.minutes.ago }
      let(:provider) { create(:provider, changed_at: timestamp + 0.001.seconds) }

      subject { Provider.changed_since(timestamp) }

      it { should include provider }
    end

    context "with a provider that has been changed exactly at the given timestamp" do
      let(:publish_time) { 10.minutes.ago }
      let(:provider) { create(:provider, changed_at: publish_time) }

      subject { Provider.changed_since(publish_time) }

      it { should_not include provider }
    end

    context "with a provider that has been changed before the given timestamp" do
      let(:provider) { create(:provider, changed_at: 1.hour.ago) }

      subject { Provider.changed_since(10.minutes.ago) }

      it { should_not include provider }
    end
  end

  describe "#update_changed_at" do
    let(:provider) { create(:provider, changed_at: 1.hour.ago) }

    it "sets changed_at to the current time" do
      Timecop.freeze do
        provider.update_changed_at
        expect(provider.changed_at).to eq Time.now.utc
      end
    end

    it "sets changed_at to the given time" do
      timestamp = 1.hour.ago
      provider.update_changed_at timestamp: timestamp
      expect(provider.changed_at).to eq timestamp
    end

    it "leaves updated_at unchanged" do
      timestamp = 1.hour.ago
      provider.update updated_at: timestamp

      provider.update_changed_at
      expect(provider.updated_at).to eq timestamp
    end
  end

  describe "#provider_type=" do
    subject { build(:provider, accrediting_provider: nil) }

    it "sets the provider type" do
      expect { subject.provider_type = "scitt" }
        .to change { subject.provider_type }
        .from("lead_school").to("scitt")
    end

    it "sets 'accrediting_provider' correctly for SCITTs" do
      expect { subject.provider_type = "scitt" }
        .to change { subject.accrediting_provider }
        .from(nil).to("accredited_body")
    end

    it "sets 'accrediting_provider' correctly for universities" do
      expect { subject.provider_type = "university" }
        .to change { subject.accrediting_provider }
        .from(nil).to("accredited_body")
    end

    it "sets 'accrediting_provider' correctly for universities" do
      expect { subject.provider_type = "lead_school" }
        .to change { subject.accrediting_provider }
        .from(nil).to("not_an_accredited_body")
    end
  end

  its(:recruitment_cycle) { should eq find(:recruitment_cycle) }

  describe "#unassigned_site_codes" do
    subject { create(:provider) }
    before do
      %w[A B C D 1 2 3 -].each { |code| subject.sites << build(:site, code: code) }
    end

    let(:expected_unassigned_codes) { ("E".."Z").to_a + %w[0] + ("4".."9").to_a }

    its(:unassigned_site_codes) { should eq(expected_unassigned_codes) }
  end

  describe "#can_add_more_sites?" do
    context "when provider has less sites than max allowed" do
      subject { create(:provider) }
      its(:can_add_more_sites?) { should be_truthy }
    end

    context "when provider has the max sites allowed" do
      let(:all_site_codes) { ("A".."Z").to_a + %w[0 -] + ("1".."9").to_a }
      let(:sites) do
        all_site_codes.map { |code| build(:site, code: code) }
      end

      subject { create(:provider, sites: sites) }

      its(:can_add_more_sites?) { should be_falsey }
    end
  end

  it "defines an enum for accrediting_provider" do
    expect(subject)
      .to define_enum_for("accrediting_provider")
      .backed_by_column_of_type(:text)
      .with_values("accredited_body" => "Y", "not_an_accredited_body" => "N")
  end

  it "defines an enum for accrediting_provider" do
    expect(subject)
      .to define_enum_for("scheme_member")
      .backed_by_column_of_type(:text)
      .with_values("is_a_UCAS_ITT_member" => "Y", "not_a_UCAS_ITT_member" => "N")
  end

  describe "courses" do
    let(:course) { create(:course, :primary, :unpublished) }
    let!(:provider) { course.provider }

    describe "#courses_count" do
      it "returns course count using courses.size" do
        allow(provider.courses).to receive(:size).and_return(1)

        expect(provider.courses_count).to eq(1)
        expect(provider.courses).to have_received(:size)
      end

      context "with .include_courses_counts" do
        let(:provider_with_included) { Provider.include_courses_counts.first }

        it "return course count using included_courses_count" do
          allow(provider_with_included).to receive(:included_courses_count).and_return(1)
          allow(provider_with_included.courses).to receive(:size)

          expect(provider_with_included.courses_count).to eq(1)
          expect(provider_with_included).to have_received(:included_courses_count)
          expect(provider_with_included.courses).to_not have_received(:size)
        end
      end

      context "with .include_accredited_courses_counts" do
        let(:provider_with_included) { Provider.include_accredited_courses_counts(provider.provider_code).first }

        it "return course count using included_accredited_courses_count" do
          allow(provider_with_included).to receive(:included_accredited_courses_count).and_return(1)
          allow(provider_with_included.courses).to receive(:size)

          expect(provider_with_included.accredited_courses_count).to eq(1)
          expect(provider_with_included).to have_received(:included_accredited_courses_count)
          expect(provider_with_included.courses).to_not have_received(:size)
        end
      end
    end

    describe "#courses" do
      describe "discard" do
        it "reduces courses when one is discarded" do
          expect { course.discard }.to change { provider.reload.courses.size }.by(-1)
        end
      end
    end
  end

  describe "accrediting_providers" do
    let(:provider) { create :provider, accrediting_provider: "N" }

    let(:accrediting_provider) { create :provider, accrediting_provider: "Y" }
    let!(:course1) { create :course, accrediting_provider: accrediting_provider, provider: provider }
    let!(:course2) { create :course, accrediting_provider: accrediting_provider, provider: provider }

    it "returns the course's accrediting provider" do
      expect(provider.accrediting_providers.first).to eq(accrediting_provider)
    end

    it "does not duplicate data" do
      expect(provider.accrediting_providers.count).to eq(1)
    end
  end

  describe "training_providers" do
    let(:accredited_provider) { create(:provider, :accredited_body) }
    let(:training_provider1) { create(:provider) }
    let(:training_provider2) { create(:provider) }

    let!(:course1) { create(:course, accrediting_provider: accredited_provider, provider: training_provider1) }
    let!(:course2) { create(:course, provider: training_provider2) }

    subject { accredited_provider.training_providers }

    it { is_expected.to contain_exactly(training_provider1) }
  end

  describe "#before_create" do
    describe "#set_defaults" do
      let(:provider) { build :provider }

      it 'sets scheme_member to "Y"' do
        expect(provider.scheme_member).to be_nil

        provider.save!

        expect(provider.is_a_UCAS_ITT_member?).to be_truthy
      end

      it "sets the year_code from the recruitment_cycle" do
        expect(provider.year_code).to be_nil

        provider.save!

        expect(provider.year_code).to eq(provider.recruitment_cycle.year)
      end

      it "does not override a given value for scheme_member" do
        provider.scheme_member = "not_a_UCAS_ITT_member"

        provider.save!

        expect(provider.scheme_member).to eq("not_a_UCAS_ITT_member")
      end

      it "does not override a given value for year_code" do
        provider.year_code = 2020

        provider.save!

        expect(provider.year_code).to eq("2020")
      end
    end
  end

  describe "#discard" do
    subject { create(:provider) }

    context "before discarding" do
      its(:discarded?) { should be false }

      it "is in kept" do
        provider
        expect(described_class.kept.size).to eq(1)
      end

      it "is not in discarded" do
        expect(described_class.discarded.size).to eq(0)
      end
    end

    context "after discarding" do
      before do
        subject.discard
      end

      its(:discarded?) { should be true }

      it "is not in kept" do
        expect(described_class.kept.size).to eq(0)
      end

      it "is in discarded" do
        expect(described_class.discarded.size).to eq(1)
      end
    end

    context "a provider with courses" do
      let(:provider) { create(:provider, courses: [course, course2]) }
      let(:course) { build(:course) }
      let(:course2) { build(:course) }

      before do
        provider.discard
      end

      it "should discard all of the providers courses" do
        expect(course.discarded?).to be_truthy
        expect(course2.discarded?).to be_truthy
      end
    end
  end

  describe "#discard_courses" do
    let(:provider) { create(:provider, courses: [course, course2]) }
    let(:course) { build(:course) }
    let(:course2) { build(:course) }

    before do
      provider.discard_courses
    end

    it "should discard all of the providers courses" do
      expect(course.discarded?).to be_truthy
      expect(course2.discarded?).to be_truthy
    end
  end

  describe "#next_available_course_code" do
    let(:provider) { create(:provider) }
    let(:course1) { create(:course, provider: provider, course_code: "A123") }
    let(:course2) { create(:course, provider: provider, course_code: "B456") }

    before do
      course1
      course2
    end

    it "Delegates to the correct service" do
      expect(provider).to delegate_method_to_service(
        :next_available_course_code,
        "Providers::GenerateUniqueCourseCodeService",
      ).with_arguments(
        existing_codes: %w[A123 B456],
        )
    end
  end

  describe "#accredited_courses" do
    subject { provider.accredited_courses }

    let(:provider) { create :provider, :accredited_body }
    let!(:findable_course) do
      create :course, name: "findable-course",
             accrediting_provider: provider,
             site_statuses: [build(:site_status, :findable)]
    end
    let!(:discarded_course) do
      create :course, :deleted,
             name: "deleted-course",
             accrediting_provider: provider
    end
    let!(:discontinued_course) do
      create :course,
             name: "discontinued-course",
             accrediting_provider: provider,
             site_statuses: [build(:site_status, :discontinued)]
    end

    it { should include findable_course }
    it { should include discontinued_course }
    it { should_not include discarded_course }

    describe "#current_accredited_courses" do
      subject { provider.current_accredited_courses }

      let(:last_years_provider) do
        # make provider_codes the same to simulate a rolled over provider
        create :provider, :previous_recruitment_cycle, provider_code: provider.provider_code
      end
      let!(:last_years_course) do
        create :course,
               name: "last-years-course",
               provider: last_years_provider,
               accrediting_provider: provider,
               site_statuses: [build(:site_status, :discontinued)]
      end

      it { should_not include last_years_course }
    end
  end

  describe "scopes" do
    describe ".with_findable_courses" do
      let(:findable_course) do
        create(:course, site_statuses: [build(:site_status, :findable)])
      end

      let(:findable_course_with_accrediting_provider) do
        create(:course, :with_accrediting_provider, site_statuses: [build(:site_status, :findable)])
      end

      let(:non_findable_course) do
        create(:course, site_statuses: [build(:site_status)])
      end

      let(:non_findable_course_with_accrediting_provider) do
        create(:course, :with_accrediting_provider, site_statuses: [build(:site_status)])
      end

      subject {
        described_class.with_findable_courses
      }

      it "should return only findable courses' provider and/or accrediting provider" do
        expect(subject).to contain_exactly(findable_course.provider,
                                           findable_course_with_accrediting_provider.provider,
                                           findable_course_with_accrediting_provider.accrediting_provider)
      end

      context "when the provider is the accredited body for a course" do
        before do
          findable_course_with_accrediting_provider
          non_findable_course_with_accrediting_provider
        end

        it "is returned" do
          expect(subject).to contain_exactly(
            findable_course_with_accrediting_provider.provider,
            findable_course_with_accrediting_provider.accrediting_provider,
          )
        end
      end

      context "when the course is delivered by the provider" do
        before do
          findable_course
          non_findable_course
        end
        it "is returned" do
          expect(subject).to contain_exactly(findable_course.provider)
        end
      end

      context "when the course is not findable" do
        before do
          non_findable_course
          non_findable_course_with_accrediting_provider
        end
        it "is not returned" do
          expect(subject).to_not include(non_findable_course.provider,
                                         non_findable_course_with_accrediting_provider.provider,
                                         non_findable_course_with_accrediting_provider.accrediting_provider)
        end
      end
    end

    describe "in_current_cycle" do
      let(:current_provider) { create(:provider) }
      let(:non_current_provider) { create(:provider, :previous_recruitment_cycle) }

      before do
        current_provider
        non_current_provider
      end

      subject { described_class.in_current_cycle }

      it "includes providers in the current recruitment cycle" do
        expect(subject).to contain_exactly(current_provider)
      end
    end
  end

  describe "geolocation" do
    include ActiveJob::TestHelper

    after do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    # Geocoding stubbed with support/helpers.rb
    let(:provider) {
      build(:provider,
            provider_name: "Southampton High School",
            address1: "Long Lane",
            address2: "Holbury",
            address3: "Southampton",
            address4: nil,
            postcode: "SO45 2PA")
    }

    describe "#full_address" do
      it "Concatenates address details" do
        expect(provider.full_address).to eq("Southampton High School, Long Lane, Holbury, Southampton, SO45 2PA")
      end

      context "address is missing" do
        before do
          provider.provider_name = ""
          provider.address1 = ""
          provider.address2 = ""
          provider.address3 = ""
          provider.address4 = ""
          provider.postcode = ""
        end

        it "returns an empty string" do
          expect(provider.full_address).to eq("")
        end
      end
    end

    describe "#needs_geolocation?" do
      subject { provider.needs_geolocation? }

      context "latitude is nil" do
        let(:provider) { build_stubbed(:provider, latitude: nil) }

        it { should be(true) }
      end

      context "longitude is nil" do
        let(:provider) { build_stubbed(:provider, longitude: nil) }

        it { should be(true) }
      end

      context "latitude and longitude is not nil" do
        let(:provider) { build_stubbed(:provider, latitude: 1.456789, longitude: 1.456789) }

        it { should be(false) }
      end

      context "address" do
        let(:provider) {
          create(:provider,
                 latitude: 1.456789,
                 longitude: 1.456789,
                 provider_name: "Southampton High School",
                 address1: "Long Lane",
                 address2: "Holbury",
                 address3: "Southampton",
                 address4: nil,
                 postcode: "SO45 2PA")
        }
        context "has not changed" do
          before do
            provider.update(address1: "Long Lane")
          end

          it { should be(false) }
        end

        context "has changed" do
          before do
            provider.update(address1: "New address 1")
          end

          it { should be(true) }
        end
      end
    end

    describe "#skip_geocoding" do
      before do
        allow(GeocodeJob).to receive(:perform_later)
      end

      context "skip_geocoding is 'true'" do
        it "does not geocode" do
          provider.skip_geocoding = true

          provider.save

          expect(GeocodeJob).to_not have_received(:perform_later)
        end
      end

      context "skip_geocoding is 'false'" do
        it "does not geocode" do
          provider.skip_geocoding = false

          provider.save

          expect(GeocodeJob).to have_received(:perform_later)
        end
      end
    end
  end

  describe "#search_by_code_or_name" do
    let!(:matching_provider) { create(:provider, provider_code: "ABC", provider_name: "Dave's Searches") }
    let!(:non_matching_provider) { create(:provider) }

    subject { described_class.search_by_code_or_name(search_term) }

    context "with an exactly matching code" do
      let(:search_term) { "ABC" }
      it { is_expected.to contain_exactly(matching_provider) }
    end

    context "with an exactly matching name" do
      let(:search_term) { "Dave's Searches" }
      it { is_expected.to contain_exactly(matching_provider) }
    end

    context "with unicode in the name" do
      let(:search_term) { "Dave’s Searches" }
      it { is_expected.to contain_exactly(matching_provider) }
    end

    context "with extra spaces in the name" do
      let(:search_term) { "Dave's  Searches" }
      it { is_expected.to contain_exactly(matching_provider) }
    end

    context "with non matching case code" do
      let(:search_term) { "abc" }
      it { is_expected.to contain_exactly(matching_provider) }
    end

    context "with non matching case name" do
      let(:search_term) { "dave's searches" }
      it { is_expected.to contain_exactly(matching_provider) }
    end

    context "with partial search term" do
      let(:search_term) { "dave" }
      it { is_expected.to contain_exactly(matching_provider) }
    end
  end
end
