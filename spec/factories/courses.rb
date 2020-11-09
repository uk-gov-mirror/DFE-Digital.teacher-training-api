FactoryBot.define do
  factory :course do
    sequence(:course_code) { |n| "C#{n}#{(0..9).to_a.sample(2).join}" }
    name { Faker::Lorem.word }
    qualification { :pgce_with_qts }
    with_apprenticeship

    association :provider

    study_mode { :full_time }
    maths { :must_have_qualification_at_application_time }
    english { :must_have_qualification_at_application_time }
    science { :must_have_qualification_at_application_time }
    level { :primary }
    age_range_in_years { "3_to_7" }
    resulting_in_pgce_with_qts
    start_date { DateTime.new(provider.recruitment_cycle.year.to_i, 9, 1) }
    applications_open_from {
      Faker::Time.between(
        from: DateTime.new(provider.recruitment_cycle.year.to_i - 1, 10, 1),
        to: DateTime.new(provider.recruitment_cycle.year.to_i, 9, 29),
      )
    }

    trait :without_validation do
      to_create { |instance| instance.save(validate: false) }
    end

    trait :primary do
      level { :primary }
      age_range_in_years { "3_to_7" }
    end

    trait :secondary do
      age_range_in_years { "11_to_18" }
      level { :secondary }
    end

    transient do
      age { nil }
      infer_level? { false }
      infer_subjects? { true }
    end

    after(:build) do |course, evaluator|
      if evaluator.age.present?
        course.created_at = evaluator.age
        course.updated_at = evaluator.age
        course.changed_at = evaluator.age
      end

      if evaluator.infer_subjects? && course.subjects.empty?
        if course.level == "primary"
          course.subjects << find_or_create(:primary_subject, :primary)
        elsif course.level == "secondary"
          course.subjects << find_or_create(:secondary_subject, :science)
        elsif course.level == "further_education"
          course.subjects << find_or_create(:further_education_subject)
        end
      end

      if evaluator.infer_level? && course.subjects.present?
        subjects = course.subjects
          .reject { |s| s.type == "DiscontinuedSubject" }
          .reject { |s| s.type == "MordernLanguagesSubject" }

        if subjects.all? do |subject| subject.type == "PrimarySubject" end
          course.level = "primary"
        elsif subjects.all? do |subject| subject.type == "SecondarySubject" end
          course.level = "secondary"
        elsif subjects.all? do |subject| subject.type == "FurtherEducationSubject" end
          course.level = "further_education"
        end
      end

      if course.subjects.any? && course.name.blank?
        course.name = course.generate_name
      end
    end

    after(:create) do |course, evaluator|
      # This is important to retain the relationship behaviour between
      # course and it's enrichment
      if evaluator.age.present?
        course.created_at = evaluator.age
        course.updated_at = evaluator.age
        course.changed_at = evaluator.age
      end

      if course.subjects.any? && course.name.blank?
        course.name = course.generate_name
      end

      # We've just created a course with this provider's code, so ensure it's
      # up-to-date and has this course loaded.
      course.provider.reload
    end

    trait :infer_level do
      transient do
        infer_level? { true }
      end
    end

    trait :dont_infer_subjects do
      transient do
        infer_subjects? { false }
      end
    end

    trait :resulting_in_qts do
      qualification { :qts }
    end

    trait :resulting_in_pgce_with_qts do
      qualification { :pgce_with_qts }
    end

    trait :resulting_in_pgde_with_qts do
      qualification { :pgde_with_qts }
    end

    trait :resulting_in_pgce do
      qualification { :pgce }
    end

    trait :resulting_in_pgde do
      qualification { :pgde }
    end

    trait :self_accredited do
      association(:provider, factory: %i[provider accredited_body])
    end

    trait :with_accrediting_provider do
      association(:accrediting_provider, factory: %i[provider accredited_body])
    end

    trait :with_higher_education do
      program_type { :higher_education_programme }
    end

    trait :with_school_direct do
      program_type { :school_direct_training_programme }
    end

    trait :with_scitt do
      program_type { :scitt_programme }
    end

    trait :with_apprenticeship do
      program_type { :pg_teaching_apprenticeship }
    end

    trait :with_salary do
      program_type { :school_direct_salaried_training_programme }
    end

    trait :fee_type_based do
      program_type {
        %i[higher_education_programme school_direct_training_programme
           scitt_programme].sample
      }
    end

    trait :salary_type_based do
      program_type { %i[pg_teaching_apprenticeship school_direct_salaried_training_programme].sample }
    end

    trait :non_salary_type_based do
      program_type { %i[scitt_programme higher_education_programme school_direct_training_programme].sample }
    end

    trait :applications_open_from_not_set do
      applications_open_from { nil }
    end

    trait :deleted do
      discarded_at { Time.zone.now - 1.day }
    end

    trait :skip_validate do
      to_create { |instance| instance.save(validate: false) }
    end

    trait :unpublished do
      transient do
        identifier { "unpublished" }
      end

      name { "#{identifier} course name" }

      provider { find_or_create :provider, :published_scitt }
      sites { build_list(:site, 1, provider: provider) }
    end

    trait :draft_enrichment do
      enrichments { [build(:course_enrichment, :initial_draft, course: nil)] }
    end

    trait :with_vacancies do
      site_statuses { [create(:site_status, :findable, :full_time_vacancies)] }
    end

    trait :without_vacancies do
      site_statuses { [build(:site_status, :findable, :with_no_vacancies)] }
    end

    trait :part_time do
      study_mode { :part_time }
    end

    trait :full_time do
      study_mode { :full_time }
    end

    trait :send do
      is_send { true }
    end
  end
end
