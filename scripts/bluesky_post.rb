#!/usr/bin/env ruby
# frozen_string_literal: true

# 公開済み記事を Bluesky に自動投稿する。
# 本文はモデル名と題材を踏まえて毎回違う言い回しにし、リンクカードで briscape へ誘導する。

require "yaml"
require "json"
require "net/http"
require "uri"
require "time"
require "optparse"
require "fileutils"
require "digest"
require "set"

ROOT = File.expand_path("..", __dir__)
POSTS_DIR = File.join(ROOT, "_posts")
STATE_PATH = File.join(ROOT, "_data", "bluesky_posted.yml")
SITE_URL = "https://briscape.com"
JST_OFFSET = "+09:00"
PDS_HOST = ENV.fetch("BLUESKY_PDS", "https://bsky.social")
MAX_GRAPHEMES = 300
TEASER_MAX = 90

TOPIC_ALIASES = {
  "グロックボット" => "GrokBot",
  "グロクボット" => "GrokBot",
  "オマーチ" => "Omarchy",
  "オマーチー" => "Omarchy",
  "エックス" => "X",
  "ライン" => "LINE",
  "ネットフリックス" => "Netflix"
}.freeze

STOP_TOPICS = %w[
  私 僕 余 それ これ あれ ここ そこ あそこ もの こと ため よう とき いま 今日
  先日 近頃 最近 しかし そして また など という といふ である です ます
].freeze

# uses_topic: 固有の題材（GrokBot 等）があるとき優先する型
TEMPLATES = [
  { uses_topic: true,  build: ->(c) { "#{c[:model]}のふりして#{c[:topic]}について書いた" } },
  { uses_topic: true,  build: ->(c) { "#{c[:model]}の声で、#{c[:topic]}の話を少し" } },
  { uses_topic: false, build: ->(c) { "#{c[:model]}になりきって『#{c[:title]}』" } },
  { uses_topic: false, build: ->(c) { "今日の随筆は#{c[:model]}。題は『#{c[:title]}』" } },
  { uses_topic: true,  build: ->(c) { "#{c[:topic]}のことを、#{c[:model]}の文体で" } },
  { uses_topic: false, build: ->(c) { "『#{c[:title]}』——#{c[:model]}の口ぶりで" } },
  { uses_topic: true,  build: ->(c) { "#{c[:model]}を借りて、#{c[:topic]}を書いてみた" } },
  { uses_topic: true,  build: ->(c) { "新着。#{c[:model]}モデルで#{c[:topic]}の話" } },
  { uses_topic: false, build: ->(c) { "#{c[:model]}の筆致で『#{c[:title]}』を置いた" } },
  { uses_topic: true,  build: ->(c) { "#{c[:topic]}について、#{c[:model]}のふりをして一筆" } },
  { uses_topic: true,  build: ->(c) { "文豪ごっこ、今日は#{c[:model]}。#{c[:topic]}の件" } },
  { uses_topic: false, build: ->(c) { "#{c[:model]}になりすまして書いた『#{c[:title]}』" } },
  { uses_topic: true,  build: ->(c) { "『#{c[:title]}』。#{c[:model]}の息で#{c[:topic]}を" } },
  { uses_topic: true,  build: ->(c) { "#{c[:model]}の仮面で、#{c[:topic]}を短く" } },
  { uses_topic: false, build: ->(c) { "briscape に新稿。#{c[:model]}／『#{c[:title]}』" } },
  { uses_topic: true,  build: ->(c) { "#{c[:model]}のふりをして、#{c[:topic]}の話を置いた" } },
  { uses_topic: true,  build: ->(c) { "#{c[:topic]}の話を、#{c[:model]}の口で書いてみた" } }
].freeze

TEASER_PREFIXES = [
  "",
  "冒頭だけ。",
  "続きはサイトで。",
  "少しだけ抜き書き。"
].freeze

def now_jst
  Time.now.getlocal(JST_OFFSET)
end

def time_to_jst(time)
  return time.getlocal(JST_OFFSET) if time.is_a?(Time)
  Time.parse(time.to_s).getlocal(JST_OFFSET)
end

def parse_front_matter(markdown)
  m = markdown.to_s.match(/\A---\n(.*?)\n---\n(.*)\z/m)
  return [{}, ""] unless m
  data = YAML.safe_load(m[1], permitted_classes: [Date, Time]) || {}
  [data, m[2].to_s]
rescue Psych::Exception
  [{}, markdown.to_s]
end

def body_paragraphs(body)
  text = body.to_s
  text = text.gsub(/!\[[^\]]*\]\([^\n]+\)/, "")
  text = text.gsub(/\{%\s*.*?\s*%\}/, "")
  text = text.gsub(/<!--.*?-->/m, "")
  text = text.gsub(/^>\s?/, "")
  text.split(/\n{2,}/).map { |p| p.gsub(/\s+/, " ").strip }.reject(&:empty?)
end

def first_paragraph(body)
  body_paragraphs(body).first.to_s
end

def grapheme_slice(str, max)
  chars = str.to_s.each_grapheme_cluster.to_a
  return str if chars.length <= max
  chars.take(max).join
end

def truncate_teaser(str, max = TEASER_MAX)
  clean = str.to_s.gsub(/\s+/, " ").strip
  chars = clean.each_grapheme_cluster.to_a
  return clean if chars.length <= max
  "#{chars.take(max - 1).join}…"
end

def extract_latin_topics(text)
  text.scan(/\b[A-Za-z][A-Za-z0-9][A-Za-z0-9+.#-]{1,40}\b/)
      .reject { |w| w.length < 3 }
      .uniq
end

def extract_katakana_topics(text)
  text.scan(/[ァ-ヶー]{3,20}/).uniq
end

def normalize_topic(raw)
  t = raw.to_s.strip
  return nil if t.empty?
  TOPIC_ALIASES.each do |kana, latin|
    return latin if t == kana || t.include?(kana)
  end
  t
end

def topic_candidates(title, body)
  para = first_paragraph(body)
  found = []
  extract_latin_topics("#{title} #{para}").each { |w| found << w }
  extract_katakana_topics(para).each do |w|
    n = normalize_topic(w)
    found << n if n
  end
  found << title.to_s.strip unless title.to_s.strip.empty?
  found.map { |t| normalize_topic(t) || t }
       .compact
       .map(&:strip)
       .reject { |t| t.empty? || STOP_TOPICS.include?(t) }
       .uniq
end

def pick_topic(candidates, rng, body: "")
  return "近況" if candidates.empty?
  # Prefer Latin / product-like names when present
  preferred = candidates.select { |t| t.match?(/\A[A-Za-z]/) }
  pool = preferred.empty? ? candidates : preferred
  if preferred.length > 1 && !body.to_s.empty?
    scored = preferred.map { |t| [t, body.to_s.scan(/#{Regexp.escape(t)}/i).length] }
    max = scored.map(&:last).max.to_i
    if max.positive?
      top = scored.select { |_, n| n == max }.map(&:first)
      return top[rng.rand(top.length)]
    end
  end
  pool[rng.rand(pool.length)]
end

def load_state
  return { "posted" => [] } unless File.exist?(STATE_PATH)
  data = YAML.safe_load(File.read(STATE_PATH), permitted_classes: [Date, Time]) || {}
  data["posted"] = Array(data["posted"])
  data
end

def save_state!(state)
  FileUtils.mkdir_p(File.dirname(STATE_PATH))
  File.write(STATE_PATH, YAML.dump(state))
end

def relative_post_path(path)
  path.to_s.sub(%r{\A#{Regexp.escape(ROOT)}/?}, "")
end

def posted_paths(state)
  state["posted"].map { |e| e["path"].to_s }.reject(&:empty?).to_set
end

def permalink_for(data, path)
  if data["permalink"]
    p = data["permalink"].to_s
    p = "/#{p}" unless p.start_with?("/")
    p += "/" unless p.end_with?("/")
    return p
  end
  # Fallback to filename slug (rare; posts usually set permalink)
  base = File.basename(path, ".md").sub(/\A\d{4}-\d{2}-\d{2}-/, "")
  "/#{base}/"
end

def post_date(data)
  raw = data["date"]
  return nil if raw.nil?
  return time_to_jst(raw) if raw.is_a?(Time)
  return Time.new(raw.year, raw.month, raw.day, 0, 0, 0, JST_OFFSET) if raw.is_a?(Date)
  time_to_jst(Time.parse(raw.to_s))
rescue ArgumentError
  nil
end

def absolute_url(path)
  "#{SITE_URL}#{path}"
end

def absolute_image_url(image)
  return nil if image.nil? || image.to_s.strip.empty?
  img = image.to_s.strip
  return img if img.start_with?("http://", "https://")
  img = "/#{img}" unless img.start_with?("/")
  "#{SITE_URL}#{img}"
end

def compose_post_text(model:, title:, body:, permalink:)
  rng = Random.new(Digest::SHA256.hexdigest(permalink).to_i(16))
  topics = topic_candidates(title, body)
  topic = pick_topic(topics, rng, body: body)
  ctx = { model: model, title: title, topic: topic }
  # タイトル以外の題材があるときは、題材を含む言い回しを厚くする
  rich_topic = topic != title && !topic.nil?
  pool =
    if rich_topic
      preferred = TEMPLATES.select { |t| t[:uses_topic] }
      preferred.empty? ? TEMPLATES : preferred
    else
      TEMPLATES
    end
  template = pool[rng.rand(pool.length)]
  line1 = template[:build].call(ctx)

  include_teaser = rng.rand < 0.55
  text =
    if include_teaser
      teaser = truncate_teaser(first_paragraph(body))
      prefix = TEASER_PREFIXES[rng.rand(TEASER_PREFIXES.length)]
      second = prefix.empty? ? teaser : "#{prefix}#{teaser}"
      "#{line1}\n\n#{second}"
    else
      line1
    end

  grapheme_slice(text, MAX_GRAPHEMES - 1)
end

def load_posts
  Dir[File.join(POSTS_DIR, "*.md")].sort.map do |path|
    data, body = parse_front_matter(File.read(path))
    date = post_date(data)
    next unless date
    permalink = permalink_for(data, path)
    model = Array(data["tags"]).first.to_s
    model = "文豪" if model.empty?
    {
      path: path,
      data: data,
      body: body,
      date: date,
      permalink: permalink,
      title: data["title"].to_s,
      model: model,
      image: data["image"],
      bluesky: data.key?("bluesky") ? data["bluesky"] : true
    }
  end.compact
end

def pending_posts(now: now_jst, state: load_state)
  done = posted_paths(state)
  load_posts.select do |p|
    next false if p[:bluesky] == false
    next false if p[:date] > now
    next false if done.include?(relative_post_path(p[:path]))
    true
  end.sort_by { |p| p[:date] }
end

def http_json(method, url, headers: {}, body: nil)
  uri = URI(url)
  req =
    case method
    when :get then Net::HTTP::Get.new(uri)
    when :post then Net::HTTP::Post.new(uri)
    else
      raise "unsupported method #{method}"
    end
  headers.each { |k, v| req[k] = v }
  req.body = body if body
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(req)
  end
  unless res.is_a?(Net::HTTPSuccess)
    raise "HTTP #{res.code} #{uri}: #{res.body.to_s[0, 400]}"
  end
  res.body.empty? ? {} : JSON.parse(res.body)
end

def http_bytes(url)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(Net::HTTP::Get.new(uri))
  end
  unless res.is_a?(Net::HTTPSuccess)
    raise "HTTP #{res.code} fetching #{uri}"
  end
  [res.body, res["content-type"].to_s]
end

def bluesky_login(identifier, password)
  json = http_json(
    :post,
    "#{PDS_HOST}/xrpc/com.atproto.server.createSession",
    headers: { "Content-Type" => "application/json" },
    body: { identifier: identifier, password: password }.to_json
  )
  {
    did: json["did"],
    access_jwt: json["accessJwt"],
    handle: json["handle"]
  }
end

def upload_blob(access_jwt, bytes, mime)
  uri = URI("#{PDS_HOST}/xrpc/com.atproto.repo.uploadBlob")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Bearer #{access_jwt}"
  req["Content-Type"] = mime
  req.body = bytes
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  unless res.is_a?(Net::HTTPSuccess)
    raise "uploadBlob failed #{res.code}: #{res.body.to_s[0, 400]}"
  end
  JSON.parse(res.body).fetch("blob")
end

def mime_for(content_type, url)
  ct = content_type.to_s.split(";").first.to_s.strip.downcase
  return ct if ct.start_with?("image/")
  case File.extname(URI(url).path).downcase
  when ".jpg", ".jpeg" then "image/jpeg"
  when ".png" then "image/png"
  when ".webp" then "image/webp"
  when ".gif" then "image/gif"
  else "image/jpeg"
  end
end

def build_external_embed(session, post)
  uri = absolute_url(post[:permalink])
  description = truncate_teaser(first_paragraph(post[:body]), 200)
  description = post[:title] if description.empty?
  card = {
    "uri" => uri,
    "title" => grapheme_slice(post[:title], 100),
    "description" => grapheme_slice(description, 200)
  }
  image_url = absolute_image_url(post[:image])
  if image_url
    begin
      bytes, ct = http_bytes(image_url)
      if bytes.bytesize.positive? && bytes.bytesize < 1_000_000
        card["thumb"] = upload_blob(session[:access_jwt], bytes, mime_for(ct, image_url))
      end
    rescue StandardError => e
      warn "thumb skipped for #{post[:permalink]}: #{e.message}"
    end
  end
  {
    "$type" => "app.bsky.embed.external",
    "external" => card
  }
end

def create_bluesky_post(session, text, embed)
  record = {
    "$type" => "app.bsky.feed.post",
    "text" => text,
    "createdAt" => Time.now.utc.iso8601(3),
    "langs" => ["ja"],
    "embed" => embed
  }
  http_json(
    :post,
    "#{PDS_HOST}/xrpc/com.atproto.repo.createRecord",
    headers: {
      "Authorization" => "Bearer #{session[:access_jwt]}",
      "Content-Type" => "application/json"
    },
    body: {
      repo: session[:did],
      collection: "app.bsky.feed.post",
      record: record
    }.to_json
  )
end

def preview_payload(post)
  text = compose_post_text(
    model: post[:model],
    title: post[:title],
    body: post[:body],
    permalink: post[:permalink]
  )
  {
    permalink: post[:permalink],
    url: absolute_url(post[:permalink]),
    title: post[:title],
    model: post[:model],
    image: absolute_image_url(post[:image]),
    text: text,
    date: post[:date].iso8601
  }
end

def seed_state!(force: false)
  state = load_state
  if !force && state["posted"].any?
    warn "state already has #{state['posted'].length} entries; use --force to reseed"
    return state
  end
  now = now_jst.iso8601
  state["posted"] = load_posts.select { |p| p[:date] <= now_jst }.map do |p|
    {
      "path" => relative_post_path(p[:path]),
      "permalink" => p[:permalink],
      "at" => now,
      "seeded" => true
    }
  end
  save_state!(state)
  puts "seeded #{state['posted'].length} posts into #{STATE_PATH}"
  state
end

def self_test!
  sample_body = <<~MD
    ![x]({{ '/assets/a.jpg' | relative_url }})

    私の手許には、電話の中に女学生が何人か住んでゐる。グロックボットとか云ふ仕掛けの中にゐて、すぐに返事をよこす。
  MD
  topics = topic_candidates("既読", sample_body)
  abort "topic should include GrokBot: #{topics.inspect}" unless topics.include?("GrokBot")

  texts = 20.times.map do |i|
    compose_post_text(
      model: "内田百閒",
      title: "既読",
      body: sample_body,
      permalink: "/kidoku-test-#{i}/"
    )
  end
  abort "empty text" if texts.any?(&:empty?)
  abort "over limit" if texts.any? { |t| t.each_grapheme_cluster.count > MAX_GRAPHEMES }
  uniq = texts.map { |t| t.lines.first.to_s.strip }.uniq
  abort "templates not varied enough: #{uniq.length}" if uniq.length < 5
  with_grok = texts.count { |t| t.include?("GrokBot") }
  abort "expected GrokBot in most samples, got #{with_grok}" if with_grok < 12
  kidoku = compose_post_text(
    model: "内田百閒",
    title: "既読",
    body: sample_body,
    permalink: "/kidoku/"
  )
  abort "kidoku should mention GrokBot: #{kidoku}" unless kidoku.include?("GrokBot")
  puts "self-test ok (#{uniq.length} unique first lines, GrokBot=#{with_grok}/20)"
end

def post_pending!(dry_run:, limit: nil)
  state = load_state
  pending = pending_posts(state: state)
  pending = pending.first(limit) if limit
  if pending.empty?
    puts "no pending posts"
    return 0
  end

  session = nil
  unless dry_run
    identifier = ENV["BLUESKY_IDENTIFIER"].to_s.strip
    password = ENV["BLUESKY_APP_PASSWORD"].to_s.strip
    if identifier.empty? || password.empty?
      warn "BLUESKY_IDENTIFIER / BLUESKY_APP_PASSWORD missing; skip"
      return 0
    end
    session = bluesky_login(identifier, password)
  end

  count = 0
  pending.each do |post|
    preview = preview_payload(post)
    puts "---"
    puts "permalink: #{preview[:permalink]}"
    puts "url: #{preview[:url]}"
    puts "model: #{preview[:model]}"
    puts "text:"
    puts preview[:text]
    puts "image: #{preview[:image] || '(none)'}"

    if dry_run
      count += 1
      next
    end

    embed = build_external_embed(session, post)
    result = create_bluesky_post(session, preview[:text], embed)
    state["posted"] << {
      "path" => relative_post_path(post[:path]),
      "permalink" => post[:permalink],
      "at" => now_jst.iso8601,
      "uri" => result["uri"],
      "cid" => result["cid"]
    }
    save_state!(state)
    count += 1
    puts "posted: #{result['uri']}"
  end
  count
end

def usage
  <<~USAGE
    Usage:
      ruby scripts/bluesky_post.rb seed [--force]
      ruby scripts/bluesky_post.rb pending
      ruby scripts/bluesky_post.rb post [--dry-run] [--limit N]
      ruby scripts/bluesky_post.rb self-test
  USAGE
end

def main
  command = ARGV.shift
  abort usage if command.nil?

  dry_run = false
  force = false
  limit = nil
  OptionParser.new do |o|
    o.on("--dry-run") { dry_run = true }
    o.on("--force") { force = true }
    o.on("--limit N", Integer) { |v| limit = v }
  end.parse!

  case command
  when "seed"
    seed_state!(force: force)
  when "pending"
    pending_posts.each do |p|
      prev = preview_payload(p)
      puts "#{prev[:date]}\t#{prev[:permalink]}\t#{prev[:model]}\t#{prev[:text].lines.first.to_s.strip}"
    end
  when "post"
    post_pending!(dry_run: dry_run, limit: limit)
  when "self-test"
    self_test!
  else
    abort usage
  end
end

main
