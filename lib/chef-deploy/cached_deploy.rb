# stolen wholesale from capistrano, thanks Jamis!

class CachedDeploy
  # Executes the SCM command for this strategy and writes the REVISION
  # mark file to each host.
  def deploy
    @buffer = []
    @configuration[:release_path] = "#{@configuration[:deploy_to]}/releases/#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
    @configuration[:revision] ||= source.query_revision('HEAD') {|cmd| run cmd}
    Chef::Log.info "updating the cached checkout"
    run(update_repository_cache)
    Chef::Log.info "copying the cached version to #{configuration[:release_path]}"
    run(copy_repository_cache)
    callback(:before_migrate)
    migrate
    callback(:before_symlink)
    symlink
    callback(:before_restart)
    @buffer
  end
  
  # before_symlink
  # before_restart
  def callback(what)
    if File.exist?("#{latest_release}/deploy/#{what}.rb")
      Chef::Log.info "running deploy hook: #{latest_release}/deploy/#{what}.rb"
      Chef::Log.info run("cd #{latest_release} && ruby deploy/#{what}.rb #{@configuration[:environment]}")
    end
  end
  
  def latest_release
    File.join(release_path, all_releases.last)
  end
  
  def previous_release
    File.join(release_path, all_releases[-2])
  end
  
  def oldest_release
    File.join(release_path, all_releases.first)
  end
  
  def all_releases
    `ls #{release_path}`.split("\n").sort
  end
  
  def cleanup
    while all_releases.size >= 5
      FileUtils.rm_rf oldest_release
    end
  end
  
  def migrate
    if @configuration[:migrate]
      run "ln -nfs #{shared_path}/config/database.yml #{latest_release}/config/database.yml"
      Chef::Log.info "Migrating: cd #{latest_release} && RAILS_ENV=#{@configuration[:environment]} #{@configuration[:migration_command]}"
      Chef::Log.info run("cd #{latest_release} && RAILS_ENV=#{@configuration[:environment]} #{@configuration[:migration_command]}")
    end
  end
  
  def user
    @configuration[:user] || 'nobody'
  end
  
  def current_path
    "#{@configuration[:deploy_to]}/current"
  end

  def shared_path
    configuration[:shared_path]
  end
  
  def release_path
    "#{@configuration[:deploy_to]}/releases"
  end
  
  def symlink
    Chef::Log.info "symlinking and finishing deploy"
    symlink = false
    begin
      run [ "chmod -R g+w #{latest_release}",
            "rm -rf #{latest_release}/log #{latest_release}/public/system #{latest_release}/tmp/pids",
            "mkdir -p #{latest_release}/tmp",
            "ln -nfs #{shared_path}/log #{latest_release}/log",
            "mkdir -p #{latest_release}/public",
            "mkdir -p #{latest_release}/config",
            "ln -nfs #{shared_path}/system #{latest_release}/public/system",
            "ln -nfs #{shared_path}/pids #{latest_release}/tmp/pids",
            "ln -nfs #{shared_path}/config/database.yml #{latest_release}/config/database.yml",
            "chown -R #{user}:#{user} #{latest_release}"
          ].join(" && ")

      symlink = true
      run "rm -f #{current_path} && ln -nfs #{latest_release} #{current_path} && chown -R #{user}:#{user} #{current_path}"
    rescue => e
      run "rm -f #{current_path} && ln -nfs #{previous_release} #{current_path} && chown -R #{user}:#{user} #{current_path}" if symlink
      run "rm -rf #{latest_release}"
      raise e
    end
  end
  
  def run(cmd)
    res = `#{cmd}`
    @buffer << res
    res
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
    #@source ||= case configuration[:scm]
    #when 'git'
      Git.new configuration
    #when 'svn'
    #  Subversion.new configuration
    #end
  end

  private

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
        return "cp -RPp #{repository_cache} #{configuration[:release_path]} && #{mark}"
      else
        exclusions = copy_exclude.map { |e| "--exclude=\"#{e}\"" }.join(' ')
        return "rsync -lrpt #{exclusions} #{repository_cache}/* #{configuration[:release_path]} && #{mark}"
      end
    end
    
    def revision
      configuration[:revision]
    end
    
    def mark
      "(echo #{revision} > #{configuration[:release_path]}/REVISION)"
    end
    
    def copy_exclude
      @copy_exclude ||= Array(configuration.fetch(:copy_exclude, []))
    end
end