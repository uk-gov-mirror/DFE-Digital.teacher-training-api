# frozen_string_literal: true

module PageObjects
  module Support
    class UserShow < PageObjects::Base
      set_url "/support/users/{id}"

      sections :providers, PageObjects::Sections::Provider, ".qa-provider_row"
    end
  end
end
