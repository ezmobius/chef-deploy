require File.join(File.dirname(__FILE__), 'git')
require File.join(File.dirname(__FILE__), 'cached_git_deploy')

# deploy "/data/#{app}" do
#   repo "git://github.com/engineyard/rack-app.git"
#   branch "HEAD"
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
                                  :deploy_to  => @new_resource.name
        dep.deploy
      end
    end
  end
end

Chef::Platform.platforms[:default].merge! :deploy => Chef::Provider::Deploy
