class CourseSearchService
  include ServicePattern

  attr_reader :filter
  attr_reader :course_scope

  def initialize(filter:, course_scope: Course)
    @filter = filter
    @course_scope = course_scope
  end

  def call
    scope = course_scope
    scope = scope.with_salary if funding_filter_salary?
    scope = scope.with_qualifications(qualifications) if qualifications.any?
    scope = scope.with_vacancies if has_vacancies?
    scope = scope.with_study_modes(study_types) if study_types.any?
    scope = scope.with_subjects(subject_codes) if subject_codes.any?
    scope = scope.with_provider_name(provider_name) if provider_name.present?
    scope = scope.with_send if send_courses_filter?
    scope = scope.within(filter[:radius], origin: origin) if locations_filter?
    scope = scope.with_funding_types(funding_types) if funding_types.any?

    if provider_name.present?
      Course.where(id: scope.select(:id))
    else
      scope.distinct
    end
  end

private

  def qualifications
    return [] if filter[:qualification].blank?

    filter[:qualification].split(",")
  end

  def funding_filter_salary?
    filter[:funding] == "salary"
  end

  def has_vacancies?
    filter[:has_vacancies].to_s.downcase == "true"
  end

  def study_types
    return [] if filter[:study_type].blank?

    filter[:study_type].split(",")
  end

  def subject_codes
    return [] if filter[:subjects].blank?

    filter[:subjects].split(",")
  end

  def provider_name
    return [] if filter[:"provider.provider_name"].blank?

    filter[:"provider.provider_name"]
  end

  def send_courses_filter?
    filter[:send_courses].to_s.downcase == "true"
  end

  def funding_types
    return [] if filter[:funding_type].blank?

    filter[:funding_type].split(",")
  end

  def locations_filter?
    %i[latitude longitude radius].all? { |k| filter.key? k }
  end

  def origin
    [filter[:latitude], filter[:longitude]]
  end
end
