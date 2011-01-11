#!/usr/bin/env ruby

require 'net/ssh/gateway'
require 'net/sftp'


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
		ssh.open_channel do | ch |
		  ch.exec("cat #{authkeyfile}") do | ch, success |
				if success
					ch.on_data do | ch, data |
						@authkeys = data.to_a
						# For debugging purposes
						@authkeys_flat = data
					end
					# Doesn't give stderr at the moment
					ch.on_extended_data do | ch, data |
						puts "ERROR: #{data}"
					end
				end
			end
		end
		# Wait for the above to complete
		ssh.loop
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
						puts "Key #{comment} already there. Skipped."
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
								puts "Key #{comment} deleted."
							end
						end
					else
						puts "Key #{comment} is not there. Skipped."
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

		# Start SFTP session
		puts "Opening SFTP session..."
		sftp = Net::SFTP::Session.new(@ssh)
		sftp.loop { sftp.opening? }

		newauthkeyfile = "#{@authkeyfile}-new"
		puts "Uploading keys to #{newauthkeyfile}..."
		wantedsize = 0
		sftp.file.open(newauthkeyfile , "w" ) do | file |
			@authkeys.each do | line |
				file.puts line
				wantedsize += line.length
			end
		end
		sftp.loop

		request = sftp.lstat(newauthkeyfile) do | response |
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
		sftp.loop
	end

end

#gateway = Net::SSH::Gateway.new('99.99.99.99', 'root')

#authkeys = SSHAuthKeys.new( gateway.ssh('111.111.111', 'root') )

ssh = Net::SSH.start( '192.168.1.1', 'martin', :port => 22, :compression => false )

authkeys = SSHAuthKeys.new( ssh )

authkeys.list

puts

authkeys.addkeyfile( 'id_rsa-test.pub' )

puts

authkeys.list

puts

authkeys.commit

puts

authkeys.removekeyfile( 'id_rsa-test.pub' )

puts
authkeys.list

puts
authkeys.commit
puts

authkeys.removekeyfile( 'id_rsa-test.pub' )

puts

authkeys.commit

ssh.shutdown!

#gateway.shutdown!

