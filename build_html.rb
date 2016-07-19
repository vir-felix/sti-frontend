#!/usr/bin/env ruby

require 'pp'
require 'erb'
require 'yaml'
require 'kramdown'
require 'fileutils'

def read_file(relative_path)
  File.read(File.join(Dir.pwd, relative_path))
end

def render_path(*path_parts)
  path = path_parts.map do |part|
    if part.length <= 1
      nil
    elsif part[-1] == '/'
      part
    else
      "#{part}/"
    end
  end
  path.join
end

@locales_path = "content"
@export_path = "build/site"
@translations_ready = YAML.load(read_file('translations-ready.yml')).uniq.sort

class Language
  @@locales = Array.new
  attr_reader :language, :language_name, :questionnaire_language, :backend

  def initialize(language, language_name, questionnaire_language, backend)
    @language, @language_name, @questionnaire_language, @backend = language, language_name, questionnaire_language, backend
    @@locales.push self
  end

  def self.locales
    @@locales
  end
end

def locales_init
  Dir.foreach(@locales_path) do |language|
    locale_path = File.join(@locales_path, language)
    next if language == '.' or language == '..' or not File.directory?(locale_path) or not @translations_ready.include?(language)
    config_path = File.join(render_path(@locales_path, language), "config.yml")
    locale_raw = YAML.load_file(config_path)
    new_locale = Language.new locale_raw["language"], locale_raw["language_name"], locale_raw["questionnaire_language"], locale_raw["backend"]
  end
  Language.locales.sort! {|x, y| x.language <=> y.language}
end

def walk(path, &process_file)
  Dir.foreach(path) do |file|
    new_path = File.join(path, file)
    if file == '.' or file == '..'
      next
    elsif File.directory?(new_path)
      walk(new_path, &process_file)
    elsif file =~ /.*\.md/
      yield(path, file)
    end
  end
end

def create_dir(path)
  parts = path.split('/')
  parts.each_with_index do |part, i|
    parts_path = parts[0..i].join('/')
    (Dir.mkdir parts_path) rescue Errno::EEXIST
  end
end

def render_partial(site_config, partial_name)
  erb = ERB.new(read_file("layouts/_#{partial_name}.html.erb"))
  obj = Object.new
  obj.instance_variable_set(:@config, site_config)
  "\n{::nomarkdown}\n" + erb.result(obj.instance_eval{binding}) + "{:/}\n"
end

def transform(site_config, locale, html)
  block_pattern = /{{([^}]*)}}/

  if block_line = html[block_pattern, 1]
    block_it = block_line.strip.split
    action   = block_it.shift

    if block_it.count > 1
      id_part = block_it.join('__').downcase
    else
      id_part = block_it.first.downcase
    end

    case action
    when 'BEGIN'
      case id_part
      when 'questionnaire-iframe'
        html.sub! block_pattern, render_partial(site_config, 'questionnaire')
      when 'navigation'
        html.sub! block_pattern, "\n{::nomarkdown}\n<div class=\"#{id_part}\">\n{:/}\n"
      when 'counter',
           'home__specialised-services',
           'home__traffic-management',
           'home__zero-rating'
        html.sub! block_pattern, "<div class=\"#{id_part}\">"
      when 'home__video', 'home__newsletter'
        html.sub! block_pattern, "
          <div class=\"#{id_part}__outer\">
          <div class=\"#{id_part}__inner\">
          <div class=\"#{id_part}__content\">
        " + render_partial(site_config, id_part.split('__').last)
      else
        html.sub! block_pattern, "
          <div class=\"#{id_part}__outer\">
          <div class=\"#{id_part}__inner\">
          <div class=\"#{id_part}__content\">
        "
      end
    when 'END'
      case id_part
      when 'questionnaire-iframe'
        html.sub! block_pattern, ''
      when 'navigation'
        tail = "\n{::nomarkdown}\n<select name=\"locale\" id=\"locale\" autocomplete=\"off\">"
        Language.locales.each do |lang|
          if lang == locale
            tail << "<option value=\"#{lang.language}\" selected=\"selected\">#{lang.language_name}</option>"
          else
            tail << "<option value=\"#{lang.language}\">#{lang.language_name}</option>"
          end
        end
        tail << "</select></div>\n{:/}\n"

        html.sub! block_pattern, tail
      when 'counter'
        tail = "\n{::nomarkdown}\n<div id=\"count-tooltip\">"
        tail << "savetheinternet.eu: <span id=\"counter-sti\"></span><br />"
        tail << "Avaaz: <span id=\"counter-avaaz\"></span><br />"
        tail << "savenetneutrality.eu: <span id=\"counter-snn\"></span><br />"
        tail << "OpenMedia: <span id=\"counter-om\"></span><br />"
        tail << "Access Now: <span id=\"counter-access\"></span><br />"
        tail << "</div></div>\n{:/}\n"

        html.sub! block_pattern, tail
      when 'home__specialised-services',
           'home__traffic-management',
           'home__zero-rating'
        html.sub! block_pattern, '</div>'
      else
        html.sub! block_pattern, '
          </div>
          </div>
          </div>
        '
      end
    when 'ANCHOR'
      html.sub! block_pattern, "\n{::nomarkdown}\n<span id=\"#{id_part}\"></span>\n{:/}\n"
    when 'IMG'
      case id_part
      when 'roadmap'
        html.sub! block_pattern, "\n{::nomarkdown}\n<img src=\"./images/net_neutrality_roadmap.svg\" alt=\"Roadmap\">\n{:/}\n"
      end
    when 'LOGOS'
      case id_part
      when 'made-by'
        html.sub! block_pattern, render_partial(site_config, 'made-by')
      when 'supported-by'
        html.sub! block_pattern, render_partial(site_config, 'supported-by')
      end
    end
    transform site_config, locale, html
  else
    (render_partial(site_config, 'head') + html).gsub /^ */, ''
  end
end

def build_site(locale)
  export_locale = render_path @export_path, locale.language
  import_locale = render_path @locales_path, locale.language
  site_config = YAML.load read_file("#{import_locale}/config.yml")
  puts "[#{locale.language}] Building site #{locale.language_name}"
  
  if Dir.exists?("#{import_locale}images/")
    create_dir "#{export_locale}images/"
    FileUtils.copy_entry("#{import_locale}images/", "#{export_locale}images/")
  end

  walk(import_locale) do |path, content_file_name|
    relative_path = render_path path.split('/')[2..-1].join('/')
    target_path   = render_path export_locale, relative_path

    layout_path = File.join(render_path("layouts"), "site.html.erb")
    target_file_name = content_file_name.split('.')[0..-2].push('html').join('.')

    # create html from kramdown flavoured markdown
    content_kramdown = transform site_config, locale, File.read(File.join(path, content_file_name))

    document = Kramdown::Document.new(content_kramdown, template: layout_path, parse_block_html: true, auto_ids: false)

    # write html
    create_dir target_path
    target_file = File.new File.join(target_path, target_file_name), 'w'
    target_file << document.to_html
  end
end

def build_all
  Language.locales.each do |locale|
    build_site locale
  end
end

locales_init
build_all

# TODO: trigger build via travis on git master push
