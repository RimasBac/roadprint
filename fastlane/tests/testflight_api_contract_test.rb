# Run under bundle exec: validates the exact Gemfile.lock implementation offline.
require "spaceship"
require_relative "testflight_status_test"
assert(Gem.loaded_specs.fetch("fastlane").version.to_s == "2.241.2")

class GetTransport
  attr_reader :requests
  def initialize; @requests = []; end
  def build_params(**args); args; end
  def get(path, params = nil)
    @requests << [path, params]
    Spaceship::ConnectAPI::Response.new(body: { "data" => [] })
  end
end
api = Object.new.extend(Spaceship::ConnectAPI::TestFlight::API)
transport = GetTransport.new
api.test_flight_request_client = transport
api.get_apps(filter: { bundleId: "com.rimasbac.roadprint" }, includes: nil, limit: 1).to_models
api.get_builds(filter: { app: "app", version: "3,4" }, includes: TestflightStatus::INCLUDES, sort: "-uploadedDate", limit: 200).all_pages
api.get_beta_groups(filter: { app: "app", name: "Board device" }, includes: nil, limit: 200).all_pages
api.get_builds_for_beta_group(group_id: "group").all_pages
assert(transport.requests.map(&:first) == ["v1/apps", "v1/builds", "v1/betaGroups", "v1/betaGroups/group/builds"])
# Real model mapping for every field emitted from a build/group.
b = Spaceship::ConnectAPI::Models.parse({ "data" => { "type" => "builds", "id" => "b", "attributes" => { "version" => "3", "processingState" => "PROCESSING" } } })
assert(b.version == "3" && b.processing_state == "PROCESSING")
{
  Spaceship::ConnectAPI::Build => %i[version uploaded_date processing_state pre_release_version build_beta_detail beta_app_review_submission],
  Spaceship::ConnectAPI::BuildBetaDetail => %i[internal_build_state external_build_state],
  Spaceship::ConnectAPI::BetaAppReviewSubmission => %i[beta_review_state],
  Spaceship::ConnectAPI::PreReleaseVersion => %i[version],
  Spaceship::ConnectAPI::BetaGroup => %i[name is_internal_group public_link_enabled public_link_limit_enabled public_link_limit public_link]
}.each { |klass, fields| fields.each { |field| assert(klass.method_defined?(field), "#{klass} missing #{field}") } }
puts "Pinned Fastlane GET transport and model contract checks passed"
