#!/usr/bin/ruby

require 'json'
require 'popen4'
require 'sensu-plugin/check/cli'
require 'redis'

class PingPolling < Sensu::Plugin::Check::CLI

option :handler, :short => '-l HANDLER', :long => '--handler HANDLER', :default => 'default'
option :options, :short => '-a OPTIONS', :long => "--fping-args OPTIONS", :default => '-t100 -i 11'
option :verbose, :short => '-v', :long => "--verbose", :boolean => true, :default => false
option :seed_file, :short => '-f SEED_FILE', :long => "--seed-file SEED_FILE", :default => 'devices.seed'
option :split, :short => '-s SPLIT', :long => '--split SPLIT', :default => ','
option :count, :short => '-c COUNT', :long => "--count COUNT", :default => '0'
#consecutive

 def sensu_client_socket(msg)
    u = UDPSocket.new
    u.send(msg + "\n", 0, '127.0.0.1', 3030)
 end

 def send_ok(check_name, msg)
    d = { 'name' => check_name, 'status' => 0, 'output' => 'OK: ' + msg, 'handler' => config[:handler] }
    sensu_client_socket d.to_json
 end

 def send_warning(check_name, msg)
    d = { 'name' => check_name, 'status' => 1, 'output' => 'WARNING: ' + msg, 'handler' => config[:handler] }
    sensu_client_socket d.to_json
 end

 def send_critical(check_name, msg)
timestamp = Time.now.utc.to_i
    d = { 'name' => check_name, 'status' => 2, 'output' => 'CRITICAL: ' + msg, 'occurrences' => 1, 'interval' => 60, 'refresh' => 6000, 'executed' => timestamp, 'handler' => config[:handler] }
    sensu_client_socket d.to_json
 end
 
 def check_file(file)
	if File.exist?("#{file}")
	puts "Check file exist: #{file}" if config[:verbose]
	else
	warning "File not found"
	end
 end

 
 def read_seed
	ips = nil
	file_name = config[:seed_file]
	check_file("#{file_name}")
	seed_file = IO.readlines(file_name)
	seed_file.each { |line|
		next if(line[0..0] == '#' || line.empty?)
		array =  line.split(config[:split])
		seedips = array[0]
		#hostname = array[1]
		ips = "#{seedips} #{ips}"
		}
	return [ips,file_name]
 end
 

 def run_fping
	ips, file_name = read_seed
	file_out = "#{file_name}.out"
	cmd = "fping #{config[:options]} #{ips} 2>/dev/null > #{file_out}"
	puts "Run Command: #{cmd}" if config[:verbose]
    stats = nil
    errors = nil
    result = POpen4::popen4(cmd) do |stdin, stdout, stderr, pid|
      stats = stdout.read
      begin
        errors = stderr.read
      rescue
        # stderr is not always open for reading.
      end
    end
    exit_status = result ? result.exitstatus : nil
    return [file_out]
  end

  def new_fping
	
	ips, file_name = read_seed
	file_out = "#{file_name}.out"
	cmd = "fping #{config[:options]} #{ips} 2>/dev/null > #{file_out}"
	%x[#${cmd}]
	
	#puts "Run Command: #{cmd}" if config[:verbose]

    return [file_out]
  end

  
  def grep_seed(ip)
	ip_grep = nil
	hostname = nil
	seed = IO.readlines(config[:seed_file])
	seed.each { |x| x.strip! }
	seed.each { |line|
	seed2 =  line.split(config[:split])
	seedips = seed2[0] 
		if seedips == ip
		# puts "match #{seedips} #{ip}"
		ip_grep = seedips
		hostname = seed2[1]
		end
	}
	#p ip_grep
	return [ip_grep, hostname]   
  end 
	
  
  def check_cons(ip, status)
	ip_cons = nil
	cons = 1
	redis = Redis.new
	seed = JSON.parse(redis.get("fping"))

	#seed.each { |x| x.strip! }
	seed.each { |line|
	array =  line.split(',')
	ip_cons = array[0]
		if ip_cons == ip
		# MATCH IP IN DB THEN CHECK VALUE
			if status == array[3]
			cons = array[4].to_i + 1
			else
			cons = 1
			end
		end
	}
	#puts "#{ip},#{cons}"	
	return [ip_cons ,cons]
  end

  def run
	#file_out = run_fping
	#array1 = IO.readlines(file_out)
	#array1.each { |x| x.strip! }
	ips, file_name = read_seed
	cmd = "fping #{config[:options]} #{ips} 2>/dev/null"
	file_out = %x[#{cmd}]
	array1 = file_out.each_line("\n").to_a
	op=[]
	cons=1
	#array2=[]
	array1.each { |line|
	array2 = line.split(' ')
	ip = array2[0] 
	status = array2[2]

	ip_grep, hostname = grep_seed(ip)
	ip_cons, cons = check_cons(ip, status)

	a = "#{ip},#{ip_grep},#{hostname},#{status},#{cons}"	
	op << a

		if status == 'unreachable'
			if cons >= config[:count].to_i
		#puts "#{hostname} is #{status} with consecutive #{cons} "
		send_critical hostname, "Host #{hostname} [#{ip}] is unreachable"
			end
		else
		#puts "#{hostname} is #{status} with consecutive #{cons} "
		send_ok hostname, "Host '#{hostname}':'#{ip} is alive"
		end

	#puts "#{ip}, #{ip_grep}, #{hostname}, #{status}"
	}

redis = Redis.new
redis.set "fping",op.to_json




	ok "done"

	end

end
