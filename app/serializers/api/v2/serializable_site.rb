module API
  module V2
    class SerializableSite < JSONAPI::Serializable::Resource
      type "sites"

      attributes :code, :location_name, :address1, :address2,
                 :address3, :address4, :postcode, :region_code,
                 :latitude, :longitude, :travel_to_work_area,
                 :london_borough, :urn

      attribute :recruitment_cycle_year do
        @object.recruitment_cycle.year
      end
    end
  end
end
