#!/usr/bin/ruby

require 'json'
require 'popen4'
require 'sensu-plugin/check/cli'
require 'redis'

class PingPolling < Sensu::Plugin::Check::CLI

option :handler, :short => '-l HANDLER', :long => '--handler HANDLER', :default => 'default'
option :options, :short => '-a OPTIONS', :long => '--fping-args OPTIONS', :default => '-t100 -i 11'
option :verbose, :short => '-v', :long => '--verbose', :boolean => true, :default => false
option :seed_file, :short => '-f SEED_FILE', :long => '--seed-file SEED_FILE', :default => 'devices.seed'
option :split, :short => '-s SPLIT', :long => '--split SPLIT', :default => ','
option :count, :short => '-c COUNT', :long => '--count COUNT', :default => '0'
option :redis_key, :short => '-k KEY', :long => '--redis-key REDIS_KEY', :default => 'ping-polling:result'
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
    d = { 'name' => check_name, 'status' => 2, 'output' => 'CRITICAL: ' + msg, 'handler' => config[:handler] }
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
                ip_seed = array[0]
                #hostname = array[1]
                ips = "#{ip_seed} #{ips}"
                }
        return [ips,file_name]
 end

 def run_fping
        ips, file_name = read_seed
        cmd = "fping #{config[:options]} #{ips} 2>/dev/null"
        cmd_out = %x[#{cmd}]
		#puts "cmd = #{cmd} : cmd_out = #{cmd_out}"
		return cmd_out
  end

  def check_hostname(ip_current)
        hostname = Array.new
		ip_seed = Array.new
        seed = IO.readlines(config[:seed_file])
        #seed.each { |x| x.strip! }
        seed.each { |line|
        array =  line.split(config[:split])
        ip_seed = array[0]
                if ip_seed == ip_current
                # puts "match #{seedip} #{ip_current}"
                hostname = array[1]
                end
        }
        #puts "check_hostname : #{ip_current} , #{hostname}"
        return [ip_seed,hostname]
  end


  def check_occurrences(ip_current, status)
        ip_history = nil
        seed = JSON.parse($redis.get($redis_key))
        seed.each { |line|
        array =  line.split(',')
        ip_history = array[0]
                if ip_history == ip_current
                # MATCH IP IN DB THEN CHECK OCCURRENCES
					if status == array[3]
					@occurrences = array[4].to_i + 1
					end
                end
        }
        #puts "redis get: #{ip_history},#{@occurrences}"
        return [ip_history,@occurrences]
  end

  def run
        value = Array.new
		# RUN CMD
		cmd_out = run_fping
        #ips, file_name = read_seed
		#cmd = "fping #{config[:options]} #{ips} 2>/dev/null"
		#cmd_out = %x[#{cmd}]
		fping_result = cmd_out.each_line("\n").to_a
		fping_result.each { |line|
		# LOOPING RESULT
		@occurrences = 1
        array = line.split(' ')
        ip_current = array[0]
        status = array[2]
		# LOOKUP FOR HOSTNAME
        ip_seed, hostname = check_hostname(ip_current)
		# OPEN REDIS
		$redis = Redis.new
		$redis_key = config[:redis_key]
			if $redis.exists $redis_key
			# LOOKING FOR EXISTING MSG
			ip_history, @occurrences = check_occurrences(ip_current, status)
			end
        data = "#{ip_current},#{ip_seed},#{hostname.strip},#{status},#{@occurrences}"
        value << data
			if status == 'unreachable'
				if @occurrences >= config[:count].to_i
                #puts "#{hostname} is #{status} with consecutive #{@occurrences} "
				#send_critical hostname, "Host '#{hostname}':'#{ip_current} is unreachable"
				end
			else
				#puts "#{hostname} is #{status} with consecutive #{@occurrences} "
				#send_ok hostname, "Host '#{hostname}':'#{ip_current} is alive"
			end
        }
		$redis.set($redis_key,value.to_json)
		ok "Finish"
	end

end
