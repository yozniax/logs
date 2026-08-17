#!/usr/bin/env ruby
# frozen_string_literal: true

# 記事生成の補助。モデル候補・ランダム選択・下書きの骨格づくり。
# 本文の文豪文体は書かない。書くのは Cursor / 人間。

require "yaml"
require "date"
require "time"
require "optparse"
require "fileutils"
require "json"
require "net/http"
require "uri"
require "open3"

JST_OFFSET = "+09:00"

ROOT = File.expand_path("..", __dir__)
MODELS_PATH = File.join(ROOT, "_data", "models.yml")
TAG_SLUGS_PATH = File.join(ROOT, "_data", "tag_slugs.yml")

TARGET_CHARS = 800
CHAR_MIN = 700
CHAR_MAX = 900

CLUSTERS = %w[lyric essay vernacular idea classical].freeze

def load_models
  YAML.load_file(MODELS_PATH)
end

def load_tag_slugs
  YAML.load_file(TAG_SLUGS_PATH)
end

def find_model(models, name)
  models.find { |m| m["name"] == name }
end

def score_model(model, notes)
  text = notes.to_s
  score = 0
  Array(model["keywords"]).each do |kw|
    score += 2 if text.include?(kw)
  end
  Array(model["when"].to_s.split(/[、,]/)).each do |w|
    w = w.strip
    next if w.empty?
    score += 1 if text.include?(w)
  end
  score
end

def ranked(models, notes)
  models.map { |m| [m, score_model(m, notes)] }
        .sort_by { |m, s| [-s, m["name"]] }
end

def pick_diverse(models, count = 3)
  by_cluster = models.group_by { |m| m["cluster"] }
  picked = []
  CLUSTERS.cycle do |cluster|
    break if picked.length >= count
    pool = (by_cluster[cluster] || []) - picked
    next if pool.empty?
    picked << pool.sample
  end
  picked.first(count)
end

def suggest_models(models, notes, count = 3)
  ranked_list = ranked(models, notes)
  hits = ranked_list.select { |_, s| s.positive? }.map(&:first)
  if hits.empty?
    pick_diverse(models, count)
  else
    rest = pick_diverse(models - hits, [count - hits.length, 0].max)
    (hits + rest).first(count)
  end
end

def random_model(models)
  models.sample
end

def format_model_line(model, index = nil)
  prefix = index ? "#{index}. " : ""
  "#{prefix}#{model['name']} — #{model['when']}"
end

def suggest_markdown(models, notes)
  picks = suggest_models(models, notes)
  lines = ["メモから、次のモデルが合いそうです。番号か名前で選んでください。", ""]
  picks.each_with_index do |m, i|
    lines << format_model_line(m, i + 1)
  end
  lines << ""
  lines << "0. ランダム"
  lines << ""
  lines << "番号か名前、または 0 で選んでください。本文は #{TARGET_CHARS} 字程度です。"
  lines.join("\n")
end

def parse_issue_body(body)
  fields = { "メモ" => "", "モデル" => "", "タイトル" => "", "補足" => "" }
  current = nil
  body.to_s.each_line do |line|
    if line =~ /\A###\s+(.+?)\s*\z/
      current = $1.strip
      fields[current] ||= ""
    elsif current
      fields[current] += line
    end
  end
  fields.transform_values { |v| v.to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "") }
end

def now_jst
  Time.now.getlocal(JST_OFFSET)
end

def time_to_jst(time)
  time.getlocal(JST_OFFSET)
end

def format_front_matter_date(time)
  time_to_jst(time).strftime("%Y-%m-%d %H:%M:%S %z")
end

def parse_clock(hour, min, sec = 0)
  [hour.to_i, (min || 0).to_i, (sec || 0).to_i]
end

def parse_jst(input, now: now_jst)
  s = input.to_s.strip
  s = s.gsub(/[（(]JST[）)]/i, "").gsub(/\bJST\b/i, "").strip
  return now if s.empty? || %w[今 いま now].include?(s)

  if (m = s.match(/\A(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?(?:\s*[+-]\d{2}:?\d{2})?\z/))
    h, min, sec = parse_clock(m[4] || 0, m[5], m[6])
    return Time.new(m[1].to_i, m[2].to_i, m[3].to_i, h, min, sec, JST_OFFSET)
  end

  if (m = s.match(/\A(\d{4})\/(\d{1,2})\/(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\z/))
    h, min, sec = parse_clock(m[4] || 0, m[5], m[6])
    return Time.new(m[1].to_i, m[2].to_i, m[3].to_i, h, min, sec, JST_OFFSET)
  end

  base = now
  if s.start_with?("明後日")
    base += 2 * 86_400
    s = s.sub(/\A明後日\s*/, "")
  elsif s.start_with?("明日")
    base += 86_400
    s = s.sub(/\A明日\s*/, "")
  elsif s.start_with?("今日")
    s = s.sub(/\A今日\s*/, "")
  end

  if (m = s.match(/\A(\d{1,2})月(\d{1,2})日(?:\s*(\d{1,2})時(?:(\d{1,2})分)?)?\z/))
    h, min, = parse_clock(m[3] || 0, m[4])
    return Time.new(now.year, m[1].to_i, m[2].to_i, h, min, 0, JST_OFFSET)
  end

  if (m = s.match(/\A(\d{1,2}):(\d{2})(?::(\d{2}))?\z/)) || (m = s.match(/\A(\d{1,2})時(?:(\d{1,2})分)?\z/))
    h, min, sec = parse_clock(m[1], m[2], m[3])
    return Time.new(base.year, base.month, base.day, h, min, sec, JST_OFFSET)
  end

  Time.parse(s).getlocal(JST_OFFSET)
end

def classify_publish_at(time, now: now_jst)
  t = time_to_jst(time)
  n = time_to_jst(now)
  if t <= n
    { time: t, kind: "past", label: "#{format_front_matter_date(t)}（過去・即反映）" }
  else
    { time: t, kind: "future", label: "#{format_front_matter_date(t)}（未来・その時刻に反映）" }
  end
end

def extract_front_matter_date(markdown)
  fm = markdown.to_s[/\A---\n(.*?)\n---/m, 1]
  return nil unless fm
  line = fm.each_line.find { |l| l.start_with?("date:") }
  return nil unless line
  raw = line.sub(/\Adate:\s*/, "").strip.gsub(/\A["']|["']\z/, "")
  parse_jst(raw)
end

def each_post_time
  Dir[File.join(ROOT, "_posts", "*.md")].sort.map do |path|
    time = extract_front_matter_date(File.read(path))
    next unless time
    { path: path, time: time_to_jst(time) }
  end.compact
end

def due_posts(since:, now: now_jst)
  since_t = time_to_jst(since)
  now_t = time_to_jst(now)
  each_post_time.select { |p| p[:time] <= now_t && p[:time] > since_t }
end

def slugify(text)
  s = text.to_s.downcase
  s = s.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  s.empty? ? "note" : s
end

def archive_path(date)
  File.join(ROOT, "archive", date.strftime("%Y"), date.strftime("%m"), "index.md")
end

def ensure_archive!(date)
  path = archive_path(date)
  return path if File.exist?(path)

  FileUtils.mkdir_p(File.dirname(path))
  ym = date.strftime("%Y-%m")
  File.write(path, <<~MD)
    ---
    layout: archive_month
    title: "Archive — #{ym}"
    year_month: "#{ym}"
    permalink: /archive/#{date.strftime("%Y")}/#{date.strftime("%m")}/
    ---
  MD
  path
end

def post_filename(date, slug)
  File.join(ROOT, "_posts", "#{date.strftime("%Y-%m-%d")}-#{slug}.md")
end

X_STATUS_RE = %r{
  https?://(?:www\.)?(?:x\.com|twitter\.com|fxtwitter\.com|vxtwitter\.com)
  /(?:[A-Za-z0-9_]+/status|i/web/status|status)
  /(\d+)
}ix

URL_IN_BODY_RE = %r{(?:https?://|www\.)\S+|x\.com/\S+|twitter\.com/\S+|t\.co/\S+}i
DIRECT_IMAGE_RE = %r{https?://[^\s)>\"]+\.(?:jpe?g|png|webp|gif)(?:\?[^\s)>\"]*)?}i
STAGING_DIR = "/tmp/article-media"
ATTACHMENT_MAX_AGE = 3600
ATTACHMENT_SKIP_DIRS = %w[
  node_modules vendor .git .nvm go pkg cursor-server plugins
  assets/post-images cloud-agent-transcripts
].freeze

def extract_x_urls(text)
  text.to_s.scan(X_STATUS_RE).flatten.uniq.map do |id|
    { id: id, url: "https://x.com/i/status/#{id}" }
  end
end

def http_get_json(url, limit = 3)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = 8
  http.read_timeout = 10
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "BrilliantScapeArticleBot/1.0"
  res = http.request(req)
  if res.is_a?(Net::HTTPRedirection) && limit.positive?
    loc = res["location"]
    return http_get_json(loc, limit - 1) if loc
  end
  return nil unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
rescue StandardError
  nil
end

def http_get_text(url, limit = 3)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = 8
  http.read_timeout = 10
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "BrilliantScapeArticleBot/1.0"
  res = http.request(req)
  if res.is_a?(Net::HTTPRedirection) && limit.positive?
    loc = res["location"]
    return http_get_text(loc, limit - 1) if loc
  end
  return nil unless res.is_a?(Net::HTTPSuccess)
  res.body
rescue StandardError
  nil
end

def tweet_from_fx(id)
  %W[
    https://api.fxtwitter.com/status/#{id}
    https://api.vxtwitter.com/Twitter/status/#{id}
  ].each do |url|
    data = http_get_json(url)
    next unless data.is_a?(Hash)
    tweet = data["tweet"] || data
    text = tweet["text"] || tweet["full_text"]
    next if text.to_s.strip.empty?
    user = tweet["author"] || tweet["user"] || {}
    return {
      id: id,
      text: text.to_s.strip,
      name: (user["name"] || tweet["authorName"]).to_s,
      screen_name: (user["screen_name"] || user["screenName"] || tweet["authorHandle"]).to_s,
      media: media_urls_from_fx_tweet(tweet)
    }
  end
  nil
end

def tweet_from_oembed(id)
  url = "https://publish.twitter.com/oembed?omit_script=true&url=#{URI.encode_www_form_component("https://twitter.com/i/status/#{id}")}"
  data = http_get_json(url)
  return nil unless data.is_a?(Hash)
  html = data["html"].to_s
  text = html.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  return nil if text.empty?
  {
    id: id,
    text: text,
    name: data["author_name"].to_s,
    screen_name: "",
    media: []
  }
end

def fetch_x_status(id)
  tweet_from_fx(id) || tweet_from_oembed(id)
end

def fetch_x_from_notes(notes)
  extract_x_urls(notes).map do |item|
    tweet = fetch_x_status(item[:id])
    tweet ? item.merge(tweet) : item.merge(text: nil)
  end
end

def format_x_context(items)
  items.map do |item|
    if item[:text]
      who = [item[:name], item[:screen_name]].reject(&:empty?).join(" / ")
      who = "投稿" if who.empty?
      lines = ["Xの内容（本文にURLは書かない）:", who, item[:text]]
      media = Array(item[:media])
      lines << "画像:\n#{media.join("\n")}" unless media.empty?
      lines.join("\n")
    else
      "Xの取得に失敗: #{item[:id]}"
    end
  end.join("\n\n")
end

def strip_urls_for_notes(text)
  text.to_s.gsub(X_STATUS_RE, "").gsub(%r{https?://\S+}i, "").gsub(/\n{3,}/, "\n\n").strip
end

def body_has_url?(markdown)
  text = markdown.to_s.sub(/\A---\n.*?\n---\n/m, "")
  text = text.gsub(/!\[[^\]]*\]\([^\n]+\)/, "")
  text = text.gsub(/<!--.*?-->/m, "")
  text.match?(URL_IN_BODY_RE)
end

def image_public_path(date, slug)
  "/assets/post-images/#{date.strftime("%Y%m%d")}-#{slug}.jpg"
end

def image_dest_path(date, slug)
  File.join(ROOT, image_public_path(date, slug).sub(%r{\A/}, ""))
end

def twitter_orig_url(url)
  uri = URI(url)
  return url unless uri.host.to_s.include?("pbs.twimg.com")
  query = URI.decode_www_form(uri.query.to_s).to_h
  query["name"] = "orig"
  uri.query = URI.encode_www_form(query)
  uri.to_s
rescue URI::InvalidURIError
  url
end

def media_urls_from_fx_tweet(tweet)
  media = tweet.is_a?(Hash) ? tweet["media"] : nil
  return [] unless media.is_a?(Hash)
  items = Array(media["photos"]) + Array(media["all"])
  items.filter_map do |item|
    next unless item.is_a?(Hash)
    type = item["type"].to_s
    next unless type.empty? || type == "photo"
    url = item["url"] || item["original_url"]
    next if url.to_s.empty?
    twitter_orig_url(url)
  end.uniq
end

def looks_like_url?(value)
  value.to_s.match?(%r{\Ahttps?://}i)
end

def extract_direct_image_urls(text)
  text.to_s.scan(DIRECT_IMAGE_RE).map { |u| twitter_orig_url(u) }.uniq
end

def http_get_binary(url, limit = 5)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = 10
  http.read_timeout = 30
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "Mozilla/5.0 (compatible; BrilliantScapeArticleBot/1.0)"
  res = http.request(req)
  if res.is_a?(Net::HTTPRedirection) && limit.positive?
    loc = res["location"]
    loc = URI.join(url, loc).to_s if loc && !loc.start_with?("http")
    return http_get_binary(loc, limit - 1) if loc
  end
  return nil unless res.is_a?(Net::HTTPSuccess)
  { body: res.body, content_type: res["content-type"].to_s, url: url }
rescue StandardError
  nil
end

def jpeg?(bytes)
  bytes.to_s.b.start_with?("\xFF\xD8".b)
end

def png?(bytes)
  bytes.to_s.b.start_with?("\x89PNG".b)
end

def download_image_url(url)
  FileUtils.mkdir_p(STAGING_DIR)
  data = http_get_binary(url)
  abort "画像の取得に失敗: #{url}" unless data && data[:body] && !data[:body].empty?
  body = data[:body]
  type = data[:content_type]
  unless type.start_with?("image/") || jpeg?(body) || png?(body)
    abort "画像ではない: #{url}"
  end
  ext = type.include?("png") || png?(body) ? ".png" : ".jpg"
  path = File.join(STAGING_DIR, "download-#{Time.now.to_i}#{ext}")
  File.binwrite(path, body)
  path
end

def first_x_media_url(text)
  items = fetch_x_from_notes(text)
  items.flat_map { |item| Array(item[:media]) }.find { |u| !u.to_s.empty? }
end

def resolve_image_source(opts)
  file = opts[:image] || opts[:file]
  return file if file && File.file?(file.to_s)

  blob = [opts[:url], opts[:notes], looks_like_url?(file) ? file : nil].compact.join(" ")
  if blob.match?(X_STATUS_RE)
    media = first_x_media_url(blob)
    abort "Xに画像がありません" if media.to_s.empty?
    return download_image_url(media)
  end

  direct = extract_direct_image_urls(blob).first
  return download_image_url(direct) if direct

  found = find_attachments
  return found.first if found.any? && file.to_s.empty? && opts[:url].to_s.empty?

  abort "--file か --url が必要です（チャット添付はファイルにならないことが多い）"
end

def skip_attachment_dir?(path)
  normalized = path.to_s
  ATTACHMENT_SKIP_DIRS.any? { |part| normalized.include?("/#{part}/") || normalized.end_with?("/#{part}") }
end

def find_attachments(now: Time.now, max_age: ATTACHMENT_MAX_AGE)
  roots = [
    STAGING_DIR,
    "/tmp",
    File.join(ROOT),
    File.join(Dir.home, "Downloads"),
    Dir.home
  ]
  seen = {}
  roots.uniq.each do |root|
    next unless File.directory?(root)
    Dir.glob(File.join(root, "*.{jpg,jpeg,png,webp,heic,gif}"), File::FNM_CASEFOLD).each do |path|
      next unless File.file?(path)
      next if skip_attachment_dir?(path)
      next if now - File.mtime(path) > max_age
      begin
        seen[File.realpath(path)] = true
      rescue Errno::ENOENT
        next
      end
    end
  end
  seen.keys.sort_by { |path| -File.mtime(path).to_i }
end

def prepare_image(src, date:, slug:)
  dest = image_dest_path(date, slug)
  script = File.join(ROOT, "scripts", "resize_image.py")
  stdout, stderr, status = Open3.capture3("python3", script, "--file", src, "--out", dest)
  abort(stderr.empty? ? stdout : stderr) unless status.success?
  {
    dest: dest,
    public: image_public_path(date, slug),
    info: stdout.strip
  }
end

def image_markdown(title, public_path)
  "![#{title}]({{ '#{public_path}' | relative_url }})\n"
end

def scaffold_post(models, opts)
  published_at = opts[:date] ? time_to_jst(opts[:date]) : now_jst
  date = published_at
  model_name = opts[:model]
  model =
    if model_name.nil? || model_name == "random" || model_name == "ランダム"
      random_model(models)
    else
      find_model(models, model_name) or abort "unknown model: #{model_name}"
    end

  slugs = load_tag_slugs
  unless slugs[model["name"]]
    abort "tag_slugs.yml に #{model['name']} がありません"
  end

  title = opts[:title].to_s.strip
  title = "無題" if title.empty?
  slug = opts[:slug].to_s.strip
  slug = slugify(title) if slug.empty? || slug =~ /[^\x00-\x7F]/
  permalink = opts[:permalink].to_s.strip
  permalink = "/#{slug}/" if permalink.empty?
  permalink = "/#{permalink}" unless permalink.start_with?("/")
  permalink += "/" unless permalink.end_with?("/")

  path = post_filename(date, slug)
  abort "already exists: #{path}" if File.exist?(path) && !opts[:force]

  notes = opts[:notes].to_s.strip
  body =
    if notes.empty?
      "<!-- ここに #{CHAR_MIN}〜#{CHAR_MAX} 字で本文を書く -->\n"
    else
      "<!-- メモ。このまま公開せず、モデルの声で書き直す。\n#{notes}\n-->\n"
    end

  image_line = ""
  image_front = ""
  prepared = nil
  if opts[:image]
    prepared = prepare_image(opts[:image], date: published_at, slug: slug)
    image_front = "image: #{prepared[:public]}\n"
    image_line = "#{image_markdown(title, prepared[:public])}\n"
  end

  safe_title = title.gsub("\\", "").gsub('"', "")
  File.write(path, <<~MD)
    ---
    layout: post
    title: "#{safe_title}"
    date: #{format_front_matter_date(published_at)}
    tags:
      - #{model['name']}

    permalink: #{permalink}
    #{image_front}---

    #{image_line}#{body}
  MD

  archive = ensure_archive!(published_at)
  info = classify_publish_at(published_at)
  {
    path: path,
    archive: archive,
    model: model,
    title: title,
    slug: slug,
    published_at: published_at,
    publish_kind: info[:kind],
    publish_label: info[:label],
    image: prepared
  }
end

def count_body_chars(markdown)
  text = markdown.to_s.sub(/\A---\n.*?\n---\n/m, "")
  text = text.gsub(/!\[[^\]]*\]\([^\n]+\)/, "")
  text = text.gsub(/<!--.*?-->/m, "")
  text.gsub(/\s+/, "").length
end

def self_test(models)
  abort "models empty" if models.empty?
  names = models.map { |m| m["name"] }
  slugs = load_tag_slugs
  missing = names - slugs.keys
  abort "models.yml にあって tag_slugs.yml にない: #{missing.join(', ')}" unless missing.empty?
  extra = slugs.keys - names
  abort "tag_slugs.yml にあって models.yml にない: #{extra.join(', ')}" unless extra.empty?

  notes = "昼から酒を飲んだ。街は外国人ばかり。友だちが遅れた。"
  picks = suggest_models(models, notes)
  abort "suggest must return 3" unless picks.length == 3
  abort "suggest names missing" unless picks.all? { |m| m["name"] }

  r = random_model(models)
  abort "random failed" unless r && r["name"]

  dazai = find_model(models, "太宰治")
  abort "太宰 missing" unless dazai
  abort "太宰 should score on 酒" if score_model(dazai, notes) <= 0

  empty_picks = suggest_models(models, "zzzz-no-keywords")
  abort "fallback must return 3" unless empty_picks.length == 3
  clusters = empty_picks.map { |m| m["cluster"] }.uniq
  abort "fallback should span clusters" if clusters.length < 2

  issue = parse_issue_body(<<~MD)
    ### メモ
    今日は花粉症がつらい

    ### モデル
    おまかせ（候補を3つ出してほしい）
  MD
  abort "issue memo parse" unless issue["メモ"].include?("花粉症")
  abort "issue model parse" unless issue["モデル"].include?("おまかせ")

  body = "あ" * 800
  abort "char count" unless count_body_chars("---\ntitle: x\n---\n\n#{body}") == 800

  frozen = Time.new(2026, 8, 15, 1, 0, 0, JST_OFFSET)
  past = parse_jst("8月10日 21時", now: frozen)
  abort "parse 8月10日" unless past.year == 2026 && past.month == 8 && past.day == 10 && past.hour == 21
  abort "parse 8月10日 offset" unless past.utc_offset == 9 * 3600
  tomorrow = parse_jst("明日 9時", now: frozen)
  abort "parse 明日" unless tomorrow.day == 16 && tomorrow.hour == 9
  iso = parse_jst("2026-08-20 09:00:00 +0900")
  abort "parse iso" unless iso.day == 20 && iso.hour == 9
  abort "classify past" unless classify_publish_at(past, now: frozen)[:kind] == "past"
  abort "classify future" unless classify_publish_at(iso, now: frozen)[:kind] == "future"
  abort "fm date" unless format_front_matter_date(iso) == "2026-08-20 09:00:00 +0900"

  due = due_posts(
    since: Time.new(2026, 8, 15, 0, 0, 0, JST_OFFSET),
    now: Time.new(2026, 8, 20, 9, 5, 0, JST_OFFSET)
  )
  abort "due helper" unless due.is_a?(Array)

  urls = extract_x_urls("見て https://x.com/yozniax/status/1234567890123456789 これ")
  abort "extract x" unless urls.length == 1 && urls.first[:id] == "1234567890123456789"
  abort "strip urls" unless strip_urls_for_notes("見て https://x.com/yozniax/status/1 これ").include?("見て")
  with_url = "---\ntitle: x\n---\n\n本文 https://x.com/a/status/1\n"
  abort "url check should catch" unless body_has_url?(with_url)
  abort "url check false positive" if body_has_url?("---\nimage: /assets/post-images/a.jpg\n---\n\n![題]({{ '/assets/post-images/a.jpg' | relative_url }})\n本文だけ\n")
  abort "image md count" unless count_body_chars("---\ntitle: x\n---\n\n![題]({{ '/a.jpg' | relative_url }})\n#{"あ" * 800}\n") == 800

  orig = twitter_orig_url("https://pbs.twimg.com/media/HPSIjQCbMAA94Ka.jpg")
  abort "orig url" unless orig.include?("name=orig")
  media = media_urls_from_fx_tweet(
    "media" => {
      "photos" => [{ "type" => "photo", "url" => "https://pbs.twimg.com/media/abc.jpg" }],
      "all" => [{ "type" => "photo", "url" => "https://pbs.twimg.com/media/abc.jpg" }]
    }
  )
  abort "media uniq" unless media == ["https://pbs.twimg.com/media/abc.jpg?name=orig"]
  abort "direct image" unless extract_direct_image_urls("x https://pbs.twimg.com/media/abc.jpg y").length == 1
  ctx = format_x_context(
    [{ text: "hi", name: "a", screen_name: "b", media: ["https://pbs.twimg.com/media/abc.jpg?name=orig"] }]
  )
  abort "format media" unless ctx.include?("画像:")
  abort "find type" unless find_attachments(now: Time.now, max_age: 1).is_a?(Array)

  puts "self-test ok (#{models.length} models)"
end

def usage
  <<~TXT
    Usage:
      ruby scripts/article.rb list
      ruby scripts/article.rb suggest [--notes TEXT | --file PATH]
      ruby scripts/article.rb random
      ruby scripts/article.rb issue-comment --file PATH
      ruby scripts/article.rb scaffold --model NAME|random [--title T] [--slug S] [--notes TEXT] [--date WHEN] [--image FILE]
      ruby scripts/article.rb prepare-image --file FILE|--url URL --date WHEN --slug SLUG
      ruby scripts/article.rb find-attachment
      ruby scripts/article.rb fetch-x --notes TEXT
      ruby scripts/article.rb check-urls --file PATH
      ruby scripts/article.rb when --date WHEN
      ruby scripts/article.rb due --since ISO8601
      ruby scripts/article.rb count --file PATH
      ruby scripts/article.rb self-test
  TXT
end

def read_notes(opts)
  return File.read(opts[:file]) if opts[:file] && File.exist?(opts[:file])
  return opts[:notes] if opts[:notes]
  return $stdin.read if !$stdin.tty?
  ""
end

def main
  command = ARGV.shift
  abort usage if command.nil? || command == "-h" || command == "--help"

  opts = {}
  OptionParser.new do |o|
    o.on("--notes TEXT") { |v| opts[:notes] = v }
    o.on("--file PATH") { |v| opts[:file] = v }
    o.on("--model NAME") { |v| opts[:model] = v }
    o.on("--title TEXT") { |v| opts[:title] = v }
    o.on("--slug TEXT") { |v| opts[:slug] = v }
    o.on("--permalink TEXT") { |v| opts[:permalink] = v }
    o.on("--date WHEN") { |v| opts[:date] = parse_jst(v) }
    o.on("--since ISO8601") { |v| opts[:since] = Time.parse(v) }
    o.on("--image FILE") { |v| opts[:image] = v }
    o.on("--url URL") { |v| opts[:url] = v }
    o.on("--force") { opts[:force] = true }
  end.parse!

  models = load_models

  case command
  when "list"
    models.each { |m| puts "#{m['name']}\t#{m['slug']}\t#{m['when']}" }
  when "suggest"
    notes = read_notes(opts)
    abort "notes required" if notes.strip.empty?
    puts suggest_markdown(models, notes)
  when "random"
    m = random_model(models)
    puts "#{m['name']}\t#{m['when']}"
  when "issue-comment"
    body = File.read(opts[:file] || abort("--file required"))
    fields = parse_issue_body(body)
    notes = [fields["メモ"], fields["補足"]].reject(&:empty?).join("\n")
    choice = fields["モデル"]
    if choice.nil? || choice.empty? || choice.include?("おまかせ")
      puts suggest_markdown(models, notes)
    elsif choice.include?("ランダム")
      m = random_model(models)
      puts "ランダムで **#{m['name']}** を選びました（#{m['when']}）。#{TARGET_CHARS} 字程度で書きます。"
    else
      m = find_model(models, choice)
      if m
        puts "モデルは **#{m['name']}** です（#{m['when']}）。#{TARGET_CHARS} 字程度で書きます。"
      else
        puts suggest_markdown(models, notes)
      end
    end
  when "scaffold"
    result = scaffold_post(models, opts.merge(notes: read_notes(opts)))
    puts "wrote #{result[:path]}"
    puts "model #{result[:model]['name']}"
    puts "archive #{result[:archive]}"
    puts "publish #{result[:publish_label]}"
    puts "image #{result[:image][:public]}" if result[:image]
  when "prepare-image"
    src = resolve_image_source(opts)
    date = opts[:date] || now_jst
    slug = opts[:slug].to_s.strip
    abort "--slug required" if slug.empty?
    result = prepare_image(src, date: date, slug: slug)
    puts result[:info]
    puts result[:public]
  when "find-attachment"
    found = find_attachments
    if found.empty?
      puts "none"
      exit 1
    end
    found.each { |path| puts path }
  when "fetch-x"
    notes = read_notes(opts)
    abort "notes required" if notes.strip.empty?
    items = fetch_x_from_notes(notes)
    abort "XのURLが見つかりません" if items.empty?
    puts format_x_context(items)
    rest = strip_urls_for_notes(notes)
    puts "\nメモ（URL除去）:\n#{rest}" unless rest.empty?
  when "check-urls"
    path = opts[:file] or abort "--file required"
    markdown = File.read(path)
    if body_has_url?(markdown)
      warn "本文にURLがあります。取り除いてください。"
      exit 1
    end
    puts "no urls"
  when "when"
    t = opts[:date] || now_jst
    info = classify_publish_at(t)
    puts "#{info[:kind]}\t#{info[:label]}"
  when "due"
    since = opts[:since] or abort "--since required"
    posts = due_posts(since: since)
    posts.each { |p| puts "#{format_front_matter_date(p[:time])}\t#{p[:path]}" }
    exit(posts.empty? ? 1 : 0)
  when "count"
    path = opts[:file] or abort "--file required"
    n = count_body_chars(File.read(path))
    puts "#{n} 字（目安 #{CHAR_MIN}〜#{CHAR_MAX}）"
    exit(n.between?(CHAR_MIN, CHAR_MAX) ? 0 : 1)
  when "self-test"
    self_test(models)
  else
    abort usage
  end
end

main
