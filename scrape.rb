#!/usr/bin/env ruby
# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2021-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'optparse'
require 'csv'
require 'json'
require 'net/http'
require 'openssl'
require 'socket'
require 'timeout'
require 'uri'

# +-----------------------------------------------------------------+
# |  Github                                                          |
# |                                                                  |
# |  Thin authenticated client for api.github.com. Performs GET      |
# |  requests, parses JSON, and waits when the primary rate limit    |
# |  is exhausted. Construct once and pass into collaborators.       |
# |                                                                  |
# |  Usage:                                                          |
# |    api = Github.new('ghp_xxx')                                   |
# |    json = api.get('/users/yegor256')                             |
# +-----------------------------------------------------------------+
class Github
  def initialize(token)
    @token = token
  end

  REQUEST_DEADLINE = 30

  NETWORK_ERRORS = [
    SocketError, IOError, EOFError,
    SystemCallError,
    Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
    Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError,
    OpenSSL::OpenSSLError,
    Timeout::Error,
    JSON::ParserError, Zlib::Error
  ].freeze

  def get(path)
    attempt = 0
    loop do
      begin
        uri = URI("https://api.github.com#{path}")
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{@token}"
        req['Accept'] = 'application/vnd.github+json'
        req['X-GitHub-Api-Version'] = '2022-11-28'
        req['User-Agent'] = 'scrape.rb'
        res = Timeout.timeout(REQUEST_DEADLINE) do
          Net::HTTP.start(
            uri.hostname, uri.port,
            use_ssl: true,
            open_timeout: 10, read_timeout: 15, write_timeout: 15, ssl_timeout: 10
          ) { |h| h.request(req) }
        end
        if (res.code == '403' || res.code == '429') && res['x-ratelimit-remaining'].to_s == '0'
          reset = res['x-ratelimit-reset'].to_i
          wait = [reset - Time.now.to_i + 1, 1].max
          warn "rate limit hit on #{path}, sleeping #{wait}s"
          sleep(wait)
          next
        end
        if res.code == '403' && res['retry-after']
          wait = [res['retry-after'].to_i, 1].max
          warn "secondary rate limit on #{path}, sleeping #{wait}s"
          sleep(wait)
          next
        end
        if res.code.to_i.between?(500, 599)
          attempt += 1
          backoff = [2**[attempt, 6].min, 60].min
          warn "server error #{res.code} on #{path}, retry in #{backoff}s"
          sleep(backoff)
          next
        end
        raise "github #{path} returned #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)
        return JSON.parse(res.body)
      rescue Interrupt
        raise
      rescue *NETWORK_ERRORS => e
        attempt += 1
        backoff = [2**[attempt, 6].min, 60].min
        warn "network error on #{path}: #{e.class}: #{e.message}, retry in #{backoff}s"
        sleep(backoff)
      end
    end
  end
end

# +-----------------------------------------------------------------+
# |  Search                                                          |
# |                                                                  |
# |  Iterates over public repositories in a star range, walking      |
# |  from the highest stars downward. GitHub's search endpoint caps  |
# |  any single query at 1000 results, so wider ranges are bisected  |
# |  recursively into sub-windows until each has at most 1000 hits.  |
# |  A degenerate window where one star value alone holds >1000      |
# |  repos still loses its tail — that is an irreducible API limit.  |
# |                                                                  |
# |  Usage:                                                          |
# |    Search.new(api, 100, 1_000_000).each { |repo| ... }           |
# +-----------------------------------------------------------------+
class Search
  PER_PAGE = 100
  MAX_RESULTS = 1000

  def initialize(github, min, max)
    @github = github
    @min = min
    @max = max
  end

  def each(&block)
    return enum_for(:each) unless block_given?
    pending = [[@min, @max]]
    until pending.empty?
      low, high = pending.shift
      next if low > high
      first = fetch(low, high, 1)
      total = first['total_count'].to_i
      if total > MAX_RESULTS && high > low
        mid = low + ((high - low) / 2)
        warn "range #{low}..#{high} has #{total} repos, splitting at #{mid}"
        pending.unshift([mid + 1, high], [low, mid])
        next
      end
      warn "range #{low}..#{high} has #{total} repos, fetching"
      (first['items'] || []).each(&block)
      pages = [(total / PER_PAGE.to_f).ceil, MAX_RESULTS / PER_PAGE].min
      (2..pages).each do |page|
        (fetch(low, high, page)['items'] || []).each(&block)
      end
    end
  end

  private

  def fetch(low, high, page)
    query = "stars:#{low}..#{high} sort:stars-desc"
    encoded = URI.encode_www_form_component(query)
    @github.get("/search/repositories?q=#{encoded}&per_page=#{PER_PAGE}&page=#{page}")
  end
end

# +-----------------------------------------------------------------+
# |  Owner                                                           |
# |                                                                  |
# |  Resolves a GitHub login into a contact record (first name,      |
# |  last name, email). When the profile email is hidden, tries      |
# |  three sources in order: the user's public push events, the      |
# |  seed repository's commits filtered by author, and the user's    |
# |  other public repos. Skips GitHub noreply addresses.             |
# |                                                                  |
# |  Usage:                                                          |
# |    Owner.new(api, 'yegor256', 'yegor256/takes').details          |
# +-----------------------------------------------------------------+
class Owner
  def initialize(github, login, repo)
    @github = github
    @login = login
    @repo = repo
  end

  def details
    user = @github.get("/users/#{@login}")
    name = user['name'].to_s.strip
    parts = name.split(/\s+/, 2)
    first = parts[0].to_s
    last = parts[1].to_s
    email = user['email'].to_s.strip
    email = harvest if email.empty?
    { 'first' => first, 'last' => last, 'email' => email }
  end

  private

  def harvest
    found = harvest_events
    return found unless found.empty?
    found = harvest_repo(@repo)
    return found unless found.empty?
    harvest_other_repos
  end

  def harvest_events
    safe_get("/users/#{@login}/events/public").each do |e|
      next unless e['type'] == 'PushEvent'
      (e.dig('payload', 'commits') || []).each do |c|
        candidate = pick(c['author'])
        return candidate unless candidate.empty?
      end
    end
    ''
  end

  def harvest_repo(slug)
    return '' if slug.to_s.empty?
    safe_get("/repos/#{slug}/commits?author=#{@login}&per_page=100").each do |c|
      candidate = pick((c['commit'] || {})['author'])
      return candidate unless candidate.empty?
    end
    ''
  end

  def harvest_other_repos
    safe_get("/users/#{@login}/repos?per_page=20&sort=pushed&type=owner").each do |r|
      slug = r['full_name'].to_s
      next if slug.empty? || slug == @repo
      next if r['fork']
      candidate = harvest_repo(slug)
      return candidate unless candidate.empty?
    end
    ''
  end

  def pick(author)
    return '' if author.nil?
    candidate = author['email'].to_s.strip
    return '' if candidate.empty?
    return '' if candidate.end_with?('users.noreply.github.com')
    return '' if candidate.end_with?('@noreply.github.com')
    candidate
  end

  def safe_get(path)
    @github.get(path)
  rescue StandardError => e
    warn "#{path} unreachable: #{e.message}"
    []
  end
end

opts = { min: 100, max: 1000, out: 'owners.csv', limit: nil }
parser = OptionParser.new do |o|
  o.banner = 'Usage: scrape.rb --token=TOKEN [--min-stars=N] [--max-stars=N] [--limit=N] [--out=FILE]'
  o.on('--token=TOKEN', 'GitHub personal access token (required)') { |t| opts[:token] = t.to_s.strip }
  o.on('--min-stars=N', Integer, 'minimum star count, default 100') { |n| opts[:min] = n }
  o.on('--max-stars=N', Integer, 'maximum star count, default 1000') { |n| opts[:max] = n }
  o.on('--limit=N', Integer, 'stop after writing N rows, default unlimited') { |n| opts[:limit] = n }
  o.on('--out=FILE', 'output CSV path, default owners.csv') { |f| opts[:out] = f }
  o.on('-h', '--help') { puts(o); exit(0) }
end
parser.parse!

raise 'option --token is mandatory' if opts[:token].nil? || opts[:token].empty?
raise "min-stars #{opts[:min]} exceeds max-stars #{opts[:max]}" if opts[:min] > opts[:max]
raise "min-stars #{opts[:min]} must be non-negative" if opts[:min].negative?
raise "limit #{opts[:limit]} must be positive" if !opts[:limit].nil? && opts[:limit] < 1

github = Github.new(opts[:token])
seen = {}
written = 0
exists = File.exist?(opts[:out]) && File.size(opts[:out]).positive?
if exists
  CSV.foreach(opts[:out], headers: true) do |row|
    login = row['repository'].to_s.split('/', 2).first.to_s
    seen[login] = true unless login.empty?
  end
  warn "appending to #{opts[:out]}, #{seen.size} owners already present"
end
file = File.open(opts[:out], exists ? 'a' : 'w')
file.sync = true
csv = CSV.new(file)
csv << %w[first_name last_name email repository] unless exists
begin
  Search.new(github, opts[:min], opts[:max]).each do |repo|
    owner = repo['owner'] || {}
    next unless owner['type'] == 'User'
    login = owner['login'].to_s
    next if login.empty?
    next if seen.key?(login)
    seen[login] = true
    full = repo['full_name'].to_s
    info =
      begin
        Owner.new(github, login, full).details
      rescue Interrupt
        raise
      rescue StandardError => e
        warn "failed for #{login} from #{full}: #{e.class}: #{e.message}, retrying in 10s"
        sleep(10)
        retry
      end
    if info['email'].empty?
      warn "no email for #{login} from #{full}"
      next
    end
    first = info['first'].match?(/\A[A-Za-z]+\z/) ? info['first'] : ''
    last = info['last'].match?(/\A[A-Za-z]+\z/) ? info['last'] : ''
    csv << [first, last, info['email'], full]
    written += 1
    warn "[#{written}] #{login} <#{info['email']}> via #{full}"
    if !opts[:limit].nil? && written >= opts[:limit]
      warn "limit of #{opts[:limit]} reached, stopping"
      break
    end
  end
ensure
  file.close
end
warn "done, #{written} rows written to #{opts[:out]}"
