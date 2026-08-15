#!/usr/bin/env ruby
# frozen_string_literal: true

# 記事生成の補助。モデル候補・ランダム選択・下書きの骨格づくり。
# 本文の文豪文体は書かない。書くのは Cursor / 人間。

require "yaml"
require "date"
require "optparse"
require "fileutils"

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
  date = opts[:date] || Date.today
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
    date: #{date.strftime("%Y-%m-%d")}
    tags:
      - #{model['name']}

    permalink: #{permalink}
    ---

    #{body}
  MD

  archive = ensure_archive!(date)
  {
    path: path,
    archive: archive,
    model: model,
    title: title,
    slug: slug
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

  puts "self-test ok (#{models.length} models)"
end

def usage
  <<~TXT
    Usage:
      ruby scripts/article.rb list
      ruby scripts/article.rb suggest [--notes TEXT | --file PATH]
      ruby scripts/article.rb random
      ruby scripts/article.rb issue-comment --file PATH
      ruby scripts/article.rb scaffold --model NAME|random [--title T] [--slug S] [--notes TEXT]
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
    o.on("--date DATE") { |v| opts[:date] = Date.parse(v) }
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
