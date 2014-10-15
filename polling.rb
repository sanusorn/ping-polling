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
                seedips = array[0]
                #hostname = array[1]
                ips = "#{seedips} #{ips}"
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

  def grep_seed(ip)
        ip_grep = nil
        hostname = nil
        seed = IO.readlines(config[:seed_file])
        #seed.each { |x| x.strip! }
        seed.each { |line|
        array =  line.split(config[:split])
        seedips = array[0]
                if seedips == ip
                # puts "match #{seedips} #{ip}"
                ip_grep = seedips
                hostname = array[1]
                end
        }
        #puts "grep_seed : #{ip_grep} , #{hostname}"
        return [ip_grep, hostname]
  end


  def check_cons(ip, status)
        ip_cons = nil
        cons = 1
        redis = Redis.new
        seed = JSON.parse(redis.get("fping2"))
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
        #puts "redis get: #{ip},#{cons}"
        return [ip_cons ,cons]
  end

  def run
        cmd_out = run_fping
        #ips, file_name = read_seed
		#cmd = "fping #{config[:options]} #{ips} 2>/dev/null"
		#cmd_out = %x[#{cmd}]
		result = cmd_out.each_line("\n").to_a
		value=[]
		cons=1
        # LOOPING RESULT
		result.each { |line|
        array = line.split(' ')
        ip = array[0]
        status = array[2]
		# LOOKUP FOR HOSTNAME
        ip_grep, hostname = grep_seed(ip)
		# OPEN REDIS
		redis = Redis.new
			if redis.exists "fping2"
			# LOOKING FOR EXISTING MSG
			ip_cons, cons = check_cons(ip, status)
			end
        data = "#{ip},#{ip_grep},#{hostname},#{status},#{cons}"
        value << data
			if status == 'unreachable'
				if cons >= config[:count].to_i
                #puts "#{hostname} is #{status} with consecutive #{cons} "
				#send_critical hostname, "Host '#{hostname}':'#{ip} is unreachable"
				end
			else
			#puts "#{hostname} is #{status} with consecutive #{cons} "
			#send_ok hostname, "Host '#{hostname}':'#{ip} is alive"
			end
        }
		redis = Redis.new
		redis.set "fping2",value.to_json
		ok "Finish"
	end

end
