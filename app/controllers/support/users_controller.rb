module Support
  class UsersController < ApplicationController
    def index
      @users = provider.users.order(:last_name)
      render layout: "provider_record"
    end

    def show
      @providers = providers.order(:provider_name).page(params[:page] || 1)
    end

  private

    def provider
      @provider ||= Provider.find(params[:provider_id])
    end

    def user
      @user ||= User.find(params[:id])
    end

    def providers
      RecruitmentCycle.current.providers.where(id: user.providers)
    end
  end
end
