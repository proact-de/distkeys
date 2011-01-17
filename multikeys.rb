#!/usr/bin/env ruby

require 'net/ssh'
require 'net/ssh/gateway'
require 'net/sftp'

require 'optparse'

class SSHAuthKeys
	# Authorized Keys
	attr_reader :authkeys

	# Takes an already initialized ssh object and
	# tries to get existing authorized keys
	def initialize(ssh, authkeyfile = ".ssh/authorized_keys")
		@ssh = ssh

		@authkeys = Array.new
		@authkeyfile = authkeyfile

		# Record when we done any change
		# So that we only upload keys when it is necessary
		@changed = false

		# Error output goes to stderr, stdout to @authkeys
		# @authkeys will be empty if file is not found, which is
		# just fine for us
		# Via the channel method we just get the standard
		# output

		# Start SFTP session
		puts "Opening SFTP session..."
		@sftp = Net::SFTP::Session.new(@ssh)
		@sftp.loop { @sftp.opening? }
		
		begin
			@authkeys_flat = @sftp.download!( authkeyfile )
		rescue RuntimeError => exception
			puts	exception.message
			puts "ERROR: Can't open authorized_keys"
			puts "Assuming that no keys are stored on the server"
		end

		@authkeys = @authkeys_flat.to_a
		@sftp.loop
	end

	# List keys via ssh-keygen -lf
	def list()
		@authkeys.each do | line |
			if line.index('ssh-')
				puts line.match(/ssh-[^ ]+\s+[A-Za-z0-9=+\/]+ (.*$)/)[1]
			end
		end
	end

	# Add a key file
	def addkeyfile( keyfile )
		if File.exists?( keyfile )
			key = File.new( keyfile, "r" ).to_a

			# Add keys in the file
			key.each do | line |
				# Is this a key?
				if line.index("ssh-")
					# Extract base64 from key
					matchdata = line.match(/ssh-[^ ]+\s+([A-Za-z0-9=+\/]+) (.*$)/)
					base64 = matchdata[1]
					comment = matchdata[2]
					# Key already there?
					if @authkeys.to_s.index(base64)
						puts "Key #{comment} already there. Skipped adding it."
					else
						# Add the key
						@authkeys += [ line ]
						@changed = true
						puts "Key #{comment} added."
					end # Key already there?
				end # Is this a key?
			end # Add keys in the file
		else
			puts "ERROR: Keyfile does not exist."
		end
	end
	
	def removekeyfile( keyfile )
		if File.exists?( keyfile )
			key = File.new( keyfile, "r" ).to_a
			
			# Remove keys in the file
			key.each do | line |
				# Is this a key?
				if line.index("ssh-")
					# Extract base64 from key
					matchdata = line.match(/ssh-[^ ]+\s+([A-Za-z0-9=+\/]+) (.*$)/)
					base64 = matchdata[1]
					comment = matchdata[2]
					# Key there?
					if index = @authkeys.to_s.index(base64)
						# Make sure to delete all instances of it
						@authkeys.each do | line |
							if line.index(base64)
								@authkeys.delete( line )
								@changed = true
								puts "Key #{comment} removed."
							end
						end
					else
						puts "Key #{comment} is not there. Skipped removing it."
					end # Key there?
				end # Is this a key?
			end # Add keys in the file
		else
			puts "ERROR: Keyfile does not exist."
		end
	end
	
	# Commits changes to authorized keys to the server
	# Creates a backup
	def commit()
		if @changed == false
			puts "Nothing has changed. Skipping uploading to server."
			return true
		end
		
		# Create a backup
		backupfile = "#{@authkeyfile}-#{ Time.now.strftime("%Y-%m-%d") }.bak"
		# With -n only if we didn't do one today already
		puts "Creating a backup to #{backupfile} if not already done today..."
		@ssh.exec!( "test -f #{backupfile} || cp -p #{@authkeyfile} #{backupfile}" )

		newauthkeyfile = "#{@authkeyfile}-new"
		puts "Uploading keys to #{newauthkeyfile}..."
		wantedsize = 0
		@sftp.file.open(newauthkeyfile , "w" ) do | file |
			@authkeys.each do | line |
				file.puts line
				wantedsize += line.length
			end
		end
		@sftp.loop

		request = @sftp.lstat(newauthkeyfile) do | response |
			if response.ok?
				# File size okay?
				if response[:attrs].size >= wantedsize
					puts "File does exist and has correct size, moving to #{@authkeyfile}..."
					# Move the new keyfile over the old one
					@ssh.exec!(  "mv  #{newauthkeyfile} #{@authkeyfile}" )

					# We saved the changes, so no unsaved changes anymore
					@changed = false
				end
			end
		end
		@sftp.loop
	end

end

class SSHGateway
	# Net::SSH::Gateway instance
	attr_reader :gateway
	
	# Takes a hash with host, port, user as returned from connection_info
	def initialize( hostdata )
		@host = hostdata[:host]
		@port = hostdata[:port]
		@user = hostdata[:user]
	end

	# Connect and return an Net::SSH::Gateway object
	def connect()
		puts "Connecting to gateway #{@host}..."
		@gateway = Net::SSH::Gateway.new(@host, @user, :port => @port, :compression => false )

		return @gateway
	end

	def disconnect()
		@gateway.shutdown!
		@gateway = nil
	end
end

class SSHHost
	# Net::SSH instance of the SSH server if connected
	attr_reader :ssh
	
	# Takes a hash with host, port, user as returned from connection_info
	def initialize( hostdata, gateway = nil )
		@host = hostdata[:host]
		@port = hostdata[:port]
		@user = hostdata[:user]
		
		@gateway = gateway
	end

	# Connect and return an Net::SSH object
	def connect( password = nil )
		if @gateway
			puts "Connecting to host #{@host} via gateway..."
			@ssh = @gateway.ssh(@host, @user, { :port => @port,  :compression => false, :password => password } )
		else
			puts "Connecting to host #{@host}..."
			@ssh = Net::SSH.start(@host, @user,  { :port => @port, :compression => false, :password => password } )
		end
		return @ssh
	end

	def disconnect()
		@ssh.shutdown!
		@ssh = nil
	end
end

# {{{ This function returns a hash which contains user, host, port from a given string *url* which is formated[user@]host[:port]
def connection_info(url)
	url =~ /^(?:([a-z0-9-]+)@)?([a-z0-9-]+(?:\.[a-z0-9-]+)*)(?::(\d+))?$/i
	user = $1
	user = "root" if !$1
	port = $3
	port = "22" if !$3
	host = $2
	{ :user => user, :host => host, :port => port }
end
#}}}

# {{{ read_hostlist
def read_hostlist(file)
	gwhosts = [ ]
	gateway = nil
	File.open(file).each do |line|
		# Remove linefeed, comment and whitespace
		clean_line = line.chomp.match(/^([^#]*)/)[1].strip
		if clean_line.length > 0
			# Strip possible in-line comment
			# a "gateway" statement?
			if matchdata = clean_line.match( /^gateway (\S+)/ )
				gateway = matchdata[1]
			# a "end" statement
			elsif clean_line =~ /^end$/
				gateway = nil
			# a host?
			else
				# Gateway already in structure?
				if i = gwhosts.index{ | gw | gw['gateway'] == gateway }
					# Add host to it
					gwhosts[i]['hosts'] += [ clean_line ]
				else
					# Add a new entry for the gateway
					gwhosts += [ 
						{
							'gateway' => gateway,
							'hosts' => [ clean_line ]
						}
					]
				end
			end
		end
	end # File.open
	return gwhosts
end
# }}}

# {{{ read_keylist
def read_keylist(file)
	keys = [ ]
	# Get path of the keylist file directory
	# and append it to each file so that relative
	# pathes in keylist files work correctly
	path = File.dirname(file)
	File.open( file ).each do |line|
		# Remove linefeed, comment and whitespace
		clean_line = line.chomp.match(/^([^#]*)/)[1].strip

		# Add a "+" before host if it does not already have
		# a + or - before it
		clean_line = "+" + clean_line if clean_line =~ /^[^+-]/

		# Add key
		# Compose string of first character + File.Join of path and everything
		# from second character
		# FIXME Fix this crude hack and make a hash out of it or something.
		keys << clean_line[0..0] + File.join( path, clean_line[1..-1] ) if clean_line.length > 0
	end

	return keys
end
# }}}

# {{{ read_char
# Read a single char from stdin
# http://rubyquiz.com/quiz5.html
def read_char
		system "stty raw -echo"
		return STDIN.getc
ensure
		system "stty -raw echo"
end
# }}}

# Parse options
host = nil
hostlist = nil
keys = [ ]
keyfile = nil
gateway = nil
gwhosts = nil
interactive = false

opts = OptionParser.new do | opt |
	opt.banner = "Usage "+$0.to_s+" <optionen> <aktion>"

	opt.on( "-H", "--host <host>", "Host to connect to (Syntax: [user@]host[:port])." ) do | value |
		host = value.to_s
	end

	opt.on( "-h", "--hostlist <hostlist>", "File with hosts to connect to." ) do | value |
		hostlist = value.to_s
		gwhosts = read_hostlist( hostlist )
	end

	opt.on( "-K", "--key <key>", "Keyfile to add or remove from the server." ) do | value |
		keys = [ value.to_s ]
	end

	opt.on( "-k", "--keylist <keylist>", "File with names of keyfiles to add or remove.") do | value |
		keylist = value.to_s
		keys = read_keylist( keylist )
	end

	opt.on( "-G", "--gateway <gateway>", "Gateway to access the host via port forwarding." ) do | value |
		gateway = value.to_s
	end
	
	opt.on( "-i", "--interactive", "Ask before each operation on a host." ) do
		interactive = true
	end
end

# Parse arguments

begin
	opts.parse!( ARGV )
	
	# Transform gateway and host in our data structure for the loop
	if host
		gwhosts = [ {
			'gateway' => gateway,
			'hosts' => [ host ]
		} ]
	end

	action = ARGV[0] || raise( "Need an action in order to do something." )
	
	raise ( "Unsupported action." ) if not ( action == "add" or action == "remove" or action == "addremove" or action == "list" or action == "ssh" )
	
	raise ( "Need a keyfile." ) if keys == nil and not ( action == "list" )

	gwhosts.each do | gwhost |
		gateway = gwhost['gateway']
		hosts = gwhost['hosts']
		
		puts "Gateway: #{gateway}." if gateway
		
		# Gateway?
		if gateway
			gateway_data = connection_info( gateway )
			
			# Initialize a new gateway...
			ssh_gateway = SSHGateway.new( gateway_data )
			
			# ... and connect to it
			ssh_gateway_connected = ssh_gateway.connect
		end

		hosts.each do | host |
			puts "Host: #{host}."
			
			# {{{ interactive mode
			if interactive == true then
				skip = false
				puts "Continue (RETURN), skip this host (s), quit (q)?"
				begin
					char = read_char()
					# Bei q oder Q abbrechen
					if char == 81 or char == 113 then
						exit 0
					end
					# Bei S den Eintrag ueberspringen
					if char == 83 or char == 115
						skip = true
						char = 13
					end
				end until char == 13
			end
			# }}} interactive mode

			# Den aktuellen Eintrag dann wirklich ueberspringen
			next if skip == true
			
			host_data = connection_info( host )

			ssh_host = nil
			# We use OpenSSH client for starting interactive SSH sessions
			# Did not find a way to do it with Net:SSH v2
			if action != "ssh"
				# Initialize a new SSH host...
				if gateway
					ssh_host = SSHHost.new( host_data, ssh_gateway_connected )
				else
					ssh_host = SSHHost.new( host_data )
				end

				# ... and connect to it
				password = nil
				begin
					ssh = ssh_host.connect( password )
				# FIXME put error handling into the SSHHost class?
				rescue Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Net::SSH::AuthenticationFailed, SocketError => exception
					STDERR.puts "#{exception.class}: #{exception.message}"
					if exception.class == Net::SSH::AuthenticationFailed
						puts "Password - is shown as you type! - (RETURN for skipping the host): "
						password = STDIN.readline.chomp.strip
						retry if password.length>0
					end
					STDERR.puts "ERROR: Error connecting #{host}! Skipping it..."
					next
				end
			end
			
			case action
			when "list"
				authkeys = SSHAuthKeys.new( ssh )
				authkeys.list
			when "add"
				authkeys = SSHAuthKeys.new( ssh )
				keys.each do | key | 
					# ignore +/- sign for add action
					# keys should possibly be a hash, but stripping the +/- works for now
					authkeys.addkeyfile( key[1..-1] )
				end
				# Commit the changes
				authkeys.commit
			when "remove"
				authkeys = SSHAuthKeys.new( ssh )
				keys.each do | key | 
					# ignore +/- sign for remove action
					# keys should possibly be a hash, but stripping the +/- works for now
					authkeys.removekeyfile( key[1..-1] )
				end
				# Commit the changes
				authkeys.commit
			when "addremove"
				authkeys = SSHAuthKeys.new( ssh )
				# add or remove depending on + or - sign
				keys.each do | key | 
					if key[0] == '-'[0]
						authkeys.removekeyfile( key[1..-1] )
					else
						authkeys.addkeyfile( key[1..-1] )
					end
				end
				# Commit the changes
				authkeys.commit
			when "ssh"
				if gateway
					ssh_gateway.gateway.open( host_data[:host], host_data[:port]) do | port |
						puts "WARNING: No host key checking for hosts behind a gateway!"
						puts "SSH'ing to #{host_data[:host]} via #{gateway}..."
						system("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null #{host_data[:user]}@localhost -p #{port}")
					end
				else
					puts "SSH'ing to #{host_data[:host]}..."
					system("ssh #{host_data[:user]}@#{host_data[:host]} -p#{host_data[:port]}")
				end
			else
				# Should not be reachable
				raise( "Unsupported action." )
			end
			
			# Disconnect from the host
			ssh_host.disconnect if ssh_host

		end # hosts.each do

		# Disconnect from the gateway
		if ssh_gateway
			ssh_gateway.disconnect
		end
	end # gateway.each do

# {{{ error handling
rescue OptionParser::ParseError => exc
	# raise
  STDERR.puts opts.to_s
	puts "\nSupported actions:"
	puts "add:       add key(s)."
	puts "remove:    remove key(s)."
	puts "addremove: add keys, then remove keys with \"-\" before filename"
  exit 1
# }}}
end

exit 0

