class Course < ApplicationRecord
  include Discard::Model
  include WithQualifications
  include ChangedAt
  include Courses::EditOptions
  include StudyModeVacancyMapper
  include TimeFormat

  after_initialize :set_defaults

  before_discard do
    raise "You cannot delete the running course #{self}" unless ucas_status == :new
  end

  has_associated_audits
  audited

  validates :course_code,
            uniqueness: { scope: :provider_id },
            on: %i[create update]

  enum program_type: {
    higher_education_programme: "HE",
    school_direct_training_programme: "SD",
    school_direct_salaried_training_programme: "SS",
    scitt_programme: "SC",
    pg_teaching_apprenticeship: "TA",
  }

  enum study_mode: {
    full_time: "F",
    part_time: "P",
    full_time_or_part_time: "B",
  }

  enum level: {
    primary: "Primary",
    secondary: "Secondary",
    further_education: "Further education",
  }, _suffix: :course

  ENTRY_REQUIREMENT_OPTIONS = {
    must_have_qualification_at_application_time: 1,
    expect_to_achieve_before_training_begins: 2,
    equivalence_test: 3,
    not_required: 9,
    not_set: nil,
  }.freeze

  enum maths: ENTRY_REQUIREMENT_OPTIONS, _suffix: :for_maths
  enum english: ENTRY_REQUIREMENT_OPTIONS, _suffix: :for_english
  enum science: ENTRY_REQUIREMENT_OPTIONS, _suffix: :for_science

  before_save :set_applications_open_from

  belongs_to :provider

  belongs_to :accrediting_provider,
             ->(c) { where(recruitment_cycle: c.recruitment_cycle) },
             class_name: "Provider",
             foreign_key: :accredited_body_code,
             primary_key: :provider_code,
             inverse_of: :accredited_courses,
             optional: true

  has_many :course_subjects,
           -> { order :position },
           inverse_of: :course,
           before_add: :set_subject_position

  def set_subject_position(course_subject)
    return unless course_subject.subject.secondary_subject?

    secondary_course_subjects = course_subjects.select { |cs| cs.subject.secondary_subject? }

    return unless secondary_course_subjects.all? { |cs| cs.position.present? }

    course_subject.position = if secondary_course_subjects.any?
                                secondary_course_subjects.last.position + 1
                              else
                                0
                              end
  end

  has_many :subjects, through: :course_subjects
  has_many :financial_incentives, through: :subjects
  has_many :site_statuses
  has_many :sites,
           -> { distinct.merge(SiteStatus.where(status: %i[new_status running])) },
           through: :site_statuses

  has_many :modern_languages_subjects,
           through: :course_subjects,
           source: :subject,
           class_name: "ModernLanguagesSubject"

  has_many :enrichments, class_name: "CourseEnrichment" do
    def find_or_initialize_draft
      # This is a ruby search as opposed to an AR search, because calling `draft`
      # will return a new instance of a CourseEnrichment object which is different
      # to the ones in the cached `enrichments` association. This makes checking
      # for validations later down non-trivial.
      latest_draft_enrichment = select(&:draft?).last

      latest_draft_enrichment || new(new_draft_attributes)
    end

    def new_draft_attributes
      latest_published_enrichment = most_recent.published.first

      if latest_published_enrichment.present?
        latest_published_enrichment_attributes = latest_published_enrichment
          .dup
          .attributes
          .with_indifferent_access
          .except(:json_data)

        latest_published_enrichment_attributes[:status] = :draft
        latest_published_enrichment_attributes
      else
        { status: :draft }.with_indifferent_access
      end
    end
  end

  has_one :latest_published_enrichment, -> { published.order("created_at DESC, id DESC").limit(1) },
          class_name: "CourseEnrichment"

  scope :within, ->(range, origin:) do
    joins(:sites).merge(Site.within(range, origin: origin))
  end

  scope :by_distance, ->(origin:) do
    joins(:sites).merge(Site.by_distance(origin: origin))
  end

  scope :by_name_ascending, -> do
    order(name: :asc)
  end

  scope :by_name_descending, -> do
    order(name: :desc)
  end

  scope :ascending_canonical_order, -> do
    joins(:provider).merge(Provider.by_name_ascending).order("name asc, course_code asc")
  end

  scope :descending_canonical_order, -> do
    joins(:provider).merge(Provider.by_name_descending).order("name desc, course_code desc")
  end

  scope :accredited_body_order, ->(provider_name) do
    joins(:provider).merge(Provider.by_provider_name(provider_name))
  end

  scope :changed_since, ->(timestamp) do
    if timestamp.present?
      changed_at_since(timestamp)
    else
      where.not(changed_at: nil)
    end.order(:changed_at, :id)
  end

  scope :changed_at_since, ->(timestamp) do
    where("course.changed_at > ?", timestamp)
  end

  scope :created_at_since, ->(timestamp) do
    where("course.created_at > ?", timestamp)
  end

  scope :not_new, -> do
    includes(site_statuses: %i[site course])
      .where
      .not(SiteStatus.table_name => { status: SiteStatus.statuses[:new_status] })
  end

  scope :published, -> do
    where(id: CourseEnrichment.published.select(:course_id))
  end

  scope :with_recruitment_cycle, ->(year) { joins(provider: :recruitment_cycle).where(recruitment_cycle: { year: year }) }
  scope :findable, -> { joins(:site_statuses).merge(SiteStatus.findable) }
  scope :with_vacancies, -> { joins(:site_statuses).merge(SiteStatus.with_vacancies) }
  scope :with_salary, -> { where(program_type: %i[school_direct_salaried_training_programme pg_teaching_apprenticeship]) }
  scope :with_study_modes, ->(study_modes) do
    where(study_mode: Array(study_modes) << "full_time_or_part_time")
  end
  scope :with_subjects, ->(subject_codes) do
    joins(:subjects).merge(Subject.with_subject_codes(subject_codes))
  end

  scope :with_qualifications, ->(qualifications) do
    where(qualification: qualifications)
  end

  scope :with_accredited_bodies, ->(accredited_body_codes) do
    where(accredited_body_code: accredited_body_codes)
  end

  scope :with_provider_name, ->(provider_name) do
    where(
      provider_id: Provider.where(provider_name: provider_name),
    ).or(
      self.where(
        accredited_body_code: Provider.where(provider_name: provider_name)
                                       .select(:provider_code),
      ),
    )
  end

  scope :with_send, -> do
    where(is_send: true)
  end

  scope :with_funding_types, ->(funding_types) do
    program_types = []

    if funding_types.include?("salary")
      program_types << :school_direct_salaried_training_programme
    end

    if funding_types.include?("apprenticeship")
      program_types << :pg_teaching_apprenticeship
    end

    if funding_types.include?("fee")
      %i[
        higher_education_programme
        scitt_programme
        school_direct_training_programme
      ].each do |program_type|
        program_types << program_type
      end
    end

    where(program_type: program_types)
  end

  def self.entry_requirement_options_without_nil_choice
    ENTRY_REQUIREMENT_OPTIONS.reject { |option| option == :not_set }.keys.map(&:to_s)
  end

  validates :maths,   inclusion: { in: entry_requirement_options_without_nil_choice }, unless: :further_education_course?
  validates :english, inclusion: { in: entry_requirement_options_without_nil_choice }, unless: :further_education_course?
  validates :science, inclusion: { in: entry_requirement_options_without_nil_choice }, if: :gcse_science_required?
  validates :is_send, inclusion: { in: [true, false] }
  validates :sites, presence: true, on: %i[publish new]
  validates :subjects, presence: true, on: :publish
  validate :validate_enrichment_publishable, on: :publish
  validate :validate_site_statuses_publishable, on: :publish
  validate :validate_enrichment
  validate :validate_qualification, on: %i[update new]
  validate :validate_start_date, on: :update, if: -> { provider.present? && start_date.present? }
  validate :validate_applications_open_from, on: %i[update new], if: -> { provider.present? }
  validate :validate_modern_languages
  validate :validate_has_languages, if: :has_the_modern_languages_secondary_subject_type?
  validate :validate_subject_count
  validate :validate_subject_consistency
  validate :validate_custom_age_range, on: %i[create new], if: -> { age_range_in_years.present? }
  validates_with UniqueCourseValidator, on: :new

  validates :name, :profpost_flag, :program_type, :qualification, :start_date, :study_mode, presence: true
  validates :age_range_in_years, presence: true, on: %i[new create publish], unless: :further_education_course?
  validates :level, presence: true, on: %i[new create publish]

  after_validation :remove_unnecessary_enrichments_validation_message

  def update_notification_attributes
    %w[name age_range_in_years qualification study_mode maths english science]
  end

  def self.get_by_codes(year, provider_code, course_code)
    RecruitmentCycle.find_by(year: year)
      .providers.find_by(provider_code: provider_code)
      .courses.find_by(course_code: course_code)
  end

  def recruitment_cycle
    provider.recruitment_cycle
  end

  def generate_name
    services[:generate_course_name].execute(course: self)
  end

  def accrediting_provider_description
    return nil if accrediting_provider.blank?
    return nil if provider.accrediting_provider_enrichments.blank?

    accrediting_provider_enrichment = provider.accrediting_provider_enrichments
      .find do |provider|
      provider.UcasProviderCode == accrediting_provider.provider_code
    end

    accrediting_provider_enrichment.Description if accrediting_provider_enrichment.present?
  end

  def publishable?
    valid? :publish
  end

  def update_valid?
    valid? :update
  end

  def findable?
    findable_site_statuses.any?
  end

  def findable_site_statuses
    if site_statuses.loaded?
      site_statuses.select(&:findable?)
    else
      site_statuses.findable
    end
  end

  def syncable_subjects
    if subjects.loaded?
      subjects
        .reject { |s| s.type == "DiscontinuedSubject" }
        .select { |s| s.subject_code.present? }
    else
      subjects
        .where.not(type: "DiscontinuedSubject")
        .where.not(subject_code: nil)
    end
  end

  def open_for_applications?
    applications_open_from.present? && applications_open_from <= Time.now.utc && findable?
  end

  def has_vacancies?
    if site_statuses.loaded?
      site_statuses.select(&:findable?).select(&:with_vacancies?).any?
    else
      site_statuses.findable.with_vacancies.any?
    end
  end

  def update_changed_at(timestamp: Time.now.utc)
    # Changed_at represents changes to related records as well as course
    # itself, so we don't want to alter the semantics of updated_at which
    # represents changes to just the course record.
    update_columns changed_at: timestamp
  end

  def study_mode_description
    study_mode.to_s.tr("_", " ")
  end

  def program_type_description
    if school_direct_salaried_training_programme? then " with salary"
    elsif pg_teaching_apprenticeship? then " teaching apprenticeship"
    else ""
    end
  end

  def description
    study_mode_string = (full_time_or_part_time? ? ", " : " ") +
      study_mode_description
    qualifications_description + study_mode_string + program_type_description
  end

  def content_status
    services[:content_status].execute(enrichment: latest_enrichment, recruitment_cycle: recruitment_cycle)
  end

  def ucas_status
    return :running if findable?
    return :new if site_statuses.empty? || site_statuses.any?(&:status_new_status?)

    :not_running
  end

  def funding_type
    return nil if program_type.nil?

    if school_direct_salaried_training_programme?
      "salary"
    elsif pg_teaching_apprenticeship?
      "apprenticeship"
    else
      "fee"
    end
  end

  def is_fee_based?
    funding_type == "fee"
  end

  # https://www.gov.uk/government/publications/initial-teacher-training-criteria/initial-teacher-training-itt-criteria-and-supporting-advice#c11-gcse-standard-equivalent
  def gcse_subjects_required
    case level
    when "primary"
      %w[maths english science]
    when "secondary"
      %w[maths english]
    else
      []
    end
  end

  def gcse_science_required?
    gcse_subjects_required.include?("science")
  end

  def last_published_at
    latest_enrichment&.last_published_timestamp_utc
  end

  def publish_sites
    site_statuses.status_new_status.each(&:start!)
    site_statuses.status_running.unpublished_on_ucas.each(&:published_on_ucas!)
  end

  def publish_enrichment(current_user)
    enrichments.draft.each do |enrichment|
      enrichment.publish(current_user)
    end
  end

  def sites=(desired_sites)
    existing_sites = sites

    if persisted?
      to_add = desired_sites - existing_sites
      to_add.each { |site| add_site!(site: site) }

      to_remove = existing_sites - desired_sites
      to_remove.each { |site| remove_site!(site: site) }

      sites.reload
    else
      super(desired_sites)
    end
  end

  def has_bursary?
    financial_incentives.any?(&:bursary_amount?)
  end

  def has_scholarship_and_bursary?
    financial_incentives.any?(&:scholarship?) && financial_incentives.any?(&:bursary_amount?)
  end

  def has_scholarship?
    financial_incentives.any?(&:scholarship?)
  end

  def has_early_career_payments?
    financial_incentives.any?(&:early_career_payments?)
  end

  def bursary_amount
    financial_incentives&.first&.bursary_amount
  end

  def scholarship_amount
    financial_incentives&.first&.scholarship
  end

  def self_accredited?
    provider.accredited_body?
  end

  def to_s
    "#{name} (#{provider.provider_code}/#{course_code}) [#{recruitment_cycle}]"
  end

  def next_recruitment_cycle?
    recruitment_cycle.year > RecruitmentCycle.current_recruitment_cycle.year
  end

  # Ideally this would just use the validation, but:
  # https://github.com/rails/rails/issues/13971
  def course_params_assignable(course_params)
    assignable_after_publish(course_params) &&
      entry_requirements_assignable(course_params) &&
      qualification_assignable(course_params)
  end

  def is_published?
    %i{published published_with_unpublished_changes}.include? content_status
  end

  def funding_type=(funding_type)
    assign_program_type_service = Courses::AssignProgramTypeService.new
    assign_program_type_service.execute(funding_type, self)
  end

  def ensure_site_statuses_match_study_mode
    site_statuses.not_no_vacancies.each do |site_status|
      update_vac_status(study_mode, site_status)
    end
  end

  def withdraw
    if is_published?
      site_statuses.each do |site_status|
        site_status.update(vac_status: :no_vacancies, status: :suspended)
      end

      withdraw_latest_enrichment
    else
      errors.add(:withdraw, "Courses that have not been published should be deleted not withdrawn")
    end
  end

  def assignable_master_subjects
    services[:assignable_master_subjects].execute(course: self)
  end

  def assignable_subjects
    services[:assignable_subjects].execute(course: self)
  end

  def in_current_cycle?
    recruitment_cycle.current?
  end

  def age_minimum
    return if age_range_in_years.blank?

    age_range_in_years.split("_").first.to_i
  end

  def age_maximum
    return if age_range_in_years.blank?

    age_range_in_years.split("_").last.to_i
  end

  def bursary_requirements
    return [] unless has_bursary?

    requirements = [I18n.t("course.values.bursary_requirements.second_degree")]
    mathematics_requirement = I18n.t("course.values.bursary_requirements.maths")

    if subjects.include?(PrimarySubject.find_by(subject_name: "Primary with mathematics"))
      requirements.push(mathematics_requirement)
    end

    requirements
  end

private

  def add_site!(site:)
    is_course_new = ucas_status == :new
    site_status = site_statuses.find_or_initialize_by(site: site)
    site_status.start! unless is_course_new
    site_status.save!
  end

  def remove_site!(site:)
    site_status = site_statuses.find_by!(site: site)
    ucas_status == :new ? site_status.destroy! : site_status.suspend!
  end

  def withdraw_latest_enrichment
    latest_enrichment.withdraw
  end

  def latest_enrichment
    enrichments.max_by(&:created_at)
  end

  def assignable_after_publish(course_params)
    relevant_params = course_params.slice(:is_send, :applications_open_from, :application_start_date)

    return true if relevant_params.empty? || !is_published?

    relevant_params.each do |field, _value|
      errors.add(field.to_sym, "cannot be changed after publish")
    end
    false
  end

  def entry_requirements_assignable(course_params)
    relevant_params = course_params.slice(:maths, :english, :science)

    invalid_params = relevant_params.select do |_subject, value|
      value && !ENTRY_REQUIREMENT_OPTIONS.key?(value.to_sym)
    end
    invalid_params.each do |subject, _value|
      errors.add(subject.to_sym, "is invalid")
    end

    invalid_params.empty?
  end

  def qualification_assignable(course_params)
    assignable = course_params[:qualification].nil? || Course::qualifications.include?(course_params[:qualification].to_sym)
    errors.add(:qualification, "is invalid") unless assignable

    assignable
  end

  def add_enrichment_errors(enrichment)
    enrichment.errors.messages.map do |field, _error|
      # `full_messages_for` here will remove any `^`s defined in the validator or en.yml.
      # We still need it for later, so re-add it.
      # jsonapi_errors will throw if it's given an array, so we call `.first`.
      message = "^" + enrichment.errors.full_messages_for(field).first.to_s
      errors.add field.to_sym, message
    end
  end

  def validate_enrichment
    latest_enrichment = enrichments.select(&:draft?).last
    return if latest_enrichment.blank?

    latest_enrichment.valid?
    add_enrichment_errors(latest_enrichment)
  end

  def validate_enrichment_publishable
    if enrichments.blank?
      temp_enrichment = CourseEnrichment.new(course: self, status: "draft")
      temp_enrichment.valid?(:publish)
      add_enrichment_errors(temp_enrichment)
    else
      latest_enrichment = enrichments.select(&:draft?).last

      if latest_enrichment
        latest_enrichment.valid?(:publish)
        add_enrichment_errors(latest_enrichment)
      end
    end
  end

  def validate_site_statuses_publishable
    site_statuses.each do |site_status|
      unless site_status.valid?
        raise RuntimeError.new("Site status invalid on course #{provider.provider_code}/#{course_code}: #{site_status.errors.full_messages.first}")
      end
    end
  end

  def set_defaults
    self.modular ||= ""
  end

  def remove_unnecessary_enrichments_validation_message
    self.errors.delete :enrichments if self.errors[:enrichments] == ["is invalid"]
  end

  def validate_qualification
    if qualification.blank?
      errors.add(:qualification, :blank)
    else
      errors.add(:qualification, "^#{qualifications_description} is not valid for a #{level.to_s.humanize.downcase} course") unless qualification.in?(qualification_options)
    end
  end

  def set_applications_open_from
    self.applications_open_from ||= recruitment_cycle.application_start_date
  end

  def validate_start_date
    errors.add :start_date, "#{start_date.strftime('%B %Y')} is not in the #{recruitment_cycle.year} cycle" unless start_date_options.include?(written_month_year(start_date))
  end

  def validate_applications_open_from
    if applications_open_from.blank?
      errors.add(:applications_open_from, :blank)
    elsif !valid_date_range.include?(applications_open_from)
      chosen_date = short_date(applications_open_from)
      start_date = short_date(recruitment_cycle.application_start_date)
      end_date = short_date(recruitment_cycle.application_end_date)
      errors.add(
        :applications_open_from,
        "#{chosen_date} is not valid for the #{provider.recruitment_cycle.year} cycle. " +
        "A valid date must be between #{start_date} and #{end_date}",
      )
    end
  end

  def validate_modern_languages
    if has_any_modern_language_subject_type? && !has_the_modern_languages_secondary_subject_type?
      errors.add(:subjects, "Modern languages subjects must also have the modern_languages subject")
    end
  end

  def validate_site_status_findable
    unless findable?
      errors.add(:site_statuses, "must be findable")
    end
  end

  def has_any_modern_language_subject_type?
    subjects.any? { |subject| subject.type == "ModernLanguagesSubject" }
  end

  def has_the_modern_languages_secondary_subject_type?
    raise "SecondarySubject not found" if SecondarySubject == nil
    raise "SecondarySubject.modern_languages not found" if SecondarySubject.modern_languages == nil

    subjects.any? { |subject| subject&.id == SecondarySubject.modern_languages.id }
  end

  def validate_has_languages
    unless has_any_modern_language_subject_type?
      errors.add(:modern_languages_subjects, :select_a_language)
    end
  end

  def validate_subject_count
    if subjects.empty?
      errors.add(:subjects, :course_creation)
      return
    end

    case level
    when "primary", "further_education"
      if subjects.count > 1
        errors.add(:subjects, "has too many subjects")
      end
    when "secondary"
      if subjects.count > 2 && !has_any_modern_language_subject_type?
        errors.add(:subjects, "has too many subjects")
      end
    end
  end

  def validate_subject_consistency
    subjects_excluding_discontinued = subjects.reject do |subject|
      DiscontinuedSubject.exists?(id: subject.id)
    end

    return if subjects_excluding_discontinued.empty?

    case level
    when "primary"
      unless PrimarySubject.exists?(id: subjects_excluding_discontinued.map(&:id))
        errors.add(:subjects, "must be primary")
      end
    when "secondary"
      unless SecondarySubject.exists?(id: subjects_excluding_discontinued.map(&:id))
        errors.add(:subjects, "must be secondary")
      end
    when "further_education"
      unless FurtherEducationSubject.exists?(id: subjects_excluding_discontinued.map(&:id))
        errors.add(:subjects, "must be further education")
      end
    end
  end

  def validate_custom_age_range
    Courses::ValidateCustomAgeRangeService.new.execute(age_range_in_years, self)
  end

  def valid_date_range
    recruitment_cycle.application_start_date..recruitment_cycle.application_end_date
  end

  def services
    return @services if @services.present?

    @services = Dry::Container.new
    @services.register(:generate_course_name) do
      Courses::GenerateCourseNameService.new
    end
    @services.register(:assignable_master_subjects) do
      Courses::AssignableMasterSubjectService.new
    end
    @services.register(:assignable_subjects) do
      Courses::AssignableSubjectService.new
    end
    @services.register(:content_status) do
      Courses::ContentStatusService.new
    end
  end
end
