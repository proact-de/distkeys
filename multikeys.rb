#!/usr/bin/env ruby

require 'net/ssh'
require 'net/ssh/gateway'
require 'net/sftp'

require 'optparse'

require 'termios'

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

	# List keys
	def list()
		@authkeys.each do | line |
			if line.index('ssh-')
				matches = line.match(/ssh-[^ ]+\s+[A-Za-z0-9=+\/]+ (.*$)/)
				if matches
					puts matches[1]
				else
					puts "WARNING: Key without comment!"
					puts line
				end
			end
		end
	end

	# {{{ Add a key file
	# Replaces it, if the base64 matches, but arguments or comment are different
	def addkeyfile( keyfile )
		if File.exists?( keyfile )
			key = File.new( keyfile, "r" ).to_a

			# Add keys in the file
			key.each do | line |
				# Is this a key?
				if line.index("ssh-")
					# Extract base64 from key
					matchdata = line.match(/ssh-[^ ]+\s+([A-Za-z0-9=+\/]+) (.*$)/)
					# Bail out if it does not appear to be a valid authorized key
					if not matchdata
						puts "ERROR: The following does not seem to be a valid authorized key."
						puts line
						puts "Aborting parsing this keyfile list..."
						return false
					end

					base64 = matchdata[1]
					comment = matchdata[2]
					# Key already there?
					if index = @authkeys.index{ | str | str.include?( base64 ) }
						if @authkeys[ index ] == line
							puts "Key #{comment} already there and identical. Skipped adding it."
						else
							puts "Key #{comment} already there, with different arguments or description. Replacing it..."
							@authkeys[ index ] = line
							@changed = true
						end
					else
						# Add the key
						@authkeys += [ line ]
						@changed = true
						puts "Key #{comment} added."
					end # Key already there?
				end # Is this a key?
			end # Add keys in the file
		else
			puts "ERROR: Keyfile #{keyfile} does not exist. Skipped."
		end
	end
	# }}}
	
	def removekeyfile( keyfile )
		if File.exists?( keyfile )
			key = File.new( keyfile, "r" ).to_a
			
			# Remove keys in the file
			key.each do | line |
				# Is this a key?
				if line.index("ssh-")
					# Extract base64 from key
					matchdata = line.match(/ssh-[^ ]+\s+([A-Za-z0-9=+\/]+) (.*$)/)
					if not matchdata
						puts "ERROR: The following does not seem to be a valid authorized key."
						puts line
						puts "Aborting parsing this keyfile list..."
						return false
					end

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
			puts "ERROR: Keyfile #{keyfile}does not exist. Skipped."
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
		begin
			@sftp.file.open(newauthkeyfile , "w" ) do | file |
				@authkeys.each do | line |
					file.puts line
					wantedsize += line.length
				end
			end
			@sftp.loop
		rescue Net::SFTP::StatusException => exception
			puts	exception.message
			puts "ERROR: Can't open authorized_keys for writing! Skipped."
		end

		# Try to create ~/.ssh if it does not already exist
		@sftp.lstat( "~/.ssh" ) do | response |
			if not response.ok?
				puts "~/.ssh does not seem to exist, creating it with 700..."
				@ssh.exec!( "mkdir ~/.ssh" )
				@ssh.exec!( "chmod 700 ~/.ssh" )
			end
		end

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
	
	# Gateway host data
	attr_reader :host, :port, :user
	
	# Takes a hash with host, port, user as returned from connection_info
	def initialize( ssh_config, hostdata, betweengateway = nil )
		@ssh_config = ssh_config

		@host = hostdata[:host]
		@port = hostdata[:port]
		@user = hostdata[:user]

		@betweengw = betweengateway
	end

	# Connect and return an Net::SSH::Gateway object
	def connect()
		begin
			if @betweengw
				puts "Connecting to gateway (user: #{@user}, port: #{@port}) #{@host} behind #{@betweengw.host}."
				if @betweengwport = @betweengw.gateway.open( @host, @port )
					@gateway = Net::SSH::Gateway.new( "localhost", @user, :port => @betweengwport, :compression => false, :config => @ssh_config )
				end
			else
				puts "Connecting to gateway #{@host} (user: #{@user}, port: #{@port})..."
				@gateway = Net::SSH::Gateway.new(@host, @user, :port => @port, :compression => false, :config => @ssh_config )
			end
		rescue Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Net::SSH::AuthenticationFailed, SocketError => exception
			STDERR.puts "#{exception.class}: #{exception.message}"
			if exception.class == Net::SSH::AuthenticationFailed
				t = Termios.tcgetattr(STDIN)
				old = t
				t.lflag &= ~Termios::ECHO
				Termios.tcsetattr(STDIN, Termios::TCSANOW, t)
				print "Password - (RETURN for skipping the host): "
				password = STDIN.readline.chomp.strip
				Termios.tcsetattr(STDIN, Termios::TCSANOW, old)
				retry if password.length>0
			end
			return false
		end
		
		return @gateway
	end

	def disconnect()
		@gateway.shutdown!
		@gateway = nil
	end
end

class SSHHost
	# Net::SSH instance of the SSH server if connectedssh_gateway
	attr_reader :ssh
	
	# Takes a hash with host, port, user as returned from connection_info
	def initialize( ssh_config, hostdata, gateway = nil )
		@ssh_config = ssh_config

		@host = hostdata[:host]
		@port = hostdata[:port]
		@user = hostdata[:user]
		
		@gateway = gateway
	end

	# Connect and return an Net::SSH object
	def connect( password = nil )
		begin
			if @gateway
				puts "Connecting to host #{@host} (user: #{@user}, port: #{@port}) via gateway #{@gateway.host}..."
				@ssh = @gateway.gateway.ssh(@host, @user, { :port => @port,  :compression => false, :password => password, :config => @ssh_config } )
			else
				puts "Connecting to host #{@host} (user: #{@user}, port: #{@port})..."
				@ssh = Net::SSH.start(@host, @user,  { :port => @port, :compression => false, :password => password, :config => @ssh_config } )
			end
		rescue Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Net::SSH::AuthenticationFailed, SocketError => exception
			STDERR.puts "#{exception.class}: #{exception.message}"
			if exception.class == Net::SSH::AuthenticationFailed
				t = Termios.tcgetattr(STDIN)
				old = t
				t.lflag &= ~Termios::ECHO
				Termios.tcsetattr(STDIN, Termios::TCSANOW, t)
				print "Password - (RETURN for skipping the host): "
				password = STDIN.readline.chomp.strip
				Termios.tcsetattr(STDIN, Termios::TCSANOW, old)
				retry if password.length>0
			end
			return false
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

# {{{ read_keylist
def read_keylist( file )
	keys = [ ]
	# Get path of the keylist file directory
	# and append it to each file so that relative
	# pathes in keylist files work correctly
	path = File.dirname(file)
	File.open( file ).each do |line|
		# Remove linefeed, comment and whitespace
		clean_line = line.chomp.match(/^([^#]*)/)[1].strip

		# Add key
		if clean_line.length > 0
			# [0] should return a substring according to the String class documentation,
			# but it returns a FixNum with the ASCII code instead. [0..0] works as expected
			if clean_line[0..0] == '+' or clean_line[0..0] == '-'
				keys << clean_line[0..0] + File.join( path, clean_line[1..-1] )
			elsif
				keys << File.join( path, clean_line)
			end
		end

	end # File.open

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

def read_hostlist_entry( list, index )
	gwhosts = []

	while index < list.count
	# Remove linefeed, comment and whitespace
	clean_line = list[ index ].chomp.match(/^([^#]*)/)[1].strip

		if clean_line.length > 0
			# a "gateway" statement?
				if matchdata = clean_line.match( /^gateway (\S+)/ )
					gateway = matchdata[1] 
					gwhosts << { gateway => [ ] }

					# recursively call us self
					gwhosts.last[gateway], index = read_hostlist_entry( list, index + 1 )
				# an "end" statement?
				elsif clean_line =~ /^end$/
					return gwhosts, index
				# a host
				else
					gwhosts << clean_line
				end
		end

		index = index + 1
	end # while

	return gwhosts, index
end

# {{{ read_hostlist
def read_hostlist( file )
	gwhosts = [ ]

	# Read file into array
	list = File.open(file, "r").to_a

	# read all hosts and gateways recursively
	gwhosts, dummy = read_hostlist_entry( list, 0 )

	return gwhosts
end
# }}}

class GWHosts

	# Return code for leaving the gwhost recursion immediately
	LEAVE = 80000004

	def initialize( gwhosts, args )
		@gwhosts = gwhosts

		@ssh_config = args['ssh_config']

		@interactive = args['interactive']
		@action = args['action']
		@keys = args['keys']

		@cmd = args['cmd']
		@script = args['script']
	end
	
	def handle_gateway( gateway, betweengateway = nil )
		gateway_data = connection_info( gateway )

		# Initialize a new gateway...
		ssh_gateway = nil
		if betweengateway
			ssh_gateway = SSHGateway.new( @ssh_config, gateway_data, betweengateway )
		else
			ssh_gateway = SSHGateway.new( @ssh_config, gateway_data )
		end

		# ... and connect to it
		if ssh_gateway.connect
			return ssh_gateway
		else
			return false
		end
	end
	
	# {{{ start interactive ssh session
	def start_ssh_session( host_data, gateway, cmd = nil )
		ssh_config_opt = case @ssh_config
			when true then ""
			when false, nil then ""
			else "-F #{@ssh_config}"
			end

		if gateway
			gateway.gateway.open( host_data[:host], host_data[:port]) do | port |
				puts "WARNING: No host key checking for hosts behind a gateway!"
				puts "SSH'ing to #{host_data[:host]} (user: #{host_data[:user]}, port: #{port}) via gateway #{gateway.host}..."
				system("ssh #{ssh_config_opt} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null #{host_data[:user]}@localhost -p #{port} #{cmd}")
			end
		else
			puts "SSH'ing to #{host_data[:host]}) (user: #{host_data[:user]}, port: #{host_data[:port]})..."
			system("ssh #{ssh_config_opt} #{host_data[:user]}@#{host_data[:host]} -p#{host_data[:port]} #{cmd}")
		end
	end
	
	# {{{ handle a single host }}}
	def handle_host( host, gateway = nil )
		if gateway
			puts "Host: #{host} via #{gateway.host}"
		else
			puts "Host: #{host}"
		end
		
		# {{{ interactive mode
		if @interactive == true then
			skip = false
			puts "Continue (RETURN), skip this host (s), quit (q)?"
			begin
				char = read_char()
				# Bei q oder Q abbrechen
				if char == 81 or char == 113 then
					# leave the gwhost recursion immediately
					return LEAVE
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
		return true if skip

		host_data = connection_info( host )

		ssh_host = nil
		# We use OpenSSH client for starting interactive SSH sessions
		# Did not find a way to do it with Net:SSH v2
		if @action != "ssh"
			# Initialize a new SSH host...
			if gateway
				ssh_host = SSHHost.new( @ssh_config, host_data, gateway )
			else
				ssh_host = SSHHost.new( @ssh_config, host_data )
			end

			# ... and connect to it
			if not ssh = ssh_host.connect()
				return false
			end
		end

		case @action
		when "list"
			authkeys = SSHAuthKeys.new( ssh )
			authkeys.list
		when "hostname"
			puts ssh.exec!("hostname")
		when "add"
			authkeys = SSHAuthKeys.new( ssh )
			@keys.each do | key |
				# [0] should return a substring according to the String class documentation,
				# but it returns a FixNum with the ASCII code instead. [0..0] works as expected
				if key[0..0] == '+' or key[0..0] == '-'
					raise OptionParser::ParseError, "ERROR: +/- in keylist is only valid for addremove action."
				end
			end
			@keys.each do | key |
				authkeys.addkeyfile( key )
			end
			# Commit the changes
			authkeys.commit
		when "remove"
			authkeys = SSHAuthKeys.new( ssh )
			@keys.each do | key |
				# [0] should return a substring according to the String class documentation,
				# but it returns a FixNum with the ASCII code instead. [0..0] works as expected
				if key[0..0] == '+' or key[0..0] == '-'
					raise OptionParser::ParseError, "ERROR: +/- in keylist is only valid for addremove action."
				end
			end
			@keys.each do | key | 
				authkeys.removekeyfile( key )
			end
			# Commit the changes
			authkeys.commit
		when "addremove"
			authkeys = SSHAuthKeys.new( ssh )
			# add or remove depending on + or - sign
			@keys.each do | key | 
				# [0] should return a substring according to the String class documentation,
				# but it returns a FixNum with the ASCII code instead. [0..0] works
				# as expected
				if key[0..0] == '-'
					authkeys.removekeyfile( key[1..-1] )
				elsif key[0..0] == '+'
					authkeys.addkeyfile( key[1..-1] )
				else # if no + or - then add it as well
					authkeys.addkeyfile( key )
				end
			end
			# Commit the changes
			authkeys.commit
		when "ssh"
			start_ssh_session( host_data, gateway )
		when "cmd"
			start_ssh_session( host_data, gateway, @cmd )
		when "script"
			# Start SFTP session
			puts "Uploading script #{@script}..."
			@sftp = Net::SFTP::Session.new(ssh)
			@sftp.loop { @sftp.opening? }

			remote = "/tmp/multikeys-script-action-#{File.basename(@script) + "-" + Time.now.strftime( "%Y-%M-%d" ) + "-" + rand(1000000).to_s}"

			begin
				@sftp.upload!( @script, remote  )
			rescue RuntimeError => exception
				puts	exception.message
				puts "ERROR: Can't upload #{script}. Skipping..."
			end
			@sftp.loop

			request = @sftp.setstat( remote, :permissions => 0500 )
			request.wait
			if request.response.ok?
				puts "Executing script..."
				start_ssh_session( host_data, gateway, remote )
				@sftp.remove!( remote )
			end
		when "scp"
			# XXX: somewhat hacky for now
			tmp_dir_name = "/tmp/multikeys-upload-" + Time.now.strftime( "%Y-%M-%d" ) + "-" + rand(1000000).to_s
			puts "Uploading file to file #{tmp_dir_name}..."

			@sftp = Net::SFTP::Session.new(ssh)
			@sftp.loop { @sftp.opening? }

			begin
				@sftp.upload!( @script, tmp_dir_name )
			rescue RuntimeError => exception
				puts	exception.message
				puts "ERROR: Can't upload #{script}. Skipping..."
			end
			@sftp.loop
		else
			# Should not be reachable
			raise( OptionParser::ParseError, "Unsupported action." )
		end

		# Disconnect from the host
		ssh_host.disconnect if ssh_host
	end

	# {{{ handle_gw_host recursively
	# level is for tracking recursion level
	# leave is for leaving recursion before it finished
	def handle_gwhost( gwhosts, level = 0, leave = false, usegateway = nil )
		return true if leave

		gwhosts.each do | gwhost |
			if gwhost.class == Hash
				gwhost.each do| gateway, hostlist |
					puts "Gateway: #{gateway}, Level #{level + 1}"
					
					if usegateway  = handle_gateway( gateway, usegateway )
						# Call ourselves recursively for handling nested gateways
						handle_gwhost( hostlist, level + 1, leave, usegateway)
					else
						puts "ERROR: Connecting to gateway #{gateway} failed! Skipped."
					end
				end
			else
				rc = handle_host( gwhost, usegateway )
				case rc
				when LEAVE
					leave = true
					break
				when false
					STDERR.puts "ERROR: Error connecting #{gwhost}! Skipping it..."
				end
			end
		end
	end
	# }}}
	
	# Do the magic
	def loop()
		handle_gwhost( @gwhosts )
	end

end

# Parse options
ssh_config = true
host = nil
hostlist = nil
keys = [ ]
keyfile = nil
gateway = nil
gwhostlist = nil
interactive = false

opts = OptionParser.new do | opt |
	opt.banner = "Usage "+$0.to_s+" <optionen> <action>"

	opt.on( "-F", "--configfile <file>", "Alternative SSH per-user configuration file." ) do | value |
		ssh_config = value.to_s
	end

	opt.on( "-H", "--host <host>", "Host to connect to (Syntax: [user@]host[:port])." ) do | value |
		host = value.to_s
	end

	opt.on( "-h", "--hostlist <hostlist>", "File with hosts to connect to." ) do | value |
		hostlist = value.to_s
		gwhostlist = read_hostlist( hostlist )
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
cmd = nil
script = nil

begin
	opts.parse!( ARGV )

	if gwhostlist and (host or gateway)
		raise OptionParser::ParseError, ( "Ambiguous options: do not specify -h and -G/-H." )
	end
	
	# Transform gateway and host in our data structure for the loop
	if host and gateway
		gwhostlist = [ {
			gateway => [ host ]
		} ]
	elsif host
		gwhostlist = [ host ]
	end

	action = ARGV[0] || raise( OptionParser::ParseError, "Need an action in order to do something." )
	
	raise OptionParser::ParseError, ( "Unsupported action." ) if not ( action == "add" or action == "remove" or action == "addremove" or action == "list" or action == "ssh" or action == "cmd" or action == "script" or action == "scp" or action == "hostname" )
	
	raise OptionParser::ParseError, ( "Need a keyfile." ) if keys == nil and not ( action == "list" )

	if action == "cmd"
		cmd = ARGV[1] || raise( OptionParser::ParseError, "Need a command to execute with action #{action}." )
	end

	if action == "script" or action == "scp"
		script = ARGV[1] || raise( OptionParser::ParseError, "Need a filename with action #{action}." )
	end

	# handle gateways and hosts recursively
	gwhosts = GWHosts.new( gwhostlist, 'ssh_config' => ssh_config, 'interactive' => interactive, 'action' => action, 'keys' => keys, 'cmd' => cmd, 'script' => script )

	# Do the magic
	gwhosts.loop

# {{{ error handling
rescue OptionParser::ParseError => exc
	# raise
	STDERR.puts exc.message
  STDERR.puts opts.to_s
	puts "\nSupported actions:"
	puts "add:             Add or update key(s). Replaces a key if base64 matches,"
	puts "                 but description or arguments differ."
	puts "addremove:       Add keys, then remove keys with \"-\" before filename."
	puts "cmd <cmd>:       Exectute command <cmd>."
	puts "hostname:        Show hostname."
	puts "list:            List authorized keys."
	puts "remove:          Remove key(s)."
	puts "script <script>: Upload <script> to server and execute it."
	puts "scp <file>:      Upload <file> to the server."
	puts "ssh:             Start interactive SSH session."
  exit 1
# }}}
end

exit 0

