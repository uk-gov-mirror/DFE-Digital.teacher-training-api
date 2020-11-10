class CourseOrderingService
  include ServicePattern

  def initialize(filter:, sort:, course_scope:)
    @filter = filter || {}
    @sort = Set.new(sort&.split(","))
    @course_scope = deduplicate_scope(course_scope)
  end

  def call
    if sort_by_provider_name_with_delivering_first_then_accredited_body_for?
      result_scope = order_by_delivering_then_accredited_body_for(course_scope)
      return order_ascending(result_scope)
    end

    return order_canonically_ascending if sort_canonically_ascending?
    return order_canonically_descending if sort_canonically_descending?
    return order_by_distance if sort_by_distance?

    course_scope
  end

private

  def deduplicate_scope(scope)
    return Course.where(id: scope.select(:id)) if sort.include?("provider.provider_name") ||
      filter["provider.provider_name"].present?

    scope.distinct
  end

  attr_reader :filter, :sort, :course_scope
  attr_accessor :result_scope

  def order_ascending(scope)
    scope.ascending_canonical_order
  end

  def order_by_delivering_then_accredited_body_for(scope)
    scope.accredited_body_order(provider_name)
  end

  def order_canonically_ascending
    result_scope = course_scope
    order_ascending(result_scope)
  end

  def order_canonically_descending
    result_scope = course_scope
    result_scope = result_scope.descending_canonical_order
    result_scope.select("provider.provider_name", "course.*")
  end

  def order_by_distance
    expand_university? ? order_by_boosted_distance : order_by_actual_distance
  end

  def order_by_actual_distance
    result_scope = distance_scope.select("course.*, distance")
    result_scope.order(:distance)
  end

  def order_by_boosted_distance
    result_scope = distance_scope.select("course.*, distance, #{distance_with_university_area_adjustment}")
    result_scope.order(:boosted_distance)
  end

  def distance_scope
    result_scope = course_scope
    result_scope = result_scope.joins(courses_with_distance_from_origin)
    result_scope.joins(:provider)
  end

  def sort_by_provider_name_with_delivering_first_then_accredited_body_for?
    provider_name.present?
  end

  def sort_canonically_ascending?
    sort == Set["name", "provider.provider_name"]
  end

  def sort_canonically_descending?
    sort == Set["-name", "-provider.provider_name"]
  end

  def sort_by_distance?
    sort == Set["distance"]
  end

  def provider_name
    return [] if filter[:"provider.provider_name"].blank?

    filter[:"provider.provider_name"]
  end

  def courses_with_distance_from_origin
    # grab courses table and join with the above result set
    # so distances from origin are now available
    # we can then sort by distance from the given origin
    courses_table = Course.arel_table
    courses_table.join(distance_table).on(courses_table[:id].eq(distance_table[:course_id])).join_sources
  end

  def course_id_with_lowest_locatable_distance
    # select course_id and nearest site with shortest distance from origin
    # as courses may have multiple sites
    # this will remove duplicates by aggregating on course_id
    origin_lat_long = OpenStruct.new(lat: origin[0], lng: origin[1])
    lowest_locatable_distance = Arel.sql("MIN#{Site.distance_sql(origin_lat_long)} as distance")
    locatable_sites.project(:course_id, lowest_locatable_distance).group(:course_id)
  end

  def distance_table
    # form a temporary table with results
    Arel::Nodes::TableAlias.new(
      Arel.sql(
        format("(%s)", course_id_with_lowest_locatable_distance.to_sql),
      ), "distances"
    )
  end

  def distance_with_university_area_adjustment
    university_provider_type = Provider.provider_types[:university]
    university_location_area_radius = 10
    <<~EOSQL.gsub(/\s+/m, " ").strip
      (CASE
        WHEN provider.provider_type = '#{university_provider_type}'
          THEN (distance - #{university_location_area_radius})
        ELSE distance
      END) as boosted_distance
    EOSQL
  end

  def locatable_sites
    site_status = SiteStatus.arel_table
    sites = Site.arel_table

    # Only running and published site statuses
    running_and_published_criteria = site_status[:status]
      .eq(SiteStatus.statuses[:running])
      .and(site_status[:publish]
      .eq(SiteStatus.publishes[:published]))

    # we only want sites that have been geocoded
    has_been_geocoded_criteria = sites[:latitude].not_eq(nil).and(sites[:longitude].not_eq(nil))

    # only sites that have a locatable address
    # there are some sites with no address1 or postcode that cannot be
    # accurately geocoded. We don't want to return these as the closest site.
    # This should be removed once the data is fixed
    locatable_address_criteria = sites[:address1].not_eq("").or(sites[:postcode].not_eq(""))

    # Create virtual table with sites and site statuses
    site_status.join(sites).on(site_status[:site_id].eq(sites[:id]))
     .where(running_and_published_criteria)
     .where(has_been_geocoded_criteria)
     .where(locatable_address_criteria)
  end

  def origin
    [filter[:latitude], filter[:longitude]]
  end

  def expand_university?
    filter[:expand_university].to_s.downcase == "true"
  end
end
