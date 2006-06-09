# $Id$
#--
# Copyright 2004 Luke Kanies <luke@madstop.com>
#
# This program is free software. It may be redistributed and/or modified under
# the terms of the Apache license.
# 
#--

class Facter
    include Comparable
    include Enumerable

    FACTERVERSION = '1.3'
	# = Facter
    # Functions as a hash of 'facts' you might care about about your
    # system, such as mac address, IP address, Video card, etc.
    # returns them dynamically

	# == Synopsis
	#
    # Generally, treat <tt>Facter</tt> as a hash:
    # == Example
    # require 'facter'
    # puts Facter['operatingsystem']
    #


    @@facts = {}
    GREEN = "[0;32m"
    RESET = "[0m"
    @@debug = 0

    attr_accessor :name, :searching, :ldapname

	# module methods

    # Return the version of the library.
    def Facter.version
        return FACTERVERSION
    end

    # Add some debugging
    def Facter.debug(string)
        if string.nil?
            return
        end
        if @@debug != 0
            puts GREEN + string + RESET
        end
    end

    # Return a fact object by name.  If you use this, you still have to call
    # 'value' on it to retrieve the actual value.
    def Facter.[](name)
        name = name.to_s.downcase
        @@facts[name]
    end

    # Add a resolution mechanism for a named fact.  This does not distinguish
    # between adding a new fact and adding a new way to resolve a fact.
    def Facter.add(name, &block)
        fact = nil
        dcname = name.to_s.downcase

        if @@facts.include?(dcname)
            fact = @@facts[dcname]
        else
            Facter.new(dcname)
            fact = @@facts[dcname]
        end

        unless block
            return fact
        end

        fact.add(&block)

        return fact
    end

    class << self
        include Enumerable
        # Iterate across all of the facts.
        def each
            @@facts.each { |name,fact|
                if fact.suitable?
                    value = fact.value
                    unless value.nil?
                        yield name, fact.value
                    end
                end
            }
        end

        # Allow users to call fact names directly on the Facter class,
        # either retrieving the value or comparing it to an existing value.
        def method_missing(name, *args)
            question = false
            if name.to_s =~ /\?$/
                question = true
                name = name.to_s.sub(/\?$/,'')
            end

            if fact = self[name]
                if question
                    value = fact.value.downcase
                    args.each do |arg|
                        if arg.to_s.downcase == value
                            return true
                        end
                    end

                    # If we got this far, there was no match.
                    return false
                else
                    return fact.value
                end
            else
                # Else, fail like a normal missing method.
                return super
            end
        end
    end

    # Clear all facts.  Mostly used for testing.
    def Facter.clear
        Facter.reset
        Facter.flush
        @@facts.clear
    end

	# Set debugging on or off.
	def Facter.debugging(bit)
		if bit
            case bit
            when TrueClass: @@debug = 1
            when FalseClass: @@debug = 0
            when Fixnum: 
                if bit > 0
                    @@debug = 1
                else
                    @@debug = 0
                end
            when String:
                if bit.downcase == 'off'
                    @@debug = 0
                else
                    @@debug = 1
                end
            else
                @@debug = 0
            end
		else
			@@debug = 0
		end
	end

    # Flush all cached values.
    def Facter.flush
        @@facts.each { |fact| fact.flush }
    end

    # Return a list of all of the facts.
    def Facter.list
        return @@facts.keys
    end

    # Remove them all.
    def Facter.reset
        @@facts.each { |name,fact|
            @@facts.delete(name)
        }
    end

    # Return a hash of all of our facts.
    def Facter.to_hash(*tags)
        @@facts.inject({}) do |h, ary|
            if ary[1].suitable? and (tags.empty? or ary[1].tagged?(*tags))
                value = ary[1].value
                if value
                    h[ary[0]] = value
                end
            end
            h
        end
    end

    def Facter.value(name)
        if @@facts.include?(name.to_s.downcase)
            @@facts[name.to_s.downcase].value
        else
            nil
        end
    end

    # Compare one value to another.
    def <=>(other)
        return self.value <=> other
    end

    # Are we the same?  Used for case statements.
    def ===(value)
        self.value == value
    end

    # Create a new fact, with no resolution mechanisms.
    def initialize(name)
        @name = name.downcase if name.is_a? String
        if @@facts.include?(@name)
            raise ArgumentError, "A fact named %s already exists" % name
        else
            @@facts[@name] = self
        end

        @resolves = []
        @tags = []
        @searching = false

        @value = nil

        @ldapname = name
    end

    # Add a new resolution mechanism.  This requires a block, which will then
    # be evaluated in the context of the new mechanism.
    def add(&block)
        unless block_given?
            raise ArgumentError, "You must pass a block to Fact<instance>.add"
        end

        resolve = Resolution.new(@name)

        resolve.fact = self

        resolve.instance_eval(&block)

        # skip resolves that will never be suitable for us
        unless resolve.suitable?
            return
        end

        # insert resolves in order of number of confinements
        inserted = false
        @resolves.each_with_index { |r,index|
            if resolve.length > r.length
                @resolves.insert(index,resolve)
                inserted = true
                break
            end
        }

        unless inserted
            @resolves.push resolve
        end
    end

    # Return a count of resolution mechanisms available.
    def count
        return @resolves.length
    end

    # Iterate across all of the fact resolution mechanisms and yield each in
    # turn.  These are inserted in order of most confinements.
    def each
        @resolves.each { |r| yield r }
    end

    # Flush any cached values.
    def flush
        @value = nil
        @suitable = nil
    end

    # Is this fact suitable for finding answers on this host?  This is used
    # to throw away any initially unsuitable mechanisms.
    def suitable?
        if @resolves.length == 0
            return false
        end

        unless defined? @suitable or (defined? @suitable and @suitable.nil?)
            @suitable = false
            @resolves.each { |resolve|
                if resolve.suitable?
                    @suitable = true
                    break
                end
            }
        end

        return @suitable
    end

    # Add one ore more tags
    def tag(*tags)
        tags.each do |t|
            t = t.to_s.downcase.intern
            @tags << t unless @tags.include?(t)
        end
    end

    # Is our fact tagged with all of the specified tags?
    def tagged?(*tags)
        tags.each do |t|
            unless @tags.include? t.to_s.downcase.intern
                return false
            end
        end

        return true
    end

    def tags
        @tags.dup
    end

    # Return the value for a given fact.  Searches through all of the mechanisms
    # and returns either the first value or nil.
    def value
        unless @value
            # make sure we don't get stuck in recursive dependency loops
            if @searching
                Facter.debug "Caught recursion on %s" % @name
                
                # return a cached value if we've got it
                if @value
                    return @value
                else
                    return nil
                end
            end
            @value = nil
            foundsuits = false

            if @resolves.length == 0
                Facter.debug "No resolves for %s" % @name
                return nil
            end

            @searching = true
            @resolves.each { |resolve|
                #Facter.debug "Searching resolves for %s" % @name
                if resolve.suitable?
                    @value = resolve.value
                    foundsuits = true
                end
                unless @value.nil? or @value == ""
                    break
                end
            }
            @searching = false

            unless foundsuits
                Facter.debug "Found no suitable resolves of %s for %s" %
                    [@resolves.length,@name]
            end
        end

        if @value.nil?
            # nothing
            Facter.debug("value for %s is still nil" % @name)
            return nil
        else
            return @value
        end
    end

    # An actual fact resolution mechanism.  These are largely just chunks of
    # code, with optional confinements restricting the mechanisms to only working on
    # specific systems.  Note that the confinements are always ANDed, so any
    # confinements specified must all be true for the resolution to be
    # suitable.
    class Resolution
        attr_accessor :interpreter, :code, :name, :fact

        # Execute a chunk of code.
        def Resolution.exec(code, interpreter = "/bin/sh")
            if interpreter == "/bin/sh"
                binary = code.split(/\s+/).shift

                path = nil
                if binary !~ /^\//
                    path = %x{which #{binary} 2>/dev/null}.chomp
                    if path == ""
                        # we don't have the binary necessary
                        return nil
                    end
                else
                    path = binary
                end

                unless FileTest.exists?(path)
                    # our binary does not exist
                    return nil
                end
                out = nil
                begin
                    out = %x{#{code}}.chomp
                rescue => detail
                    $stderr.puts detail
                    return nil
                end
                if out == ""
                    return nil
                else
                    return out
                end
            else
                raise ArgumentError,
                    "non-sh interpreters are not currently supported"
            end
        end

        # Add a new confine to the resolution mechanism.
        def confine(*args)
            if args[0].is_a? Hash
                args[0].each do |fact, values|
                    @confines.push Confine.new(fact,*values)
                end
            else
                fact = args.shift
                @confines.push Confine.new(fact,*args)
            end
        end

        # Create a new resolution mechanism.
        def initialize(name)
            @name = name
            @confines = []
            @value = nil
        end

        # Return the number of confines.
        def length
            @confines.length
        end

        # Set our code for returning a value.
        def setcode(string = nil, interp = nil, &block)
            if string
                @code = string
                @interpreter = interp || "/bin/sh"
            else
                unless block_given?
                    raise ArgumentError, "You must pass either code or a block"
                end
                @code = block
            end
        end

        # Set the name by which this parameter is known in LDAP.  The default
        # is just the fact name.
        def setldapname(name)
            @fact.ldapname = name
        end

        # Is this resolution mechanism suitable on the system in question?
        def suitable?
            unless defined? @suitable
                @suitable = true
                if @confines.length == 0
                    return true
                end
                @confines.each { |confine|
                    unless confine.true?
                        @suitable = false
                    end
                }
            end

            return @suitable
        end

        # Set tags on our parent fact.
        def tag(*values)
            @fact.tag(*values)
        end

        def to_s
            return self.value()
        end

        # How we get a value for our resolution mechanism.
        def value
            value = nil

            if @code.is_a?(Proc)
                value = @code.call()
            else
                unless defined? @interpreter
                    @interpreter = "/bin/sh"
                end
                if @code.nil?
                    $stderr.puts "Code for %s is nil" % @name
                else
                    value = Resolution.exec(@code,@interpreter)
                end
            end

            if value == ""
                value = nil
            end

            return value
        end

    end

    # A restricting tag for fact resolution mechanisms.  The tag must be true
    # for the resolution mechanism to be suitable.
    class Confine
        attr_accessor :fact, :op, :value

        # Add the tag.  Requires the fact name, an operator, and the value
        # we're comparing to.
        def initialize(fact, *values)
            fact = fact.to_s if fact.is_a? Symbol
            @fact = fact
            @values = values.collect do |value|
                if value.is_a? String
                    value
                else
                    value.to_s
                end
            end
        end

        def to_s
            return "'%s' '%s'" % [@fact, @values.join(",")]
        end

        # Evaluate the fact, returning true or false.
        def true?
            fact = nil
            unless fact = Facter[@fact]
                Facter.debug "No fact for %s" % @fact
                return false
            end
            value = fact.value

            if value.nil?
                return false
            end

            retval = @values.find { |v|
                if value.downcase == v.downcase
                    break true
                end
            }

            if retval
                retval = true
            else
                retval = false
            end

            return retval || false
        end
    end

    # Load all of the default facts
    def Facter.loadfacts
        Facter.add("FacterVersion") do
            setcode { FACTERVERSION.to_s }
        end

        Facter.add("RubyVersion") do
            setcode { RUBY_VERSION.to_s }
        end

        Facter.add("PuppetVersion") do
            setcode {
                begin
                    require 'puppet'
                    Puppet::PUPPETVERSION.to_s
                rescue LoadError
                    nil
                end
            }
        end

        Facter.add :rubysitedir do
            setcode do
                version = RUBY_VERSION.to_s.sub(/\.\d+$/, '')
                $:.find do |dir|
                    dir =~ /#{File.join("site_ruby", version)}$/
                end
            end
        end

        Facter.add("Kernel") do
            setcode 'uname -s'
        end

        Facter.add("KernelRelease") do
            setcode 'uname -r'
        end

        Facter.add("OperatingSystem") do
            # Default to just returning the kernel as the operating system
            setcode do Facter["Kernel"].value end
        end

        Facter.add("OperatingSystemRelease") do
            setcode do Facter["KernelRelease"].value end
        end

        Facter.add("OperatingSystem") do
            #obj.os = "Linux"
            confine :kernel => :sunos
            setcode do "Solaris" end
        end

        Facter.add("OperatingSystem") do
            #obj.os = "Linux"
            confine :kernel => :linux
            setcode do
                if FileTest.exists?("/etc/debian_version")
                    "Debian"
                elsif FileTest.exists?("/etc/gentoo-release")
                    "Gentoo"
                elsif FileTest.exists?("/etc/fedora-release")
                    "Fedora"
                elsif FileTest.exists?("/etc/redhat-release")
                    txt = File.read("/etc/redhat-release")
                    if txt =~ /centos/i
                        "CentOS"
                    else
                        "RedHat"
                    end
                elsif FileTest.exists?("/etc/SuSE-release")
                    "SuSE"
                end
            end
        end

        Facter.add("HardwareModel") do
            setcode 'uname -m'
        end

        Facter.add("Architecture") do
            confine :operatingsystem => :debian
            setcode do
                model = Facter.hardwaremodel
                case model
                when 'x86_64': "amd64" 
                when /(i[3456]86|pentium)/: "i386"
                else
                    model
                end
            end
        end

        Facter.add("CfKey") do
            setcode do
                value = nil
                ["/usr/local/etc/cfkey.pub",
                    "/etc/cfkey.pub",
                    "/var/cfng/keys/localhost.pub",
                    "/var/cfengine/ppkeys/localhost.pub"
                ].each { |file|
                    if FileTest.file?(file)
                        File.open(file) { |openfile|
                            value = openfile.readlines.reject { |line|
                                line =~ /PUBLIC KEY/
                            }.collect { |line|
                                line.chomp
                            }.join("")
                        }
                    end
                    if value
                        break
                    end
                }

                value
            end
        end

        Facter.add("Domain") do
            setcode do
                if defined? $domain and ! $domain.nil?
                    $domain
                else
                    nil
                end
            end
        end
        Facter.add("Domain") do
            setcode do
                domain = Resolution.exec('domainname') or nil
                # make sure it's a real domain
                if domain and domain =~ /.+\..+/
                    domain
                else
                    nil
                end
            end
        end
        Facter.add("Domain") do
            setcode do
                value = nil
                if FileTest.exists?("/etc/resolv.conf")
                    File.open("/etc/resolv.conf") { |file|
                        # is the domain set?
                        file.each { |line|
                            if line =~ /domain\s+(\S+)/
                                value = $1
                                break
                            end
                        }
                    }
                    ! value and File.open("/etc/resolv.conf") { |file|
                        # is the search path set?
                        file.each { |line|
                            if line =~ /search\s+(\S+)/
                                value = $1
                                break
                            end
                        }
                    }
                    value
                else
                    nil
                end
            end
        end
        Facter.add("Hostname") do
            setldapname "cn"
            setcode do
                hostname = nil
                name = Resolution.exec('hostname') or nil
                if name
                    if name =~ /^([\w-]+)\.(.+)$/
                        hostname = $1
                        # the Domain class uses this
                        $domain = $2
                    else
                        hostname = name
                    end
                    hostname
                else
                    nil
                end
            end
        end

        Facter.add("IPAddress") do
            setldapname "iphostnumber"
            setcode do
                require 'resolv'

                begin
                    if hostname = Facter["hostname"].value
                        ip = Resolv.getaddress(hostname)
                        unless ip == "127.0.0.1"
                            ip
                        end
                    else
                        nil
                    end
                rescue Resolv::ResolvError
                    nil
                rescue NoMethodError # i think this is a bug in resolv.rb?
                    nil
                end
            end
        end
        Facter.add("IPAddress") do
            setcode do
                if hostname = Facter["hostname"].value
                    # we need Hostname to exist for this to work
                    if list = Resolution.exec("host #{hostname}").chomp.split(/\s/)

                        if defined? list[-1] and
                                list[-1] =~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/
                            list[-1]
                        end
                    else
                        nil
                    end
                else
                    nil
                end
            end
        end

        ["/etc/ssh","/usr/local/etc/ssh","/etc","/usr/local/etc"].each { |dir|
            {"SSHDSAKey" => "ssh_host_dsa_key.pub",
                    "SSHRSAKey" => "ssh_host_rsa_key.pub"}.each { |name,file|
                Facter.add(name) do
                    setcode do
                        value = nil
                        filepath = File.join(dir,file)
                        if FileTest.file?(filepath)
                            begin
                                value = File.open(filepath).read.chomp
                            rescue
                                value = nil
                            end
                        end
                        value
                    end # end of proc
                end # end of add
            } # end of hash each
        } # end of dir each

        Facter.add("UniqueId") do
            setcode 'hostid',  '/bin/sh'
            confine :operatingsystem => :solaris
        end

        Facter.add("HardwareISA") do
            setcode 'uname -p', '/bin/sh'
            confine :operatingsystem => :solaris
        end

        Facter.add("MacAddress") do
            confine :operatingsystem => :solaris
            setcode do
                ether = nil
                output = %x{/sbin/ifconfig -a}

                output =~ /ether (\w{1,2}:\w{1,2}:\w{1,2}:\w{1,2}:\w{1,2}:\w{1,2})/
                ether = $1

                ether
            end
        end

        Facter.add("MacAddress") do
            confine :kernel => :darwin
            setcode do
                ether = nil
                output = %x{/sbin/ifconfig}

                output.split(/^\S/).each { |str|
                    if str =~ /10baseT/ # we're wired
                        str =~ /ether (\w\w:\w\w:\w\w:\w\w:\w\w:\w\w)/
                        ether = $1
                    end
                }

                ether
            end
        end
        Facter.add("IPAddress") do
            confine :kernel => :darwin
            setcode do
                ip = nil
                output = %x{/sbin/ifconfig}

                output.split(/^\S/).each { |str|
                    if str =~ /inet ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/
                        tmp = $1
                        unless tmp =~ /127\./
                            ip = tmp
                            break
                        end
                    end
                }

                ip
            end
        end
        Facter.add("Hostname") do
            confine :kernel => :darwin, :kernelrelease => "R7"
            setcode do
                %x{/usr/sbin/scutil --get LocalHostName}
            end
        end
        Facter.add("IPHostnumber") do
            confine :kernel => :darwin, :kernelrelease => "R6"
            setcode do
                %x{/usr/sbin/scutil --get LocalHostName}
            end
        end
        Facter.add("IPHostnumber") do
            confine :kernel => :darwin, :kernelrelease => "R6"
            setcode do
                ether = nil
                output = %x{/sbin/ifconfig}

                output =~ /HWaddr (\w\w:\w\w:\w\w:\w\w:\w\w:\w\w)/
                ether = $1

                ether
            end
        end

        Facter.add("ps") do
            setcode do 'ps -ef' end
        end

        Facter.add("ps") do
            confine :operatingsystem => %w{FreeBSD NetBSD OpenBSD Darwin}
            setcode do 'ps -auxwww' end
        end

        Facter.add("id") do
            confine :operatingsystem => :linux
            setcode "whoami"
        end

        locals = []

        # Now see if we can find any other facts
        $:.each do |dir|
            fdir = File.join(dir, "facter")
            if FileTest.exists?(fdir) and FileTest.directory?(fdir)
                Dir.glob("#{fdir}/*.rb").each do |file|
                    # Load here, rather than require, because otherwise
                    # the facts won't get reloaded if someone calls
                    # "loadfacts".  Really only important in testing, but,
                    # well, it's important in testing.
                    load file
                end
            end
        end
    end

    Facter.loadfacts
end
