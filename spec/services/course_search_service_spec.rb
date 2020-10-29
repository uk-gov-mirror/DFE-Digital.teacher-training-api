require "rails_helper"

describe CourseSearchService do
  describe "filters" do
    subject { described_class.call(filter: filter) }

    describe "funding" do
      context "= salary" do
        let(:filter) { { funding: "salary" } }

        before do
          course
        end

        context "salaried course" do
          let(:course) { create(:course, :salary_type_based) }
          it { is_expected.to include(course) }
        end

        context "non salaried course" do
          let(:course) { create(:course, :non_salary_type_based) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "qualification" do
      context "= qts,pgde_with_qts" do
        let(:filter) { { qualification: "qts,pgde_with_qts" } }

        context "qts course" do
          let(:course) { create(:course, :resulting_in_qts) }
          it { is_expected.to include(course) }
        end

        context "pgde_with_qts course" do
          let(:course) { create(:course, :resulting_in_pgde_with_qts) }
          it { is_expected.to include(course) }
        end

        context "pgce_course" do
          let(:course) { create(:course, :resulting_in_pgce) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "has_vacancies" do
      context "= true" do
        let(:filter) { { has_vacancies: true } }

        context "course with vacancies" do
          let(:course) { create(:course, :with_vacancies) }
          it { is_expected.to include(course) }
        end

        context "course without vacancies" do
          let(:course) { create(:course, :without_vacancies) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "study_types" do
      context "= full_time" do
        let(:filter) { { study_type: "full_time" } }

        context "full time course" do
          let(:course) { create(:course, :full_time) }
          it { is_expected.to include(course) }
        end

        context "part time course" do
          let(:course) { create(:course, :part_time) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "subjects" do
      context "= 00,01,02" do
        let(:filter) { { subjects: "#{primary.subject_code},01,02" } }
        let(:primary) { create(:primary_subject, :primary) }

        context "with a requested subject" do
          let(:course) { create(:course, subjects: [primary]) }
          it { is_expected.to include(course) }
        end

        context "without a requested subject" do
          let(:course) { create(:course, :secondary, subjects: [build(:secondary_subject, :science)]) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "provider_name" do
      context "= test" do
        let(:filter) { { "provider.provider_name": provider_name } }
        let(:provider_name) { "Darren" }
        let(:provider) { create(:provider, provider_name: provider_name) }

        context "when a course has a matching provider" do
          let(:course) { create(:course, provider: provider) }
          it { is_expected.to include(course) }
        end

        context "when a course does not have a matching provider" do
          let(:course) { create(:course) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "send_courses" do
      context "= true" do
        let(:filter) { { send_courses: true } }

        context "when a course is SEND" do
          let(:course) { create(:course, :send) }
          it { is_expected.to include(course) }
        end

        context "when a course is not SEND" do
          let(:course) { create(:course) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "funding_types" do
      context "= apprenticeship" do
        let(:filter) { { funding_type: "apprenticeship" } }

        context "course has an apprenticeship funding type" do
          let(:course) { create(:course, :with_apprenticeship) }
          it { is_expected.to include(course) }
        end

        context "course does not have an apprenticeship funding type" do
          let(:course) { create(:course, :with_salary) }
          it { is_expected.not_to include(course) }
        end
      end
    end

    describe "locations" do
      let(:course) { create(:course) }
      let(:sefton_park) { { latitude: 53.380393, longitude: -2.940340 } }
      let(:filter) { sefton_park.merge(radius: 5) }

      context "course within radius of lat:lng" do
        let(:lark_lane) { { latitude: 53.381707, longitude: -2.945094 } }
        let(:site) { build(:site, latitude: lark_lane[:latitude], longitude: lark_lane[:longitude]) }

        before do
          course.sites << site
        end

        it { is_expected.to include(course) }
      end

      context "course not within radius of lat:lng" do
        let(:site) { build(:site, latitude: 2, longitude: 1) }
        it { is_expected.not_to include(course) }
      end
    end

    describe "when passed a scope" do
      subject { described_class.call(filter: filter, course_scope: provider.courses) }

      let(:provider) { create(:provider) }
      let(:course) { build(:course) }
      let(:filter) { {} }

      context "a course in the scope" do
        before do
          provider.courses << course
        end

        it { is_expected.to include(course) }
      end

      context "a course not in the scope" do
        it { is_expected.not_to include(course) }
      end
    end

    describe "pagination" do
      let(:filter) { {} }

      before do
        12.times do
          create(:course)
        end
      end

      it "returns 10 records" do
        expect(subject.limit(10).offset(0).count).to eq(10)
      end
    end
  end
end
