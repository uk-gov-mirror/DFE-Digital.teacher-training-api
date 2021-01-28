#PaaS
cf_space                   = "bat-staging"
paas_app_environment       = "staging"
paas_web_app_host_name     = "staging"
paas_web_app_instances     = 1
paas_web_app_memory        = 512
paas_worker_app_instances  = 1
paas_worker_app_memory     = 512
paas_postgres_service_plan = "small-11"
paas_redis_service_plan    = "tiny-5_x"
paas_app_config = {
  RAILS_ENV                = "staging"
  RAILS_SERVE_STATIC_FILES = true
}

#StatusCake
statuscake_alerts = {
  ttapi = {
    website_name   = "teacher-training-api-staging"
    website_url    = "https://staging.api.publish-teacher-training-courses.service.gov.uk/ping"
    test_type      = "HTTP"
    check_rate     = 60
    contact_group  = [188603]
    trigger_rate   = 0
    node_locations = ["UKINT", "UK1", "MAN1", "MAN5", "DUB2"]
  }
}
