require "ostruct"
require "tmpdir"
require_relative "../lib/testflight_status"

def assert(value, message = "assertion failed")
  raise message unless value
end

class Page
  def initialize(models, following = [])
    @models, @following = models, following
  end
  def to_models; @models; end
  def all_pages; [self] + @following; end
end

# Deliberately supports only the four read calls: mutations or identity lookups fail.
class ReadAPI
  attr_reader :queries
  attr_accessor :groups, :builds, :attachments
  def initialize
    @queries = []
    @groups, @builds, @attachments = Page.new([]), Page.new([]), Page.new([])
  end
  def get_apps(filter:, includes:, limit:)
    assert(filter == { bundleId: "com.rimasbac.roadprint" })
    assert(includes.nil? && limit == 1)
    Page.new([OpenStruct.new(id: "app")])
  end
  def get_builds(filter:, includes:, sort:, limit:)
    @queries << [filter, includes, sort, limit]
    @builds
  end
  def get_beta_groups(filter:, includes:, limit:)
    assert(filter == { app: "app", name: "Board device" })
    assert(includes.nil? && limit == 200)
    @groups
  end
  def get_builds_for_beta_group(group_id:)
    assert(group_id == "group")
    @attachments
  end
end

def reporter(api)
  TestflightStatus.new(api: api, app_id: "com.rimasbac.roadprint", group_name: "Board device")
end

def build(number, state: nil)
  OpenStruct.new(version: number, uploaded_date: "2026-11-10T00:00:00Z", processing_state: "VALID",
    pre_release_version: OpenStruct.new(version: "0.1.0"),
    build_beta_detail: state && OpenStruct.new(internal_build_state: "IN_BETA_TESTING", external_build_state: "BETA_REJECTED"),
    beta_app_review_submission: state && OpenStruct.new(beta_review_state: state),
    contact_email: "PRIVATE-CONTACT", beta_testers: "PRIVATE-TESTER")
end

assert(TestflightStatus.selection("3, 4,3", "10") == [["3", "4"], 10])
assert(TestflightStatus.selection("", "2") == [[], 2])
[ ["3; echo nope", "10"], ["3,", "10"], ["3", "0"], ["", "51"], ["", "x"] ].each do |args|
  begin
    TestflightStatus.selection(*args)
    raise "invalid input accepted"
  rescue ArgumentError
    # expected
  end
end

api = ReadAPI.new
api.builds = Page.new([build("3", state: "REJECTED")], [Page.new([build("4")])])
api.groups = Page.new([], [Page.new([OpenStruct.new(id: "group", name: "Board device", is_internal_group: false,
  public_link_enabled: false, public_link_limit_enabled: true, public_link_limit: 5,
  public_link: "https://testflight.apple.com/join/EXAMPLE", beta_testers: "PRIVATE-TESTER")])])
api.attachments = Page.new([build("3")], [Page.new([build("4")])])
report = reporter(api).report(numbers: ["3", "4", "5"], recent: 10)
assert(report[:missing_build_numbers] == ["5"])
assert(report[:builds].map { |b| b[:build_number] } == ["3", "4"])
assert(report[:builds][0][:beta_review_state] == "REJECTED")
assert(report[:builds][0][:external_state] == "BETA_REJECTED")
assert(report[:builds][1][:internal_state].nil?)
assert(report[:builds][1][:beta_review_submission_present] == false)
assert(report[:group][:attached_build_numbers] == ["3", "4"])
assert(report[:group][:public_link_enabled] == false)
assert(api.queries[0] == [{ app: "app", version: "3,4,5" }, TestflightStatus::INCLUDES, "-uploadedDate", 200])
assert(report[:rejection_information].include?("App Store Connect UI"))
Time.iso8601(report[:generated_at])

Dir.mktmpdir do |dir|
  summary = File.join(dir, "summary.md")
  json = TestflightStatus.write(report, directory: dir, summary_path: summary)
  assert(!json.include?("PRIVATE"))
  assert(JSON.parse(File.read(File.join(dir, "testflight-status.json"))) == JSON.parse(json))
  assert(File.read(summary).include?("REJECTED"))
end

recent = reporter(api).report(numbers: [], recent: 1)
assert(recent[:builds].size == 1, "recent must not fetch following pages")
assert(api.queries.last.last == 1)
assert(!api.queries.last.first.key?(:version))
api.groups = Page.new([])
api.builds = Page.new([])
missing = reporter(api).report(numbers: ["4"], recent: 10)
assert(missing[:group][:found] == false)
assert(missing[:missing_build_numbers] == ["4"])
puts "TestFlight status mocked checks passed"
