require "dependabot/file_fetchers"
require "dmaas_utils"


module Dependabot
    module Dmaas
        class DmaasRun


            attr_reader :repo, :package_manager, :repo_token, :registry_token,
                        :github_token, :provider, :branch, :directory, :dependency,
                        :commit, :requirements_update_strategy, :lockfile_only, :pr_count

            def initialize(repo:, package_manager:, repo_token:, registry_token:, 
                           github_token:, provider: "azure", branch:nil, directory:"/", 
                           dependency:nil, commit:nil, requirements_update_strategy: nil, lockfile_only: false, pr_count:-1)
                           @repo = repo
                           @package_manager = package_manager
                           @repo_token = repo_token
                           @registry_token = registry_token
                           @github_token = github_token
                           @provider = provider
                           @branch = branch 
                           @directory = directory
                           @dependency = dependency
                           @commit = commit
                           @requirements_update_strategy = requirements_update_strategy
                           @lockfile_only = lockfile_only
                           @pr_count = pr_count

                           check_inputs
            end

            def process_event

                #Add caching of dependency files
                puts "=> Fetching dependency files"
                dependency_files = file_fetcher.files

                puts "=> Fetching registry credentials"
                registry_credentials = Dependabot::Dmaas::Utils.get_registry_credentials(file_fetcher.npmrc_content, registry_token)
                credentials.concat(registry_credentials)

                puts "=> Generating .npmrc content"
                Dependabot::Dmaas::Utils.create_npmrc(file_fetcher.npmrc_content, registry_token)

                #Add dependency caching
                puts "=> Parsing dependency files"
                dependencies = get_dependencies(dependency_files)

                puts "=> Updating #{dependencies.count} dependencies"

                # Added support to group update dependencies

                if pr_count == -1
                    pr_count = dependencies.length
                end
                
                count = 0
                dependencies.each do |dependency|

                    if count == pr_count
                        break
                    end

                    updated_dependencies = update_dependencies([dependency])

                    if updated_dependencies.length == 0
                        next
                    end
                    updated_dependency_files = generate_updated_dependency_files(updated_dependencies, file_fetcher.files)
                    pull_request_creator = pull_request_creator(updated_dependencies, updated_dependency_files)

                    if !pull_request_creator.pull_request_exists
                        count += 1
                    end

                    pull_request_creator.create
                end
            end

            def source
                @source ||= Dependabot::Source.new(
                    provider: provider,
                    repo: repo,
                    directory: directory,
                    branch: branch,
                    commit: commit
                    )
            end

            def file_fetcher
                @file_fetcher ||= Dependabot::FileFetchers.for_package_manager(package_manager).
                            new(source: source, credentials: credentials)
            end

            def file_parser(dependency_files)
                @file_parser ||= Dependabot::FileParsers.for_package_manager(package_manager).new(
                    dependency_files: dependency_files,
                    source: source,
                    credentials: credentials
                )
            end

            def update_checker(dependency, files)
                Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
                    dependency: dependency,
                    dependency_files: files,
                    credentials: credentials,
                    requirements_update_strategy: requirements_update_strategy
                    #ignored_versions: ignore_conditions_for(dependency),
                    #security_advisories: security_advisories_for(dependency),
                )
            end

            def file_updater(dependencies, dependency_files)
                Dependabot::FileUpdaters.for_package_manager(package_manager).new(
                    dependencies: dependencies,
                    dependency_files: dependency_files,
                    credentials: credentials
                  )
            end

            def pull_request_creator(updated_dependencies, updated_files)
                Dependabot::PullRequestCreator.new(
                    source: source,
                    base_commit: file_fetcher.commit,
                    dependencies: updated_dependencies,
                    files: updated_files,
                    credentials: credentials
                    )
            end

            def credentials
                @credentials ||= [repo_credentials, github_credentials].compact
            end

            def repo_credentials
                #make this according to the provider
                Dependabot::Dmaas::Utils.get_credentials("git_source", "dev.azure.com", repo_token)
            end

            def github_credentials
                return unless github_token
                Dependabot::Dmaas::Utils.get_credentials("git_source", "github.com", github_token)
            end

            def get_dependencies(dependency_files)
                dependencies = file_parser(dependency_files).parse

                if dependency.nil?
                    dependencies.select!(&:top_level?)
                else
                    dependencies.select! { |d| d.name == dependency }
                end
                
                dependencies
            end

            def update_dependencies(dependencies)
                updated_dependencies = []
                dependencies.each do |dependency|
                    update_checker = update_checker(dependency, file_fetcher.files)
                    requirements_to_unlock = get_requirements_to_unlock(update_checker)

                    if !can_update_dependency?(update_checker, dependency, requirements_to_unlock)
                        next
                    end

                    # Get the requiements to unlock
                    updated_dependencies << update_checker.updated_dependencies(
                        requirements_to_unlock: requirements_to_unlock
                    )
                end
                
                updated_dependencies
            end

            def can_update_dependency?(update_checker, dependency, requirements_to_unlock)
                puts "\n=== #{dependency.name} (#{dependency.version})"
                puts " => checking for updates"
                puts " => latest version from registry is #{update_checker.latest_version}"
                puts " => latest resolvable version is #{update_checker.latest_resolvable_version}"

                if update_checker.up_to_date?
                    puts "=> (no update needed)"
                    return false
                end

                if requirements_to_unlock == :update_not_possible && !peer_dependencies_can_update?(update_checker, requirements_to_unlock)
                   puts "=> (update not possible)"
                   return false
                end
                 
                return true
            end

            def generate_updated_dependency_files(updated_dependencies, dependency_files)
                if updated_dependencies.count == 1
                    updated_dependency = updated_dependencies.first.first
                    puts " => updating #{updated_dependency.name} from " \
                         "#{updated_dependency.previous_version} to " \
                         "#{updated_dependency.version}"
                else
                    dependency_names = updated_dependencies.map(&:name)
                    puts " => updating #{dependency_names.join(', ')}"
                end
                
                updater = file_updater(updated_dependencies, dependency_files)
                updater.updated_dependency_files
            end

            def create_pr

            end

            private 

            def check_inputs
                if repo.nil? || repo.strip.empty?
                    raise "Invalid repo name"
                elsif package_manager.nil? || package_manager.strip.empty? then
                    raise "Invalid Package manager"
                elsif repo_token.nil? || repo_token.strip.empty? then
                    raise "Invalid Repo Token"
                elsif registry_token.nil? || registry_token.strip.empty? then
                    raise "Invalid registry token"
                end 
            end

            def get_requirements_to_unlock(update_checker)
                requirements_to_unlock = 
                if lockfile_only || !update_checker.requirements_unlocked_or_can_be?
                    if update_checker.can_update?(requirements_to_unlock: :none) then :none
                    else :update_not_possible
                    end
                  elsif update_checker.can_update?(requirements_to_unlock: :own) then :own
                  elsif update_checker.can_update?(requirements_to_unlock: :all) then :all
                  else :update_not_possible
                end

                puts "=> requirements to unlock: #{requirements_to_unlock}"

                requirements_to_unlock
            end

            def peer_dependencies_can_update?(update_checker, requirements_to_unlock)
                update_checker.updated_dependencies(requirements_to_unlock: requirements_to_unlock).
                reject { |dep| dep.name == update_checker.dependency.name }.
                any? do |dep|
                original_peer_dep = ::Dependabot::Dependency.new(
                   name: dep.name,
                   version: dep.previous_version,
                   requirements: dep.previous_requirements,
                   package_manager: dep.package_manager
                )
                update_checker(original_peer_dep).
                   can_update?(requirements_to_unlock: :own)
                end
            end
        end
    end
end

        