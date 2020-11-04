require "rails_helper"

describe CourseOrderingService do
  subject { described_class.call(filter: filter, sort: sort, course_scope: Course.all) }

  describe "sort by provider name" do
    let(:filter) { { "provider.provider_name": "Dave" } }
    let(:sort) { nil }
    let(:provider) { create(:provider, provider_name: "AAA") }
    let(:provider_two) { create(:provider, provider_name: "BBB") }

    describe "courses the provider delivers" do
      let(:course_one) { create(:course, name: "Z-course", provider: provider) }
      let(:course_two) { create(:course, name: "A-course", provider: provider_two) }
      let(:course_three) { create(:course, name: "G-course", provider: provider) }

      before do
        course_one # AAA Z-course
        course_two # BBB A-course
        course_three # AAA G-course
      end

      it "orders by provider name course name ascending" do
        # AAA G-course, AAA Z-course BBB A-course
        expect(subject).to eq [course_three, course_one, course_two]
      end
    end

    describe "courses the provider is an accredited body for" do
      let(:delivered_course_one) { create(:course, name: "Z-course", provider: provider) }
      let(:accredited_course_one) { create(:course, provider: provider_two,  name: "A-course", accredited_body_code: provider.provider_code) }
      let(:accredited_course_two) { create(:course, provider: provider_two,  name: "G-course", accredited_body_code: provider.provider_code) }

      before do
        accredited_course_two # BBB G-course accredited by AAA
        accredited_course_one # BBB A-course accredited by AAA
        delivered_course_one # AAA Z-course
      end

      it "lists them after the courses that are delivered" do
        # AAA Z-course BBB A-course BBB G-course
        expect(subject).to eq [delivered_course_one, accredited_course_one, accredited_course_two]
      end
    end
  end

  describe "sort by course name and provider name" do
    let(:provider_one) { create(:provider, provider_name: "AAA") }
    let(:provider_two) { create(:provider, provider_name: "BBB") }
    let(:course_one) { create(:course, name: "A-course", provider: provider_one) }
    let(:course_two) { create(:course, name: "B-course", provider: provider_two) }
    let(:course_three) { create(:course, name: "C-course", provider: provider_one) }

    let(:filter) { {} }

    before do
      course_two # BBB B-course
      course_three # AAA C-course
      course_one # AAA A-course
    end

    context "ascending" do
      let(:sort) { "name,provider.provider_name" }

      it "orders by provider name course name ascending" do
        # AAA A-course AAA C-course BBB B-course
        expect(subject).to eq [course_one, course_three, course_two]
      end
    end

    context "descending" do
      let(:sort) { "-name,-provider.provider_name" }

      it "orders by provider name course name descending" do
        # BBB B-course AAA C-course AAA A-course
        expect(subject).to eq [course_two, course_three, course_one]
      end
    end
  end

  describe "sort by distance" do
    let(:sort) { "distance" }

    let(:origin) { { latitude: 53.384589, longitude: -2.941050 } }
    let(:closest) { { latitude: 53.380147, longitude: -2.894760 } }
    let(:middle) { { latitude: 53.420033, longitude: -2.939805 } }
    let(:furthest) { { latitude: 53.457170, longitude: -2.993871 } }

    let(:provider_one) { create(:provider) }
    let(:provider_two) { create(:provider, :university) }
    let(:provider_three) { create(:provider) }

    let(:course_one) { create(:course, provider: provider_one) }
    let(:course_two) { create(:course, provider: provider_two) }
    let(:course_three) { create(:course, provider: provider_three) }

    let(:site_status_one) { create(:site_status, :published, site: build(:site, { provider: provider_one }.merge(closest)), course: course_one) }
    let(:site_status_two) { create(:site_status, :published, site: build(:site, { provider: provider_two }.merge(middle)), course: course_two) }
    let(:site_status_three) { create(:site_status, :published, site: build(:site, { provider: provider_three }.merge(furthest)), course: course_three) }

    before do
      site_status_two # middle (uni)
      site_status_three # furthest
      site_status_one # closest
    end

    context "with expand_university" do
      let(:filter) { { expand_university: true }.merge(origin) }

      it "orders by distance but boosts universities" do
        # middle (uni) closest furthest
        expect(subject).to eq [course_two, course_one, course_three]
      end
    end

    context "without expand_university" do
      let(:filter) { { expand_university: false }.merge(origin) }

      it "orders by distance" do
        # closest middle furthest
        expect(subject).to eq [course_one, course_two, course_three]
      end
    end
  end
end
