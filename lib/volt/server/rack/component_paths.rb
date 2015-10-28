# ComponentPaths gives an array of every folder where you find a component.
require 'volt/server/rack/component_code'

module Volt
  class ComponentPaths
    def initialize(root = nil)
      @root = root || Dir.pwd
    end

    # Yield for every folder where we might find components
    def app_folders
      # Find all app folders
      @app_folders ||= begin
        volt_app    = File.expand_path(File.join(File.dirname(__FILE__), '../../../../app'))

        # Gem folders with volt in them
        # TODO: we should probably qualify this a bit more
        app_folders = [volt_app]
        app_folders += Gem.loaded_specs.values.
          select {|gem| gem.name =~ /^volt/ }.
          sort { |a, b| dependent_sort(a, b) }.
          map {|gem| "#{gem.full_gem_path}/app" }

        app_folders += ["#{@root}/app", "#{@root}/vendor/app"].map { |f| File.expand_path(f) }

        app_folders.uniq
      end

      # Yield each app folder and return a flattened array with
      # the results

      files        = []
      @app_folders.each do |app_folder|
        files << yield(app_folder)
      end

      files.flatten
    end

    # returns an array of every folder that is a component
    def components
      return @components if @components

      @components = {}
      app_folders do |app_folder|
        Dir["#{app_folder}/*"].sort.each do |folder|
          if File.directory?(folder)
            folder_name = folder[/[^\/]+$/]

            # Add in the folder if it's not alreay in there
            folders = (@components[folder_name] ||= [])
            folders << folder unless folders.include?(folder)
          end
        end
      end

      @components
    end

    # Setup load path for components
    def setup_load_paths
      unless RUBY_PLATFORM == 'opal'
        app_folders do |app_folder|
          $LOAD_PATH.unshift(app_folder)
        end
      end
    end

    # Makes each components classes available on the load path, require classes.
    def require_in_components(volt_app)
      if RUBY_PLATFORM == 'opal'
      else
        app_folders do |app_folder|
          # Sort so we get consistent load order across platforms
          Dir["#{app_folder}/*/{controllers,models,tasks}/*.rb"].each do |ruby_file|
            path = ruby_file.gsub(/^#{app_folder}\//, '')[0..-4]
            require(path)
          end
        end

        # Delay the loading of views
        volt_app.templates.template_loader = -> { load_views_and_routes(volt_app) }
      end
    end

    def load_views_and_routes(volt_app)
      component_names = []
      app_folders do |app_folder|
        Dir["#{app_folder}/*"].map { |cp| cp[/[^\/]+$/] }.each do |component_name|
          component_names << component_name
        end
      end

      # Load in all views and routes
      # TODO: Nested components listed twice are are loaded multiple times
      component_names.uniq.each do |component_name|
        code = Volt::ComponentCode.new(volt_app, component_name, self, false).code
        # Evaluate returned code, the ```volt_app``` variable is set for access.
        eval(code)
      end
    end

    # Returns all paths for a specific component
    def component_paths(name)
      folders = components[name]

      if folders
        return folders
      else
        return nil
      end
    end

    # Return every asset folder we need to serve from
    def asset_folders
      folders = []
      app_folders do |app_folder|
        Dir["#{app_folder}/*/assets"].sort.each do |asset_folder|
          folders << yield(asset_folder)
        end
      end

      folders.flatten
    end

    private

    # Determine if Gem::Specification b dependes on a
    def dependent?(a, b)
      name = a.name
      b.dependencies.any? {|dep| dep.type == :runtime && dep.name == a.name }
    end

    def dependent_sort(a, b)
      if dependent?(a, b)
        -1
      elsif dependent?(b, a)
        1
      else
        0
      end
    end

  end
end
