require "yaml"

class AutomaticNamespaces::Autoloader
  PACKAGE_NON_NAMESPACED_DIRS_KEY = "excluded_automatic_namespace_directories".freeze
  DEFAULT_NON_NAMESPACED_DIRS = %w[/app/helpers /app/inputs /app/javascript /app/views].freeze

  def enable_automatic_namespaces
    namespaced_packages.each do |pack, metadata|
      package_namespace = define_namespace(pack, metadata)
      pack_directories(pack.path, metadata).each do |pack_dir|
        set_namespace_for(pack_dir, package_namespace)
      end
    end
  end

  private

  def set_namespace_for(pack_dir, package_namespace)
    Rails.logger.debug { "Associating #{pack_dir} with namespace #{package_namespace}" }
    ActiveSupport::Dependencies.autoload_paths.delete(pack_dir)
    Rails.autoloaders.main.push_dir(pack_dir, namespace: package_namespace)
    Rails.application.config.watchable_dirs[pack_dir] = [:rb]
  end

  def pack_directories(pack_root_dir, metadata)
    Dir.glob("#{pack_root_dir}/**/app/*").reject { |dir| non_namspaced_directory(dir, metadata) }
  end

  def non_namspaced_directory(dir, metadata)
    (DEFAULT_NON_NAMESPACED_DIRS + metadata.fetch(PACKAGE_NON_NAMESPACED_DIRS_KEY, [])).any? { dir.include?(_1) }
  end

  def define_namespace(pack, metadata)
    namespace_name = metadata["namespace_override"] || pack.last_name.camelize
    namespace_object = Object
    namespace_name.split("::").each do |module_name|
      namespace_object = find_or_create_module(namespace_object, module_name)
    end
    namespace_object
  end

  def find_or_create_module(namespace_object, module_name)
    if namespace_object.const_defined?(module_name)
      namespace_object.const_get(module_name)
    else
      namespace_object.const_set(module_name, Module.new)
    end
  end

  def namespaced_packages
    Packs.all
         .map { |pack| [pack, package_metadata(pack)] }
         .select { |_pack, metadata| metadata && metadata["automatic_pack_namespace"] }
  end

  def package_metadata(pack)
    package_file = pack.path.join("package.yml").to_s
    package_description = YAML.load_file(package_file) || {}
    package_description["metadata"]
  end
end
