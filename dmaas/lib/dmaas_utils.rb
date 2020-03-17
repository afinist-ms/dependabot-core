module Dependabot
    module Dmaas
        class Utils
    
            def self.create_npmrc(npmrc_content, registry_token)
                puts "reading .npmrc file"
                home = ENV["HOME"].to_s.strip
                npmrc_path = "#{home}/.npmrc"
                puts "#{npmrc_path}"

                File.delete(npmrc_path) if File.exist?(npmrc_path)

                registries = get_unique_registries(npmrc_content)
                encoded_registry_token = Base64.encode64(registry_token).gsub("\n", "") 

                registries.each do |reg|
                    registry_npmrc_content = get_registry_npmrc_entry(reg, encoded_registry_token)

                    out_file = File.new(npmrc_path, "a")
                    out_file.write(registry_npmrc_content)
                    out_file.write(registry_npmrc_content)
                    out_file.close
                end
            end

            def self.get_registry_credentials(npmrc_content, registry_token)
                # Handle error if token is nil or empty
                registries = get_unique_registries(npmrc_content)
                credentials = []
                token = Base64.encode64(":" + registry_token).gsub("\n", "")

                registries.each do |registry|
                    registry_url = registry
                    credentials << {
                        "type" => "npm_registry",
                        "registry" => registry_url[2..-1],
                        "token" => token
                    }
                end

                credentials
            end

            def self.get_credentials(type, host, password)
                cred = {
                    "type" => type,
                    "host" => host,
                    "password" => password
                }

                cred
            end

            private_class_method def self.get_unique_registries(npmrc_content)
                return [] unless npmrc_content

                npmrc = npmrc_content.split
                registries = []
                npmrc.each do |registry| if registry.include?("registry=")
                    registry_value = registry.split('=').at(1).gsub("https:", "").gsub("http:", "")
                    registries.push(registry_value)
                end
            end

                registries.uniq
            end

            private_class_method def self.get_registry_npmrc_entry(registry_url, registry_token)
                #For e.g the registry url is msasg.pkgs.visualstudio.com/_packaging/ARIA-SDK/npm/registry/ then registry_name is msasg
                registry_name = registry_url[2..-1].split('/').at(0).split('.').at(0)
                registry_password = registry_token
                registry_email = "xyz@abc.com"

                registry_npmrc_content = registry_url + ":username=" + registry_name + "\n"
                registry_npmrc_content += registry_url + ":_password=" + registry_password + "\n"
                registry_npmrc_content += registry_url + ":email=" + registry_email + "\n"

                registry_npmrc_content
            end
        end
    end
end


