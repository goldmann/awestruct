require 'git'

#  openshift:
#    baseurl: http://appname-prefix.rhcloud.com
#    deploy:
#      type: openshift
#      url: b98815a6hashhashhashhash@appname-prefix.rhcloud.com/~/git/appname.git
#      path: php
#      
module Awestruct
  module Commands
    class OpenShift
      def initialize( site_path, deploy_data )
        @site_path  = site_path
        @url        = deploy_data['url']
        @path       = deploy_data['path'] || 'php' # default for PHP cartridge
        @branch     = deploy_data['branch'] || 'master'
      end

      def run
        Dir.mktmpdir(nil, "/tmp") do |tmpdir|
          @git = Git.clone(@url, tmpdir)
          publish_site
        end
      end
      
      def publish_site
        copy
    
        if changed?
          commit
          push
        end
      end

      def copy
        @git.chdir do
          FileUtils.rm_rf( Dir.glob("#{@path}/*") )
          FileUtils.cp_r( Dir.glob("#{@site_path}/*"), @path )
        end
      end

      def changed?
        if @git.status.changed.empty?
          puts "No changes to commit, skipping."
          false
        else
          true
        end
      end

      def commit
        @git.chdir do
          @git.add(@path)

          @git.status.deleted.each do |f|
            @git.remove( f.first )
          end
          
          begin
            @git.commit("Published #{@branch} to OpenShift")
            true
          rescue Git::GitExecuteError => e
            $stderr.puts "Can't commit. #{e}."
            false
          end
        end
      end

      def push
        @git.reset_hard
        @git.push( 'origin', @branch )
      end
    end
  end
end

