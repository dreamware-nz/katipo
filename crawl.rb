require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'uri'
require 'addressable/uri'
require 'fileutils'
require 'typhoeus'

Typhoeus::Config.user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.89 Safari/537.36"

class Agent
    def initialize(start_point)
        @seen = {}
        @stack = [start_point]
    end

    def run
        while l = @stack.pop
            @seen[l] = true
            puts "-" * 80
            puts "crawling #{l}"
            fetch(l)
        end
    end

    private
    def mkdir(path)
        puts "mkdir: " + path
        location = []
        path.split("/").each do |fragment|
            location << fragment
            new_path = location.join("/")
            move = false

            if File.file?(new_path)
                puts "moving existing file #{new_path} out of the way to #{new_path + '~'} for directory"
                FileUtils.mv(new_path, new_path + "~")
                move = true
            end

            unless File.exists?(new_path)
                puts "creating new directory at: #{new_path}"
                Dir.mkdir(new_path)
            end
            new_file_path = File.join(new_path, "index.html")
            
            if move
                puts "moving existing file #{new_path + '~'} back into new directory #{new_file_path}"
                FileUtils.mv(new_path + "~", new_file_path)
            end
        end
    end

    def absolutize(url, path)
        return if url.nil? || path.nil?
        begin
            uri = Addressable::URI.parse(url)
            path = Addressable::URI.parse(path).omit(:query, :fragment)
        
            return if path.host && path.host != uri.host
            uri = uri.join(Addressable::URI.parse(path))
            return if uri.scheme !~ /https?/
            return URI(uri.to_s).to_s rescue nil
        rescue URI::InvalidURIError, Addressable::URI::InvalidURIError
        end
    end
    
    def links(url, dom)
        dom.css("a").map{ |l| absolutize(url, l.attr("href")) }.compact.uniq
    end

    def save(url, response)
        content = response.body
        uri = Addressable::URI.parse(url).omit(:scheme)

        # escape params in file paths (probably wont happen)
        local_path = uri.to_s.gsub(/([\?&])/, '\\1')

        # remove the // from the beginning of the address
        local_path[0] = ''
        local_path[0] = ''

        # remove a trailing / if present
        local_path.chop! if local_path.end_with?("/")

        # extract the file name and the dir from the local path
        file = File.basename(local_path)
        dir = File.dirname(local_path)

        # make the local directory
        mkdir(dir)

        # if the dir is '.' (this dir), remove the reference
        dir = nil if dir == "."

        # set the local file path again
        local_path = File.join(*[dir, file].compact)

        # mkdir(local_path)
        local_path += "/index.html" if File.directory?(local_path)
        suffix = File.extname(local_path)

        puts "url:        #{url}"
        puts "local_path: #{local_path}"
        puts "basename:   #{file}"
        puts "suffix:     #{suffix}"

        local_path += ".html" if suffix == ""

        # TODO handle .pdf or other suffixes causing this to misbehave
        puts "writing #{url} to #{local_path}"
        open(local_path, "w") do |f|
            f.puts content
        end
    end
    
    def get(url)
        request = Typhoeus::Request.new(url, followlocation: true)
        request.on_complete do |response|
            if response.success?
                save(url, response)
                return response.body
            end
            return ""
        end
          
        request.run
    end

    def fetch(url)
        @stack.push *links(url, Nokogiri::HTML.parse(get(url))).reject{ |l| @seen.has_key?(l) }
    end
end

Agent.new(ARGV[0]).run