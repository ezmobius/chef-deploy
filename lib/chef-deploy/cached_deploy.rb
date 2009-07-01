# stolen wholesale from capistrano, thanks Jamis!
require 'yaml'
class ChefDeployFailure < StandardError
end

class CachedDeploy
  # Executes the SCM command for this strategy and writes the REVISION
  # mark file to each host.
  def deploy
    @configuration[:release_path] = "#{@configuration[:deploy_to]}/releases/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
    if @configuration[:revision] == ''
       @configuration[:revision] = source.query_revision(@configuration[:branch]) {|cmd| run_with_result "#{cmd}"}
    end
    
    if check_current_revision_and_noop_if_same(@configuration[:revision])
      Chef::Log.info "Revision is already deployed, running migrations if there are any"
      callback(:before_migrate)
      migrate
      callback(:before_symlink)
      symlink
      return
    end
    
    Chef::Log.info "ensuring proper ownership"
    chef_run("chown -R #{user}:#{group} #{@configuration[:deploy_to]}")    
    
    Chef::Log.info "deploying branch: #{@configuration[:branch]} rev: #{@configuration[:revision]}"
    Chef::Log.info "updating the cached checkout"
    chef_run(update_repository_cache)
    Chef::Log.info "copying the cached version to #{release_path}"
    chef_run(copy_repository_cache)
    install_gems
    
    chef_run("chown -R #{user}:#{group} #{@configuration[:deploy_to]}")    
    
    callback(:before_migrate)
    migrate
    callback(:before_symlink)
    symlink
    callback(:before_restart)
    restart
    callback(:after_restart)
    cleanup
  end
  
  def restart
    unless @configuration[:restart_command].empty?
      Chef::Log.info "restarting app: #{latest_release}"
      chef_run("cd #{current_path} && sudo -u #{user} RAILS_ENV=#{@configuration[:environment]} RACK_ENV=#{@configuration[:environment]} MERB_ENV=#{@configuration[:environment]} #{@configuration[:restart_command]}")
    end
  end
  
  def check_current_revision_and_noop_if_same(newrev)
    IO.read("#{latest_release}/REVISION").chomp == newrev
  rescue
    false
  end
  
  # before_symlink
  # before_restart
  def callback(what)
    if File.exist?("#{latest_release}/deploy/#{what}.rb")
      Dir.chdir(latest_release) do
        Chef::Log.info "running deploy hook: #{latest_release}/deploy/#{what}.rb"
        instance_eval(IO.read("#{latest_release}/deploy/#{what}.rb"))
      end
    end
  end
  
  def latest_release
    all_releases.last
  end
  
  def previous_release(current=latest_release)
    index = all_releases.index(current)
    all_releases[index-1]
  end
  
  def oldest_release
    all_releases.first
  end
  
  def all_releases
    `ls #{release_dir}`.split("\n").sort.map{|r| File.join(release_dir, r)}
  end
  
  def cleanup
    while all_releases.size >= 5
      FileUtils.rm_rf oldest_release
    end
  end
  
  def rollback
    Chef::Log.info "rolling back to previous release"
    symlink(previous_release)
    FileUtils.rm_rf latest_release
    Chef::Log.info "restarting with previous release"
    restart
  end
  
  def migrate
    if @configuration[:migrate]
      chef_run "ln -nfs #{shared_path}/config/database.yml #{latest_release}/config/database.yml"
      Chef::Log.info "Migrating: cd #{latest_release} && sudo -u #{user} RAILS_ENV=#{@configuration[:environment]} RACK_ENV=#{@configuration[:environment]} MERB_ENV=#{@configuration[:environment]} #{@configuration[:migration_command]}"
      chef_run("chown -R #{user}:#{group} #{latest_release}")
      chef_run("cd #{latest_release} && sudo -u #{user} RAILS_ENV=#{@configuration[:environment]} RACK_ENV=#{@configuration[:environment]} MERB_ENV=#{@configuration[:environment]} #{@configuration[:migration_command]}")
    end
  end
  
  def user
    @configuration[:user] || 'nobody'
  end
  
  def group
    @configuration[:group] || user
  end
  
  def current_path
    "#{@configuration[:deploy_to]}/current"
  end

  def shared_path
    configuration[:shared_path]
  end
  
  def release_dir
    "#{@configuration[:deploy_to]}/releases"
  end
  
  def release_path
    @configuration[:release_path]
  end
  
  def node
    @configuration[:node]
  end
  
  def symlink(release_to_link=latest_release)
    Chef::Log.info "symlinking and finishing deploy"
    symlink = false
    begin
      chef_run [ "chmod -R g+w #{release_to_link}",
            "rm -rf #{release_to_link}/log #{release_to_link}/public/system #{release_to_link}/tmp/pids",
            "mkdir -p #{release_to_link}/tmp",
            "ln -nfs #{shared_path}/log #{release_to_link}/log",
            "mkdir -p #{release_to_link}/public",
            "mkdir -p #{release_to_link}/config",
            "ln -nfs #{shared_path}/system #{release_to_link}/public/system",
            "ln -nfs #{shared_path}/pids #{release_to_link}/tmp/pids",
            "ln -nfs #{shared_path}/config/database.yml #{release_to_link}/config/database.yml",
            "chown -R #{user}:#{group} #{release_to_link}"
          ].join(" && ")

      symlink = true
      chef_run "rm -f #{current_path} && ln -nfs #{release_to_link} #{current_path} && chown -R #{user}:#{group} #{current_path}"
    rescue => e
      chef_run "rm -f #{current_path} && ln -nfs #{previous_release(release_to_link)} #{current_path} && chown -R #{user}:#{group} #{current_path}" if symlink
      chef_run "rm -rf #{release_to_link}"
      raise e
    end
  end
  
  def run_with_result(cmd)
    res = `#{cmd} 2>&1`
    raise(ChefDeployFailure, res) unless $? == 0
    res
  end
  
  def chef_run(cmd)
    Chef::Mixin::Command.run_command(:command => cmd)
  end
  
  def run(cmd)
    Chef::Mixin::Command.run_command(:command => cmd, :user => user)
  end
  
  def sudo(cmd)
    Chef::Mixin::Command.run_command(:command => cmd)
  end
  
  # :repository_cache
  # :shared_path
  # :repository
  # :release_path
  # :copy_exclude
  # :revision
  # :user
  # :group
  def initialize(opts={})
    @configuration = opts
    @configuration[:shared_path] = "#{@configuration[:deploy_to]}/shared"
  end
  
  def configuration
    @configuration
  end
  
  def source
    @source ||= case configuration[:scm]
    when 'git'
      Git.new configuration
    when 'svn'
      Subversion.new configuration
    end
  end

  private

    def install_gems
      if File.exist?("#{latest_release}/gems.yml")
        gems = YAML.load(IO.read("#{latest_release}/gems.yml"))
        resources = []
        gems.each do |g|
          next if has_gem?(g[:name], g[:version])
          r = Chef::Resource::GemPackage.new(g[:name], nil, @configuration[:node])
          r.version g[:version]
          r.source "http://gems.github.com"
          resources << r
        end
        resources.each do |r|
          begin
            r.run_action(:install)
          rescue Chef::Exception::Exec => e
            Chef::Log.info("Error installing gem: #{r.package_name} version: #{r.version}")
            raise e
          end
        end
      end
    end
    
    def has_gem?(name, version=nil)
      if !$GEM_LIST_DEPLOY
        gems = {}
        `gem list --local`.each_line do |line|
          gems[$1.to_sym] = $2.split(/, /) if line =~ /^(.*) \(([^\)]*)\)$/
        end
        $GEM_LIST_DEPLOY = gems
      end
      if $GEM_LIST_DEPLOY[name.to_sym]
        if version
          if $GEM_LIST_DEPLOY[name.to_sym].include?(version) 
            Chef::Log.info("Gem: #{name}:#{version} already installed, skipping")
            return true
          end  
        else
          Chef::Log.info("Gem: #{name} already installed, skipping")
          return true
        end
      end
      false
    end

    def repository_cache
      File.join(configuration[:shared_path], configuration[:repository_cache] || "cached-copy")
    end

    def update_repository_cache
      command = "if [ -d #{repository_cache} ]; then " +
        "#{source.sync(revision, repository_cache)}; " +
        "else #{source.checkout(revision, repository_cache)}; fi"
      command
    end

    def copy_repository_cache
      if copy_exclude.empty? 
        return "cp -RPp #{repository_cache} #{release_path} && #{mark}"
      else
        exclusions = copy_exclude.map { |e| "--exclude=\"#{e}\"" }.join(' ')
        return "rsync -lrpt #{exclusions} #{repository_cache}/* #{release_path} && #{mark}"
      end
    end
    
    def revision
      configuration[:revision]
    end
    
    def mark
      "(echo #{revision} > #{release_path}/REVISION)"
    end
    
    def copy_exclude
      @copy_exclude ||= Array(configuration.fetch(:copy_exclude, []))
    end
end
