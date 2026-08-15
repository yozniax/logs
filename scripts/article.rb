#!/usr/bin/env ruby
# frozen_string_literal: true

# 記事生成の補助。モデル候補・ランダム選択・下書きの骨格づくり。
# 本文の文豪文体は書かない。書くのは Cursor / 人間。

require "yaml"
require "date"
require "time"
require "optparse"
require "fileutils"

JST_OFFSET = "+09:00"

ROOT = File.expand_path("..", __dir__)
MODELS_PATH = File.join(ROOT, "_data", "models.yml")
TAG_SLUGS_PATH = File.join(ROOT, "_data", "tag_slugs.yml")

TARGET_CHARS = 800
CHAR_MIN = 700
CHAR_MAX = 900

CLUSTERS = %w[lyric essay vernacular idea].freeze

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

  safe_title = title.gsub("\\", "").gsub('"', "")
  File.write(path, <<~MD)
    ---
    layout: post
    title: "#{safe_title}"
    date: #{format_front_matter_date(published_at)}
    tags:
      - #{model['name']}

    permalink: #{permalink}
    ---

    #{body}
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
    publish_label: info[:label]
  }
end

def count_body_chars(markdown)
  text = markdown.to_s.sub(/\A---\n.*?\n---\n/m, "")
  text = text.gsub(/!\[[^\]]*\]\([^)]+\)/, "")
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

  puts "self-test ok (#{models.length} models)"
end

def usage
  <<~TXT
    Usage:
      ruby scripts/article.rb list
      ruby scripts/article.rb suggest [--notes TEXT | --file PATH]
      ruby scripts/article.rb random
      ruby scripts/article.rb issue-comment --file PATH
      ruby scripts/article.rb scaffold --model NAME|random [--title T] [--slug S] [--notes TEXT] [--date WHEN]
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
