require "json"
require "time"
require "fileutils"

# Only GET methods from Spaceship::ConnectAPI are used. Never serialize API models:
# allowlisted fields keep tester identities and review contact details out of output.
class TestflightStatus
  INCLUDES = "preReleaseVersion,buildBetaDetail,betaAppReviewSubmission".freeze
  REJECTION_NOTE = "Rejection reason is not exposed by the pinned Beta App Review API; check App Store Connect UI review messages.".freeze

  def self.selection(numbers, recent)
    numbers = numbers.to_s.strip
    unless numbers.empty? || numbers.match?(/\A[0-9]+(?:\s*,\s*[0-9]+)*\z/)
      raise ArgumentError, "BUILD_NUMBERS must be comma-separated numeric build numbers, or empty for recent builds."
    end
    count = Integer(recent.to_s, 10)
    raise ArgumentError, "RECENT_LIMIT must be 1..50." unless (1..50).cover?(count)
    [numbers.empty? ? [] : numbers.split(/\s*,\s*/).uniq, count]
  end

  def initialize(api:, app_id:, group_name:)
    @api, @app_id, @group_name = api, app_id, group_name
  end

  def report(numbers:, recent:)
    app = @api.get_apps(filter: { bundleId: @app_id }, includes: nil, limit: 1).to_models.first
    raise "App not found" unless app

    filter = { app: app.id }
    filter[:version] = numbers.join(",") unless numbers.empty?
    response = @api.get_builds(filter: filter, includes: INCLUDES, sort: "-uploadedDate", limit: numbers.empty? ? recent : 200)
    # Recent mode intentionally reads one page; selected mode checks every page.
    builds = numbers.empty? ? response.to_models : response.all_pages.flat_map(&:to_models)
    groups = @api.get_beta_groups(filter: { app: app.id, name: @group_name }, includes: nil, limit: 200)
                 .all_pages.flat_map(&:to_models)
    group = groups.find { |g| g.name == @group_name && !g.is_internal_group }
    attached = if group
                 @api.get_builds_for_beta_group(group_id: group.id).all_pages.flat_map(&:to_models)
               else
                 []
               end
    {
      generated_at: Time.now.utc.iso8601,
      app: @app_id,
      selection: numbers.empty? ? { recent_limit: recent } : { build_numbers: numbers },
      missing_build_numbers: numbers - builds.map(&:version),
      builds: builds.map { |b| build_status(b) },
      group: group ? {
        name: @group_name, found: true,
        public_link_enabled: group.public_link_enabled,
        public_link_limit_enabled: group.public_link_limit_enabled,
        public_link_limit: group.public_link_limit, public_link_url: group.public_link,
        attached_build_numbers: attached.map(&:version).uniq.sort
      } : { name: @group_name, found: false, attached_build_numbers: [] },
      rejection_information: REJECTION_NOTE
    }
  end

  def self.write(report, directory:, summary_path: nil)
    json = JSON.pretty_generate(report)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "testflight-status.json"), json + "\n")
    # JSON fence is escaped so even unexpected remote strings cannot end the fence.
    summary = "## TestFlight status (read only)\n\n```json\n#{json.gsub('`', '\\u0060')}\n```\n"
    File.write(summary_path, summary, mode: "a") if summary_path && !summary_path.empty?
    json
  end

  private

  def build_status(build)
    detail = build.build_beta_detail
    review = build.beta_app_review_submission
    {
      build_number: build.version, app_version: build.pre_release_version&.version,
      uploaded_at: build.uploaded_date, processing_state: build.processing_state,
      internal_state: detail&.internal_build_state, external_state: detail&.external_build_state,
      beta_review_state: review&.beta_review_state,
      beta_review_submission_present: !review.nil?
    }
  end
end
