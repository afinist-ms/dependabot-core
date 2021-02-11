# frozen_string_literal: true

require "dependabot/clients/azure"

module Dependabot
    class PullRequestUpdater
        class Azure
            attr_reader :source, :files, :base_commit, :old_commit, :credentials,
                  :pull_request_number

            def initialize(source:, base_commit:, old_commit:, files:,
                            credentials:, pull_request_number:)
                @source              = source
                @base_commit         = base_commit
                @old_commit          = old_commit
                @files               = files
                @credentials         = credentials
                @pull_request_number = pull_request_number
            end

            def update
                return unless pull_request && source_branch_name
                update_source_branch
            end

            private

            def azure_client_for_source
                @azure_client_for_source ||=
                Dependabot::Clients::Azure.for_source(
                    source: source,
                    credentials: credentials
                )
            end

            def pull_request
                @pull_request ||=
                azure_client_for_source.get_pull_request(pull_request_number)
            end

            def source_branch_name
                @source_branch_name ||=
                pull_request.fetch('sourceRefName').gsub('refs/heads/', '')
            end

            def update_source_branch
                azure_client_for_source.create_commit(
                    source_branch_name, 
                    old_commit, 
                    "Bumps dependency",
                    files,
                    nil
                )
            end

        end
    end
end

