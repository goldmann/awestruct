require 'ostruct'
require 'find'
require 'compass'
require 'ninesixty'
require 'bootstrap-sass'
require 'time'
require 'notifier'

require 'hashery/opencascade'

require 'awestruct/config'
require 'awestruct/site'
require 'awestruct/haml_file'
require 'awestruct/erb_file'
require 'awestruct/textile_file'
require 'awestruct/coffeescript_file'
require 'awestruct/markdown_file'
require 'awestruct/asciidoc_file'
require 'awestruct/sass_file'
require 'awestruct/scss_file'
require 'awestruct/orgmode_file'
require 'awestruct/verbatim_file'
require 'awestruct/restructuredtext_file'

require 'awestruct/context_helper'

require 'awestruct/extensions/pipeline'
require 'awestruct/extensions/posts'
require 'awestruct/extensions/indexifier'
require 'awestruct/extensions/data_dir'
require 'awestruct/extensions/paginator'
require 'awestruct/extensions/atomizer'
require 'awestruct/extensions/tagger'
require 'awestruct/extensions/tag_cloud'
require 'awestruct/extensions/intense_debate'
require 'awestruct/extensions/disqus'
require 'awestruct/extensions/flattr'
require 'awestruct/extensions/google_analytics'
require 'awestruct/extensions/partial'
require 'awestruct/extensions/sitemap'
require 'awestruct/extensions/cachebuster'
require 'awestruct/extensions/obfuscate'
require 'awestruct/extensions/relative'
require 'awestruct/extensions/assets'
require 'awestruct/extensions/minify'
require 'awestruct/extensions/coffeescripttransform'

require 'awestruct/util/inflector'
require 'awestruct/util/default_inflections'

module Awestruct

  class Engine

    attr_reader :config
    attr_reader :dir
    attr_reader :site

    def initialize(config)
      @dir    = config.input_dir
      @config = config

      @site   = Site.new( config )
      @site.engine = self

      @helpers = []
      @max_site_mtime = nil
      adjust_load_path
    end

    def skin_dir
      @site.skin_dir
    end

    def config
      @config
    end

    def generate(profile=nil, base_url=nil, default_base_url=nil, force=false)
      @base_url         = base_url
      @default_base_url = default_base_url
      @max_site_mtime = nil
      load_site_yaml(profile)
      load_yamls
      set_base_url
      load_layouts
      load_pages
      load_extensions
      set_urls(site.pages)
      configure_compass
      generate_files(force)
    end

    def find_and_load_site_page(simple_path)
      path_glob = File.join( config.input_dir, simple_path + '.*' )
      candidates = Dir[ path_glob ]
      return nil if candidates.empty?
      throw Exception.new( "too many choices for #{simple_path}" ) if candidates.size != 1
      dir_pathname = Pathname.new( dir )
      path_name = Pathname.new( candidates[0] )
      relative_path = path_name.relative_path_from( dir_pathname ).to_s
      load_page( candidates[0], :relative_path => relative_path )
    end

    def load_site_page(relative_path)
      load_page( File.join( dir, relative_path ) )
    end

    def load_page(path, options = {})
      page = nil
      if ( options[:relative_path].nil? )
        #dir_pathname = Pathname.new( dir )
        #path_name = Pathname.new( path )
        #relative_path = path_name.relative_path_from( dir_pathname ).to_s
      end

      fixed_relative_path = ( options[:relative_path].nil? ? nil : File.join( '', options[:relative_path] ) )

      if ( path =~ /\.haml$/ )
        page = HamlFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.erb$/ )
        page = ErbFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.textile$/ )
        page = TextileFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.coffee$/ )
        page = CoffeeScriptFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.md$/ )
        page = MarkdownFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.(asciidoc|adoc)$/ )
        page = AsciiDocFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.sass$/ )
        page = SassFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.scss$/ )
        page = ScssFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.org$/ )
        page = OrgmodeFile.new( site, path, fixed_relative_path, options )
      elsif ( path =~ /\.rst$/ )
        page = ReStructuredTextFile.new( site, path, fixed_relative_path, options )
      elsif ( File.file?( path ) )
        page = VerbatimFile.new( site, path, fixed_relative_path, options )
      end
      page
    end

    def create_context(page, content='')
      context = OpenStruct.new( :site=>site, :content=>content )
      context.extend( Awestruct::ContextHelper )
      @helpers.each do |h|
        context.extend( h )
      end
      context.page = page
      class << context
        def interpolate_string(str)
          if site.interpolate
            str = str || ''
            str = str.gsub( /\\/, '\\\\\\\\' )
            str = str.gsub( /\\\\#/, '\\#' )
            str = str.gsub( '@', '\@' )
            str = "%@#{str}@"
            result = instance_eval( str )
            result
          else
            str || ''
          end
        end
        def evaluate_erb(erb)
          erb.result( binding )
        end
      end
      context
    end

    def set_urls(pages)
      pages.each do |page|
        page_path = page.output_path
        if ( page_path =~ /^\// )
          page.url = page_path
        else
          page.url = "/#{page_path}"
        end
        if ( page.url =~ /^(.*\/)index.html$/ )
          page.url = $1
        end
      end
    end

    private

    def adjust_load_path
      ext_dir = File.join( config.extension_dir )
      if ( $LOAD_PATH.index( ext_dir ).nil? )
        $LOAD_PATH << ext_dir
      end
      if ( skin_dir )
        skin_ext_dir = File.join( skin_dir, config.extension_dir )
        if ( $LOAD_PATH.index( skin_ext_dir ).nil? )
          $LOAD_PATH << skin_ext_dir
        end
      end
    end

    def configure_compass
      Compass.configuration.project_type    = :standalone
      Compass.configuration.project_path    = dir
      Compass.configuration.sass_dir        = 'stylesheets'
      
      site.images_dir      = File.join( config.output_dir, 'images' )
      site.stylesheets_dir = File.join( config.output_dir, 'stylesheets' )
      site.javascripts_dir = File.join( config.output_dir, 'javascripts' )

      Compass.configuration.css_dir         = site.css_dir
      Compass.configuration.javascripts_dir = 'javascripts'
      Compass.configuration.images_dir      = 'images'

    end

    def set_base_url
      if ( @base_url )
        site.base_url = @base_url
      end

      if ( site.base_url.nil? )
        site.base_url = @default_base_url
      end

      if ( site.base_url )
        if ( site.base_url =~ /^(.*)\/$/ )
          site.base_url = $1
        end
      end
    end

    def generate_files(force)
      site.pages.each do |page|
        begin
          generate_page( page, force )
        rescue Exception => e
          Notifier.notify(:title=>"Error generating page #{page.name}", :message=>e.to_s)
          puts "Cannot render page #{page.source_path}. #{e.to_s}"
        end
      end
    end

    def generate_page(page, force)
      return unless requires_generation?(page, force)

      generated_path = File.join( config.output_dir, page.output_path )
      $stderr.puts "rendering #{page.source_path} -> #{page.output_path}"
      rendered = render_page(page, true)
      FileUtils.mkdir_p( File.dirname( generated_path ) )
      File.open( generated_path, 'w' ) do |file|
        file << rendered
      end
    end

    def requires_generation?(page, force)
      return true if force
      generated_path = File.join( config.output_dir, page.output_path )
      return true unless File.exist?( generated_path )
      now = Time.now
      generated_mtime = File.mtime( generated_path )
      return true if ( ( @max_site_mtime || Time.at(0) ) > generated_mtime )

      while true
        now = Time.now
        source_mtime = File.mtime( page.source_path )
        if ( now - source_mtime > 1 )
          if ( source_mtime - generated_mtime >= 0 )
            return true
          else
            break
          end
        end
        sleep 0.1
      end

      ext = page.output_extension
      layout_name = page.layout
      while ( ! layout_name.nil? )
        layout = site.layouts[ layout_name + ext ]
        if ( layout )
          layout_mtime = File.mtime( layout.source_path )
          return true if layout_mtime > generated_mtime
          layout_name = layout.layout
        else
          return false
        end
      end
      false
    end

    def render_page(page, with_layouts=true)
      context = create_context( page )
      rendered = page.render( context )
      if ( with_layouts )
        cur = page
        while ( ! cur.nil? && ! cur.layout.nil? )
          layout_name = cur.layout.to_s + page.output_extension
          cur = site.layouts[ layout_name ]
          if ! cur.nil?
            context.content = rendered.to_s
            rendered = cur.render( context )
          end
        end
      end
      @transformers.each do |transformer|
        rendered = transformer.transform(site, page, rendered)
      end if @transformers
      rendered
    end

    def load_layouts
      site.layouts.clear
      dir_pathname = Pathname.new( dir )
      Dir[ File.join( config.layouts_dir, '*.haml' ) ].each do |layout_path|
        layout_pathname = Pathname.new( layout_path )
        relative_path = layout_pathname.relative_path_from( dir_pathname ).to_s
        name = File.basename( layout_path, '.haml' )
        site.layouts[ name ] =  load_page( layout_path, :relative_path => relative_path )
      end
      if ( skin_dir )
        skin_dir_pathname = Pathname.new( skin_dir )
        Dir[ File.join( skin_dir, config.layouts_dir, '*.haml' ) ].each do |layout_path|
          layout_pathname = Pathname.new( layout_path )
          relative_path = layout_pathname.relative_path_from( skin_dir_pathname ).to_s
          name = File.basename( layout_path, '.haml' )
          unless ( site.layouts.key?( name ) )
            site.layouts[ name ] =  load_page( layout_path, :relative_path => relative_path )
          end
        end
      end
    end

    def load_site_yaml(profile)
      site_yaml = File.join( config.config_dir, 'site.yml' )
      if ( File.exist?( site_yaml ) )
        mtime = File.mtime( site_yaml )
        if ( mtime > ( @max_site_mtime || Time.at(0) ) )
          @max_site_mtime = mtime
        end
        data = YAML.load( File.read( site_yaml ) )
        site.interpolate = true
        profile_data = {}
        data.each do |k,v|
          if ( ( k == 'profiles' ) && ( ! profile.nil? ) )
            profile_data = ( v[profile] || {} )
          else
            site.send( "#{k}=", v )
          end
        end if data
        site.profile = profile

        profile_data.each do |k,v|
          site.send( "#{k}=", v )
        end
      end
    end

    def load_yamls
      Dir[ File.join( config.config_dir, '*.yml' ) ].each do |yaml_path|
        load_yaml( yaml_path ) unless ( File.basename( yaml_path ) == 'site.yml' )
      end
    end

    def load_yaml(yaml_path)
      mtime = File.mtime( yaml_path )
      if ( mtime > ( @max_site_mtime || Time.at(0) ) )
        @max_site_mtime = mtime
      end
      data = YAML.load( File.read( yaml_path ) )
      name = File.basename( yaml_path, '.yml' )
      site.send( "#{name}=", massage_yaml( data ) )
    end

    def inherit_front_matter( page )
      layout = page.layout
      while ( layout )
        layout_name = layout.to_s + page.output_extension
        current = site.layouts[ layout_name ]
        raise "Unknown layout '#{layout_name}' #{site.layouts.keys} for page #{page}" if current == nil
        current.front_matter.each { |k,v| page.send( "#{k}=", v ) unless page.send( "#{k}" ) } if current
        layout = current.layout
      end
    end

    def load_pages()
      visited_pages = {}
      dir_pathname = Pathname.new( dir )
      Find.find( dir ) do |path|
        next if path == dir
        basename = File.basename( path )
        if ( basename == '.htaccess' )
          #special case
        elsif ( basename =~ /^[_.]/ )
          Find.prune
          next
        end
        file_pathname = Pathname.new( path )
        relative_path = file_pathname.relative_path_from( dir_pathname ).to_s
        if config.ignore.include?(relative_path)
          Find.prune
          next
        end
        page = load_page( path, :relative_path => relative_path )
        if ( page )
          inherit_front_matter( page )
          visited_pages[ path ] = page
        end
      end

      if ( skin_dir )
        skin_dir_pathname = Pathname( skin_dir )
        Find.find( skin_dir ) do |path|
          next if path == skin_dir
          basename = File.basename( path )
          if ( basename == '.htaccess' )
            #special case
          elsif ( basename =~ /^[_.]/ )
            Find.prune
            next
          end
          file_pathname = Pathname.new( path )
          relative_path = file_pathname.relative_path_from( skin_dir_pathname ).to_s
          if config.ignore.include?(relative_path)
            Find.prune
            next
          end
          page = load_page( path, :relative_path => relative_path )
          if ( page )
            inherit_front_matter( page )
            visited_pages[ path ] = page
          end
        end
      end

      site.pages = visited_pages.values
    end

    def massage_yaml(obj)
      result = obj
      case ( obj )
        when Hash
          result = {}
          obj.each do |k,v|
            result[k] = massage_yaml(v)
          end
          result = OpenCascade.new(result.inject({}) { |memo, (k, v)| memo[k.to_sym] = v; memo })
        when Array
          result = []
          obj.each do |v|
            result << massage_yaml(v)
          end
      end
      result
    end

    def load_extensions
      watched_dirs = []
      pipeline = nil
      skin_pipeline = nil

      ext_dir = File.join( config.extension_dir )
      pipeline_file = File.join( ext_dir, 'pipeline.rb' )
      if ( File.exists?( pipeline_file ) )
        pipeline = eval(File.read( pipeline_file ), nil, pipeline_file, 1)
        @helpers = pipeline.helpers || []
        @transformers = pipeline.transformers || []
        watched_dirs << ext_dir.to_s
      end

      if ( skin_dir )
        skin_ext_dir = File.join( skin_dir, config.extension_dir.sub(/^#{Dir.pwd}/, "") )
        if ( $LOAD_PATH.index( skin_ext_dir ).nil? )
          $LOAD_PATH << skin_ext_dir
        end
        skin_pipeline_file = File.join( skin_ext_dir, 'pipeline.rb' )
        if ( File.exists?( skin_pipeline_file ) )
          skin_pipeline = eval(File.read( skin_pipeline_file ), nil, skin_pipeline_file, 1)
          @helpers = ( @helpers + skin_pipeline.helpers || [] ).flatten
          @transformers = ( @transformers + skin_pipeline.transformers || [] ).flatten
          watched_dirs << skin_dir.to_s
        end
      end

      #if _partials directory (from Partial helper) is present, watch
      partials = File.join( '_partials' )
      if ( File.exists?( partials ) )
        watched_dirs << partials
      end

      pipeline.watch(watched_dirs) if pipeline
      skin_pipeline.watch(watched_dirs) if skin_pipeline
      check_dir_for_change(watched_dirs)

      pipeline.execute( site ) if pipeline
      skin_pipeline.execute( site ) if skin_pipeline
    end

    def check_dir_for_change(watched_dirs)
      watched_dirs.each do |dir|
        Dir.chdir(dir){check_dir_for_change_recursively()}
      end
    end

    def check_dir_for_change_recursively()
      directories=[]
      Dir['*'].sort.each do |name|
        if File.file?(name)
          mtime = File.mtime(name)
          if ( mtime > ( @max_site_mtime || Time.at(0) ) )
            @max_site_mtime = mtime
          end
        elsif File.directory?(name)
          directories << name
        end
      end
      directories.each do |name|
        #don't descend into . or .. on linux
        Dir.chdir(name){check_dir_for_change_recursively()} if !Dir.pwd[File.expand_path(name)]
      end
    end

    def camelize(lower_case_and_underscored_word, first_letter_in_uppercase = true)
      if first_letter_in_uppercase
        lower_case_and_underscored_word.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
      else
        lower_case_and_underscored_word.first.downcase + camelize(lower_case_and_underscored_word)[1..-1]
      end
    end

  end

end
