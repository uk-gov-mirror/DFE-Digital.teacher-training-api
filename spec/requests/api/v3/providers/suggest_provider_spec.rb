require "rails_helper"

describe "GET /provider-suggestions" do
  let(:jsonapi_renderer) { JSONAPI::Serializable::Renderer.new }
  let(:courses) { [build(:course, site_statuses: [build(:site_status, :findable)])] }
  let(:courses2) { [build(:course, site_statuses: [build(:site_status, :findable)])] }
  let(:provider) { create(:provider, provider_name: "PROVIDER 1", courses: courses, latitude: 51.482578, longitude: -0.007659) }
  let(:provider2) { create(:provider, provider_name: "PROVIDER 2", courses: courses2, latitude: 52.482578, longitude: -0.107659) }

  context "current recruitment cycle" do
    before do
      provider
      provider2
    end

    it "searches for a particular provider" do
      get "/api/v3/provider-suggestions?query=#{provider.provider_name}"

      expect(JSON.parse(response.body)["data"]).
          to match_array([
                             {
                                 "id" => provider.id.to_s,
                                 "type" => "providers",
                                 "attributes" => {
                                     "provider_code" => provider.provider_code,
                                     "provider_name" => provider.provider_name,
                                     "provider_type" => provider.provider_type,
                                     "latitude" => provider.latitude,
                                     "longitude" => provider.longitude,
                                     "recruitment_cycle_year" => provider.recruitment_cycle.year,
                                 },
                             },
                         ])
    end

    it "searches for a partial provider" do
      get "/api/v3/provider-suggestions?query=#{provider2.provider_name[0..3]}"

      expect(JSON.parse(response.body)["data"]).
          to match_array([
                             {
                                 "id" => provider.id.to_s,
                                 "type" => "providers",
                                 "attributes" => {
                                     "provider_code" => provider.provider_code,
                                     "provider_name" => provider.provider_name,
                                     "provider_type" => provider.provider_type,
                                     "latitude" => provider.latitude,
                                     "longitude" => provider.longitude,
                                     "recruitment_cycle_year" => provider.recruitment_cycle.year,
                                 },
                             },
                             {
                                 "id" => provider2.id.to_s,
                                 "type" => "providers",
                                 "attributes" => {
                                     "provider_code" => provider2.provider_code,
                                     "provider_name" => provider2.provider_name,
                                     "provider_type" => provider2.provider_type,
                                     "latitude" => provider2.latitude,
                                     "longitude" => provider2.longitude,
                                     "recruitment_cycle_year" => provider2.recruitment_cycle.year,
                                 },
                             },
                         ])
    end
  end

  context "next recruitment cycle" do
    it "searches for a provider" do
      next_recruitment_cycle = find_or_create(:recruitment_cycle, :next)
      provider = create(:provider, recruitment_cycle: next_recruitment_cycle)

      get "/api/v3/provider-suggestions?query=#{provider.provider_name}"

      expect(JSON.parse(response.body)["data"]).to match_array([])
    end
  end

  it "limits responses to a maximum of 10 items" do
    11.times do
      courses = [build(:course, site_statuses: [build(:site_status, :findable)])]
      create(:provider, provider_name: "provider X", courses: courses)
    end

    get "/api/v3/provider-suggestions?query=provider"

    expect(JSON.parse(response.body)["data"].length).to eq(10)
  end

  it "returns status: bad request (400) if query is empty" do
    get "/api/v3/provider-suggestions"

    expect(response.status).to eq(400)
  end

  it "returns status: bad request (400) if query is too short" do
    provider

    get "/api/v3/provider-suggestions?query=#{provider.provider_name[0, 2]}"

    expect(response.status).to eq(400)
  end

  it "returns status: success (200) if start of query is not alphanumeric" do
    get "/api/v3/provider-suggestions?query=%22%22%22%22"

    expect(response.status).to eq(200)
  end
end
