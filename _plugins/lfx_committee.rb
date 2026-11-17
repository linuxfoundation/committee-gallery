# Fetches committee members from the LFX Self Serve (v2) query service and
# returns them in the field shape the _includes renders already use, so the
# render templates and filters in _layouts/default.html keep working unchanged.
#
# Usage in a template:
#   {% assign committee_uid = page | lfx_committee_uid %}
#   {% lfxCommitteeMembers members from committee committee_uid %}
#
# Environment:
#   LFX_API_TOKEN   (required) Bearer token for the LFX v2 API. Committee members are
#                   not public in v2, so anonymous requests return nothing.
#   LFX_API_URL     (optional) Defaults to https://lfx-api.v2.cluster.lfx.dev
#   LFX_ALLOW_EMPTY_COMMITTEES (optional) Set to 1 to let a committee that returns no
#                   members build anyway instead of failing the build.

require 'json'
require 'net/http'
require 'uri'

module LFXCommittee
  DEFAULT_API_URL = 'https://lfx-api.v2.cluster.lfx.dev'.freeze
  UUID_RE = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/.freeze
  LEGACY_PCC_HOST = 'projectadmin.lfx.linuxfoundation.org'.freeze
  PAGE_SIZE = 1000

  @cache = {}

  class << self
    # Resolve the v2 committee UID from page front matter.
    # Prefers `lfx_committee_uid`; otherwise takes the last UUID in a v2 Self Serve
    # `lfx_committee_url`. Legacy PCC URLs carry v1 committee IDs, which do not
    # match v2 UIDs, so those are rejected with a clear message.
    def committee_uid_for(uid, url)
      uid = uid.to_s.strip
      return uid unless uid.empty?

      url = url.to_s.strip
      return nil if url.empty?

      if url.include?(LEGACY_PCC_HOST)
        raise ArgumentError, "lfx_committee_url #{url} is a legacy PCC link; its committee ID is " \
                             'not valid in LFX Self Serve. Set lfx_committee_uid to the v2 committee UID.'
      end
      url.scan(UUID_RE).last
    end

    def members(committee_uid)
      @cache[committee_uid] ||= fetch(committee_uid)
    end

    private

    def api_url
      ENV.fetch('LFX_API_URL', DEFAULT_API_URL).chomp('/')
    end

    def token
      t = ENV['LFX_API_TOKEN'].to_s.strip
      raise ArgumentError, 'LFX_API_TOKEN is not set; the LFX v2 API needs a bearer token to read committee members.' if t.empty?

      t.sub(/\ABearer\s+/i, '')
    end

    def fetch(committee_uid)
      raise ArgumentError, "Not a committee UID: #{committee_uid.inspect}" unless committee_uid.to_s.match?(/\A#{UUID_RE}\z/)

      resources = []
      page_token = nil
      loop do
        body = get_page(committee_uid, page_token)
        resources.concat(Array(body['resources']))
        page_token = body['page_token'].to_s
        break if page_token.empty?
      end

      members = resources
                .map { |r| r['data'] || r['Data'] }
                .compact
                .select { |d| d['status'].nil? || d['status'].to_s.casecmp('active').zero? }
                .map { |d| to_legacy(d) }

      if members.empty? && ENV['LFX_ALLOW_EMPTY_COMMITTEES'] != '1'
        raise "No members returned for committee #{committee_uid}. Check the UID and that the " \
              'LFX_API_TOKEN identity can view this committee (set LFX_ALLOW_EMPTY_COMMITTEES=1 to build anyway).'
      end

      Jekyll.logger.info 'LFX:', "committee #{committee_uid}: #{members.size} members"
      members
    end

    def get_page(committee_uid, page_token)
      uri = URI("#{api_url}/query/resources")
      params = [
        %w[v 1],
        %w[type committee_member],
        ['tags', "committee_uid:#{committee_uid}"],
        ['page_size', PAGE_SIZE.to_s]
      ]
      params << ['page_token', page_token] if page_token && !page_token.empty?
      uri.query = URI.encode_www_form(params)

      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}"
      req['Accept'] = 'application/json'

      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                 open_timeout: 15, read_timeout: 60) do |http|
        http.request(req)
      end
      unless resp.is_a?(Net::HTTPSuccess)
        raise "LFX query for committee #{committee_uid} failed: HTTP #{resp.code} #{resp.body.to_s[0, 300]}"
      end

      JSON.parse(resp.body)
    end

    # Map a v2 committee_member document onto the v1 public API field names.
    # Email is deliberately not carried over: these pages are published publicly.
    # `avatar` is the member's LFX profile picture, copied onto the member record by the
    # committee service; it is empty when the person has none. v2 carries no bio, Twitter
    # or GitHub, so those are nil.
    def to_legacy(d)
      role = d['role'] || {}
      voting = d['voting'] || {}
      org = d['organization'] || {}
      linkedin = d['linkedin_profile'].to_s.strip

      {
        'MemberID' => d['uid'],
        'Username' => d['username'],
        'FirstName' => d['first_name'],
        'LastName' => d['last_name'],
        'Title' => d['job_title'],
        'Role' => role['name'].to_s.empty? ? 'None' : role['name'],
        'RoleStartDate' => role['start_date'],
        'RoleEndDate' => role['end_date'],
        'VotingStatus' => voting['status'],
        'VotingStartDate' => voting['start_date'],
        'VotingEndDate' => voting['end_date'],
        'AppointedBy' => d['appointed_by'],
        'Organization' => {
          'ID' => org['id'],
          'Name' => org['name'],
          'Website' => org['website']
        },
        'LogoURL' => d['avatar'].to_s.strip.empty? ? nil : d['avatar'].to_s.strip,
        'Twitter' => nil,
        'AboutMe' => linkedin.empty? ? nil : { 'LinkedIn' => linkedin }
      }
    end
  end

  class MembersTag < Liquid::Tag
    SYNTAX = /\A\s*(\S+)\s+from\s+committee\s+(.+?)\s*\z/.freeze

    def initialize(tag_name, markup, tokens)
      super
      m = SYNTAX.match(markup)
      raise ArgumentError, "Syntax: {% lfxCommitteeMembers <var> from committee <uid> %} (got #{markup.inspect})" unless m

      @var = m[1]
      @uid_expr = m[2]
    end

    def render(context)
      expr = @uid_expr.delete('{} ').strip
      uid = context[expr] || expr
      context.scopes.last[@var] = LFXCommittee.members(uid.to_s.strip)
      ''
    end
  end

  class UidFilterHelper
    # Exposed as a Liquid filter so the layout can resolve front matter in one place.
    module Filter
      def lfx_committee_uid(page)
        LFXCommittee.committee_uid_for(page['lfx_committee_uid'], page['lfx_committee_url'])
      end
    end
  end
end

Liquid::Template.register_tag('lfxCommitteeMembers', LFXCommittee::MembersTag)
Liquid::Template.register_filter(LFXCommittee::UidFilterHelper::Filter)
