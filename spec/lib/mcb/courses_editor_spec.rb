require 'mcb_helper'

describe MCB::CoursesEditor do
  def run_editor(*input_cmds)
    stderr = nil
    output = with_stubbed_stdout(stdin: input_cmds.join("\n"), stderr: stderr) do
      subject.run
    end
    [output, stderr]
  end

  let(:provider_code) { 'X12' }
  let(:course_code) { '3FC4' }
  let(:course_codes) { [course_code] }
  let(:email) { 'user@education.gov.uk' }
  let(:provider) { create(:provider, provider_code: provider_code) }
  let!(:course) {
    create(:course,
           provider: provider,
           course_code: course_code,
           name: 'Original name',
           maths: 'must_have_qualification_at_application_time',
           english: 'equivalence_test',
           science: 'not_required',
           program_type: 'higher_education_programme',
           qualification: 'qts',
           study_mode: 'part_time')
  }
  subject { described_class.new(provider: provider, course_codes: course_codes, requester: requester) }

  context 'when an authorised user' do
    let!(:requester) { create(:user, email: email, organisations: provider.organisations) }

    describe 'runs the editor' do
      it 'updates the course title' do
        expect { run_editor("edit title", "Mathematics", "exit") }.to change { course.reload.name }.
          from("Original name").to("Mathematics")
      end

      it 'updates the maths setting when that is valid' do
        expect { run_editor("edit maths", "equivalence_test", "exit") }.to change { course.reload.maths }.
          from("must_have_qualification_at_application_time").to("equivalence_test")
      end

      it 'updates the english setting when that is valid' do
        expect { run_editor("edit english", "must_have_qualification_at_application_time", "exit") }.to change { course.reload.english }.
          from("equivalence_test").to("must_have_qualification_at_application_time")
      end

      it 'updates the science setting when that is valid' do
        expect { run_editor("edit science", "equivalence_test", "exit") }.to change { course.reload.science }.
          from("not_required").to("equivalence_test")
      end

      it 'updates the route/program type setting when that is valid' do
        expect { run_editor("edit route", "scitt_programme", "exit") }.to change { course.reload.program_type }.
          from("higher_education_programme").to("scitt_programme")
      end

      describe "(qualifications)" do
        it 'updates the qualifications setting when that is valid' do
          expect { run_editor("edit qualifications", "pgde_with_qts", "exit") }.to change { course.reload.qualification }.
            from("qts").to("pgde_with_qts")
        end

        it 'updates the qualifications setting to pgce_with_qts by default' do
          expect { run_editor("edit qualifications", "", "exit") }.to change { course.reload.qualification }.
            from("qts").to("pgce_with_qts")
        end
      end

      describe "(study mode)" do
        it 'updates the study mode setting when that is valid' do
          expect { run_editor("edit study mode", "full_time_or_part_time", "exit") }.to change { course.reload.study_mode }.
            from("part_time").to("full_time_or_part_time")
        end

        it 'updates the study mode setting to full-time by default' do
          expect { run_editor("edit study mode", "", "exit") }.to change { course.reload.study_mode }.
            from("part_time").to("full_time")
        end
      end

      it 'does nothing upon an immediate exit' do
        expect { run_editor("exit") }.to_not change { course.reload.name }.
          from("Original name")
      end
    end

    describe 'does not specify any course codes' do
      let!(:another_course) {
        create(:course,
               provider: provider,
               course_code: "A123",
               name: 'Another name')
      }
      let(:course_codes) { [] }

      it 'edits all courses on the provider' do
        expect { run_editor("edit title", "Mathematics", "exit") }.
          to change { provider.reload.courses.order(:name).pluck(:name) }.
          from(["Another name", "Original name"]).to(%w[Mathematics Mathematics])
      end
    end

    describe 'tries to edit a non-existent course' do
      let(:course_codes) { [course_code, "ABCD"] }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError, /Couldn't find course ABCD/)
      end
    end
  end

  context 'for an unauthorised user' do
    let!(:requester) { create(:user, email: email, organisations: []) }

    it 'raises an error' do
      expect { subject }.to raise_error(Pundit::NotAuthorizedError)
    end
  end
end
