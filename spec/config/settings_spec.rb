require "rails_helper"

describe Settings do
  describe "authentication" do
    subject do
      YAML.load_file(Rails.root.join("config/settings.yml"))
    end

    its(%w[authentication algorithm]) { should eq "HS256" }
    its(%w[authentication secret]) { should eq "<%= SecureRandom.base64 %>" }
    its(%w[current_recruitment_cycle_year]) { should eq 2021 }
    its(%w[allocation_cycle_year]) { should eq 2020 }
  end
end
