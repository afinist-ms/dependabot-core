# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/npm_and_yarn/dependency_files_filterer"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/npm_lockfile_updater"
      require_relative "file_updater/yarn_lockfile_updater"
      require_relative "file_updater/pnpm_lockfile_updater"

      class NoChangeError < StandardError
        def initialize(message:, error_context:)
          super(message)
          @error_context = error_context
        end

        def raven_context
          { extra: @error_context }
        end
      end

      def self.updated_files_regex
        [
          /^package\.json$/,
          /^package-lock\.json$/,
          /^npm-shrinkwrap\.json$/,
          /^yarn\.lock$/,
          /^shrinkwrap\.yaml$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        updated_files += updated_manifest_files
        updated_files += updated_lockfiles

        if updated_files.none?
          raise NoChangeError.new(
            message: "No files were updated!",
            error_context: error_context(updated_files: updated_files)
          )
        end

        sorted_updated_files = updated_files.sort_by(&:name)
        if sorted_updated_files == filtered_dependency_files.sort_by(&:name)
          raise NoChangeError.new(
            message: "Updated files are unchanged!",
            error_context: error_context(updated_files: updated_files)
          )
        end

        updated_files
      end

      private

      def filtered_dependency_files
        @filtered_dependency_files ||=
          begin
            if dependencies.select(&:top_level?).any?
              DependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: dependencies
              ).files_requiring_update
            else
              SubDependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: dependencies
              ).files_requiring_update
            end
          end
      end

      def check_required_files
        raise "No package.json!" unless get_original_file("package.json")
      end

      def error_context(updated_files:)
        {
          dependencies: dependencies.map(&:to_h),
          updated_files: updated_files.map(&:name),
          dependency_files: dependency_files.map(&:name)
        }
      end

      def package_locks
        @package_locks ||=
          filtered_dependency_files.
          select { |f| f.name.end_with?("package-lock.json") }
      end

      def yarn_locks
        @yarn_locks ||=
          filtered_dependency_files.
          select { |f| f.name.end_with?("yarn.lock") }
      end

      def shrinkwraps
        @shrinkwraps ||=
          filtered_dependency_files.
          select { |f| f.name.end_with?("npm-shrinkwrap.json") }
      end

      def package_files
        @package_files ||=
          filtered_dependency_files.select do |f|
            f.name.end_with?("package.json")
          end
      end

      def yarn_lock_changed?(yarn_lock)
        yarn_lock.content != updated_yarn_lock_content(yarn_lock)
      end

      def package_lock_changed?(package_lock)
        package_lock.content != updated_package_lock_content(package_lock)
      end

      def shrinkwrap_changed?(shrinkwrap)
        shrinkwrap.content != updated_package_lock_content(shrinkwrap)
      end

      def updated_manifest_files
        package_files.map do |file|
          updated_content = updated_package_json_content(file)
          next if updated_content == file.content

          updated_file(file: file, content: updated_content)
        end.compact
      end

      def updated_lockfiles
        updated_files = []

        yarn_locks.each do |yarn_lock|
          next unless yarn_lock_changed?(yarn_lock)

          updated_files << updated_file(
            file: yarn_lock,
            content: updated_yarn_lock_content(yarn_lock)
          )
        end

        package_locks.each do |package_lock|
          next unless package_lock_changed?(package_lock)

          updated_files << updated_file(
            file: package_lock,
            content: updated_package_lock_content(package_lock)
          )
        end

        shrinkwraps.each do |shrinkwrap|
          next unless shrinkwrap_changed?(shrinkwrap)

          updated_files << updated_file(
            file: shrinkwrap,
            content: updated_shrinkwrap_content(shrinkwrap)
          )
        end

        # Currently adding support for only pnpm with rush.
        # If the pacakge manager is yarn/npm then this needs to updated to 
        # handle those as well. Also, note that yarn/npm lock files would have
        # been modified above too! 
        if rush_config_present?

          # pnpn_shrinkwraps.each do |shrinkwrap|
          #   next unless pnpm_shrinwrap_changes?(shrinkwrap)

          # fetch the whrinkwrap file 
          pnpm_shrinkwrap_file = dependency_files.find {|f| f.name == "common/config/rush/pnpm-lock.yaml"}
          if pnpm_shrinkwrap_file
            updated_files << updated_file(
              file: pnpm_shrinkwrap_file,
              content: updated_pnpm_shrinkwrap_content(pnpm_shrinkwrap_file)
            )
          end
        end

        updated_files
      end

      def rush_config_present?
        # filtered_dependency_files.each do |f|
        #dependency_files.each do |f|
          #puts "GGB: f name is #{f.name}"
        #end

        @rush_config_present ||= dependency_files.one? {|f| f.name.end_with?("rush.json")}
      end

      def updated_pnpm_shrinkwrap_content(pnpm_shrinkwrap)
        @updated_pnpm_lock_content ||= {}
        @updated_pnpm_lock_content[pnpm_shrinkwrap.name] ||=
          pnpm_lockfile_updater.updated_pnpm_lock_content(pnpm_shrinkwrap)
      end

      def pnpm_lockfile_updater
        @pnpm_lockfile_updater ||= 
          PnpmLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          )
      end

      def updated_yarn_lock_content(yarn_lock)
        @updated_yarn_lock_content ||= {}
        @updated_yarn_lock_content[yarn_lock.name] ||=
          yarn_lockfile_updater.updated_yarn_lock_content(yarn_lock)
      end

      def yarn_lockfile_updater
        @yarn_lockfile_updater ||=
          YarnLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          )
      end

      def updated_package_lock_content(package_lock)
        @updated_package_lock_content ||= {}
        @updated_package_lock_content[package_lock.name] ||=
          npm_lockfile_updater.updated_lockfile_content(package_lock)
      end

      def updated_shrinkwrap_content(shrinkwrap)
        @updated_shrinkwrap_content ||= {}
        @updated_shrinkwrap_content[shrinkwrap.name] ||=
          npm_lockfile_updater.updated_lockfile_content(shrinkwrap)
      end

      def npm_lockfile_updater
        @npm_lockfile_updater ||=
          NpmLockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          )
      end

      def updated_package_json_content(file)
        @updated_package_json_content ||= {}
        @updated_package_json_content[file.name] ||=
          PackageJsonUpdater.new(
            package_json: file,
            dependencies: dependencies
          ).updated_package_json.content
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("npm_and_yarn", Dependabot::NpmAndYarn::FileUpdater)
