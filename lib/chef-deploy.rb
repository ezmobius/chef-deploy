require File.join(File.dirname(__FILE__), 'git')
require File.join(File.dirname(__FILE__), 'cached_git_deploy')

# git_deploy "/data/#{app}" do
#   repo "git://github.com/engineyard/rack-app.git"
#   branch "HEAD"
#   enable_submodules true
#   shallow_clone true
#   action :manage
# end

class Chef
  class Resource
    class Deploy < Chef::Resource
        
      def initialize(name, collection=nil, node=nil)
        super(name, collection, node)
        @resource_name = :deploy
        @deploy_to = name
        @branch = 'HEAD'
        @repository_cache = 'cached-copy'
        @copy_exclude = []
        @revision = nil
        @action = :manage
        @allowed_actions.push(:manage)
      end
      
      def repo(arg=nil)
        set_or_return(
          :repo,
          arg,
          :kind_of => [ String ]
        )
      end
      
      def enable_submodules(arg=false)
        set_or_return(
          :enable_submodules,
          arg,
          :kind_of => [ TrueClass, FalseClass ]
        )
      end
      
      def shallow_clone(arg=false)
        set_or_return(
          :shallow_clone,
          arg,
          :kind_of => [ TrueClass, FalseClass ]
        )
      end
      
      # :repository_cache
      # :shared_path
      # :repository
      # :release_path
      # :copy_exclude
      # :revision

      def repository_cache(arg=nil)
        set_or_return(
          :repository_cache,
          arg,
          :kind_of => [ String ]
        )
      end
      
      def copy_exclude(arg=nil)
        set_or_return(
          :copy_exclude,
          arg,
          :kind_of => [ String ]
        )
      end
      
      def revision(arg=nil)
        set_or_return(
          :revision,
          arg,
          :kind_of => [ String ]
        )
      end
            
      def branch(arg=nil)
        set_or_return(
          :branch,
          arg,
          :kind_of => [ String ]
        )
      end
 
    end
  end
  
  class Provider
    class Deploy < Chef::Provider 
      
      def load_current_resource
        
      end
      
      def action_manage
        Chef::Log.info "Running a new deploy\nto: #{@new_resource.name}\nrepo: #{@new_resource.repo}"
        dep = CachedGitDeploy.new :repository => @new_resource.repo,
                                  :deploy_to  => @new_resource.name,
                                  :repository_cache  => @new_resource.repository_cache,
                                  :copy_exclude  => @new_resource.copy_exclude,
                                  :revision  => @new_resource.revision,
                                  :git_enable_submodules => @new_resource.enable_submodules,
                                  :git_shallow_clone  => @new_resource.shallow_clone
        dep.deploy
      end
    end
  end
end

Chef::Platform.platforms[:default].merge! :deploy => Chef::Provider::Deploy
