require File.expand_path('node_info.rb', File.dirname(__FILE__))

module ClusterChef

  #
  #
  module Discovery


    def announces(sys_name, aspects={})
      sys = System.new(sys_name, aspects)
      node[:discovery][system] = sys.to_hash
    end

    System = Struct.new(
      :name,
      :realm,
      :concerns,
      :version,
      #
      :stores,
      :daemons,
      :ports,
      :crons,
      :exports,
      #
      :dashboards,
      :description,
      :cookbook
      ) unless defined?(::ClusterChef::Discovery::System)
    System.class_eval do
      # include Chef::Mixin::CheckHelper
      # include Chef::Mixin::ParamsValidate
      # FORBIDDEN_IVARS = []
      # HIDDEN_IVARS    = []

      def initialize
      end

    end

    # --------------------------------------------------------------------------
    #
    # Alternate syntax
    #

    # alias for #discovers
    #
    # @example
    #   can_haz(:redis) # => {
    #     :in_yr       => 'uploader_queue',             # alias for realm
    #     :mah_bukkit  => '/var/log/uploader',          # alias for logs
    #     :mah_sunbeam => '/usr/local/share/uploader',  # home dir
    #     :ceiling_cat => 'http://10.80.222.69:2345/',  # dashboards
    #     :o_rly       => ['mountable_volumes'],        # concerns
    #     :zomg        => ['redis_server'],             # daemons
    #     :btw         => %Q{Queue to process uploads}  # description
    #   }
    #
    #
    def can_haz(name, options={})
      system = discover(name, options)
      MAH_ASPECTZ_THEYR.each do |lol, real|
        system[lol] = system.delete(real) if aspects.has_key?(real)
      end
      system
    end

    # alias for #announces. As with #announces, all params besides name are
    # optional -- follow the conventions whereever possible. MAH_ASPECTZ_THEYR
    # has the full list of alternate aspect names.
    #
    # @example
    #   # announce a redis; everything according to convention except for the
    #   # custom log directory.
    #   i_haz_a(:redis, :mah_bukkit => '/var/log/uploader' )
    #
    def i_haz_a(system, aspects)
      MAH_ASPECTZ_THEYR.each do |lol, real|
        aspects[real] = aspects.delete(lol) if aspects.has_key?(lol)
      end
      announces(system, aspects)
    end

    # Alternate names for machine aspects. Only available through #i_haz_a and
    # #can_haz.
    #
    MAH_ASPECTZ_THEYR = {
      :in_yr => :realm, :mah_bukkit => :logs, :mah_sunbeam => :home,
      :ceiling_cat => :dashboards, :o_rly => :concerns, :zomg => :daemons,
      :btw => :description,
    }
  end

  module StructAttr

    #
    # Returns a hash with each key set to its associated value.
    #
    # @example
    #    FooClass = Struct(:a, :b)
    #    foo = FooClass.new(100, 200)
    #    foo.to_hash # => { :a => 100, :b => 200 }
    #
    # @return [Hash] a new Hash instance, with each key set to its associated value.
    #
    def to_mash
      Mash.new.tap do |hsh|
        each_pair do |key, val|
          case
          when val.respond_to?(:to_mash) then hsh[key] = val.to_mash
          when val.respond_to?(:to_hash) then hsh[key] = val.to_hash
          else                                hsh[key] = val
          end
        end
      end
    end
    def to_hash() to_mash.to_hash ; end

    # barf.
    def store_into_node(node, a, b=nil)
      if b then
        node[a] ||= Mash.new
        node[a][b] = self.to_mash
      else
        node[a]    = self.to_mash
      end
    end

    module ClassMethods

      def discover()
      end

      def populate
      end

      def from_node(node, scope)
      end

      def dsl_attr(name, validation)
        name = name.to_sym
        define_method(name) do |arg|
          set_or_return(name, arg, validation)
        end
      end
    end
    def self.included(base) base.extend(ClassMethods) ; end
  end

  #
  # An *aspect* is an external property, commonly encountered across multiple
  # systems, that decoupled agents may wish to act on.
  #
  # For example, many systems have a Dashboard aspect -- phpMySQL, the hadoop
  # jobtracker web console, a one-pager generated by cluster_chef's
  # mini_dashboard recipe, or a purpose-built backend for your website. The
  # following independent concerns can act on such dashboard aspects:
  # * a dashboard dashboard creates a page linking to all of them
  # * your firewall grants access from internal machines and denies access on
  #   public interfaces
  # * the monitoring system checks that the port is open and listening
  #
  # Aspects are able to do the following:
  #
  # * Convert to and from a plain hash,
  #
  # * ...and thusly to and from plain node metadata attributes
  #
  # * discover its manifestations across all systems (on all or some
  #   machines): for example, all dashboards, or all open ports.
  #
  # * identify instances from a system's by-convention metadata. For
  #   example, given a chef server system at 10.29.63.45 with attributes
  #     `:chef_server => { :server_port => 4000, :dash_port => 4040 }`
  #   the PortAspect class would produce instances for 4000 and 4040, since by
  #   convention an attribute ending in `_port` means "I have a port aspect`;
  #   the DashboardAspect would recognize the `dash_port` attribute and
  #   produce an instance for `http://10.29.63.45:4040`.
  #
  # Note:
  #
  # * separate *identifiable conventions* from *concrete representation* of
  #   aspects. A system announces that it has a log aspect, and by convention
  #   declares a `:log_dir` attribute. At that point it is regularized into a
  #   LogAspect instance and stored in the `node[:aspects]` tree. External
  #   concerns should only inspect these concrete Aspects, and never go
  #   hunting for thins with a `:log_dir` attribute.
  #
  # * conventions can be messy, but aspects are perfectly uniform
  #
  module Aspect
    include StructAttr

    # Harvest all aspects findable in the given node metadata hash
    #
    # @example
    #   ClusterChef::Aspect.harvest({ :log_dirs => '...', :dash_port => 9387 })
    #   # [ <LogAspect name="log" dirs=["..."]>,
    #   #   <DashboardAspect url="http://10.x.x.x:9387/">,
    #   #   <PortAspect port=9387 addr="10.x.x.x"> ]
    #
    def self.harvest_all(sys_name, info, run_context)
      info = info.to_hash
      aspects = Mash.new
      registered.each do |aspect_name, aspect_klass|
        res = aspect_klass.harvest(sys_name, info, run_context)
        aspects[aspect_name] = res
      end
      aspects
    end

    # list of known aspects
    def self.registered
      @registered ||= Mash.new
    end

    # simple handle for class
    # @example
    #   foo = ClusterChef::FooAspect
    #   foo.klass_handle # :foo
    def klass_handle() self.class.klass_handle ; end

    # checks that the aspect is well-formed. returns non-empty array if there is lint.
    #
    # @abstract
    #   override to provide guidance, filling an array with warning strings. Include
    #       errors + super
    #   as the last line.
    #
    def lint
      []
    end

    def lint!
      lint.each{|l| Chef::Log.warn(l) }
    end

    def lint_flavor
      self.class.allowed_flavors.include?(self.flavor) ? [] : ["Unexpected #{klass_handle} flavor #{flavor.inspect}"]
    end

    module ClassMethods
      include StructAttr::ClassMethods
      include ClusterChef::NodeInfo

      # Identify aspects from the given hash
      #
      # @return [Array<Aspect>] aspect instances found in hash
      #
      # @example
      #   LogAspect.harvest({
      #     :access_log_file => ['/var/log/nginx/foo-access.log'],
      #     :error_log_file  => ['/var/log/nginx/foo-error.log' ], })
      #   # [ <LogAspect @name="access_log" @files=['/var/log/nginx/foo-access.log'] >,
      #   #   <LogAspect @name="error_log"  @files=['/var/log/nginx/foo-error.log']  > ]
      #
      def harvest(sys_name, info, run_context)
        []
      end

      #
      # Extract attributes matching the given pattern.
      #
      # @param [Hash]   info   -- hash of key-val pairs
      # @param [Regexp] regex  -- filter for keys matching this pattern
      #
      # @yield on each match
      # @yieldparam [String, Symbol] key   -- the matching key
      # @yieldparam [Object]         val   -- its value in the info hash
      # @yieldparam [MatchData]      match -- result of the regexp match
      # @yieldreturn [Aspect]        block should return an aspect
      #
      # @return [Array<Aspect>] collection of the block's results
      def attr_matches(info, regexp)
        results = []
        info.each do |key, val|
          next unless (match = regexp.match(key.to_s))
          result = yield(key, val, match)
          result.lint!
          results << result
        end
        results
      end

      # add this class to the list of registered aspects
      def register!
        Aspect.registered[klass_handle] = self
      end

      # strip off module part and '...Aspect' from class name
      # @example ClusterChef::FooAspect.klass_handle # :foo
      def klass_handle
        @klass_handle ||= self.name.to_s.gsub(/.*::(\w+)Aspect\z/,'\1').gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase.to_sym
      end

      def match_resource(rsrc_clxn, resource_name, cookbook_name)
        results = []
        rsrc_clxn.each do |rsrc|
          next unless rsrc.resource_name == resource_name.to_s
          next unless rsrc.cookbook_name == cookbook_name.to_s
          result = yield(rsrc)
          results << result
        end
        results
      end
    end
    def self.included(base) ; base.extend(ClassMethods) ; end
  end

  #
  # * scope[:run_state]
  #
  # from the eponymous service resource,
  # * service.path
  # * service.pattern
  # * service.user
  # * service.group
  #
  class DaemonAspect < Struct.new(:name,
      :pattern,    # pattern to detect process
      :run_state ) # desired run state

    include Aspect; register!
    def self.harvest(sys_name, info, run_context)
      match_resource(run_context.resource_collection, :service, sys_name) do |rsrc|
        svc = self.new(rsrc.name, rsrc.pattern)
        svc.run_state = info[:run_state].to_s if info[:run_state]
        p svc
        svc
      end
    end
  end

  class PortAspect < Struct.new(:name,
      :port_num,
      :addrs)
    include Aspect; register!
    ALLOWED_FLAVORS = [:http, :https, :pop3, :imap, :ftp, :jmx, :ssh, :nntp, :udp, :selfsame]
    def self.allowed_flavors() ALLOWED_FLAVORS ; end
  end

  class DashboardAspect < Struct.new(:name, :flavor,
      :url)
    include Aspect; register!
    ALLOWED_FLAVORS = [ :http, :jmx ]
    def self.allowed_flavors() ALLOWED_FLAVORS ; end

    def self.harvest(sys_name, info, run_context)
      attr_matches(info, /(.*dash)_port/) do |key, val, match|
        name   = match[1]
        flavor = (name == 'dash') ? :http_dash : name.to_sym
        url    = "http://#{private_ip_of(run_context.node)}:#{val}/"
        self.new(name, flavor, url)
      end
    end
  end

  #
  # * scope[:log_dirs]
  # * scope[:log_dir]
  # * flavor: http, etc
  #
  class LogAspect < Struct.new(:name,
      :flavor,
      :dirs )
    include Aspect; register!
    ALLOWED_FLAVORS = [ :http, :log4j, :rails ]

    def self.harvest(sys_name, info, run_context)
      attr_matches(info, /log_dir/) do |key, val, match|
        name = 'log'
        self.new(name, name.to_sym, val)
      end
    end
  end

  #
  # * attributes with a _dir or _dirs suffix
  #
  class DirectoryAspect < Struct.new(:name,
      :flavor,  # log, conf, home, ...
      :dirs    # directories pointed to
      )
    include Aspect; register!
    ALLOWED_FLAVORS = [ :home, :conf, :log, :tmp, :pid, :data, :lib, :journal, :cache, ]
    def self.allowed_flavors() ALLOWED_FLAVORS ; end

    def self.harvest(sys_name, info, run_context)
      attr_matches(info, /(.*)_dir/) do |key, val, match|
        name = match[1]
        self.new(name, name.to_sym, val)
      end
    end
  end

  #
  # Code assets (jars, compiled libs, etc) that another system may wish to
  # incorporate
  #
  class ExportedAspect < Struct.new(:name,
      :flavor,
      :files)
    include Aspect; register!

    ALLOWED_FLAVORS = [:jars, :libs, :confs]
    def self.allowed_flavors() ALLOWED_FLAVORS ; end

    def flavor=(val)
      val = val.to_sym unless val.nil?
      super(val)
    end

    def lint
      errors  = []
      errors += lint_flavor
      errors + super()
    end

    def self.harvest(sys_name, info, run_context)
      attr_matches(info, /exported_(.*)/) do |key, val, match|
        name = match[1]
        self.new(name, name.to_sym, val)
      end
    end
  end

  class VolumeAspect < Struct.new(:name,
      :device, :mount_path, :fstype
      )
    include Aspect; register!
    ALLOWED_FLAVORS = [:persistent, :local, :fast, :bulk, :reserved, ]
    def self.allowed_flavors() ALLOWED_FLAVORS ; end
  end

  #
  # manana
  #

  # # usage constraints -- ulimits, java heap size, thread count, etc
  # class UsageLimitAspect
  # end
  # # deploy
  # # package
  # # account (user / group)
  # class CookbookAspect < Struct.new( :name,
  #     :deploys, :packages, :users, :groups, :depends, :recommends, :supports,
  #     :attributes, :recipes, :resources, :authors, :license, :version )
  # end
  #
  # class CronAspect
  # end
  #
  # class AuthkeyAspect
  # end
end
