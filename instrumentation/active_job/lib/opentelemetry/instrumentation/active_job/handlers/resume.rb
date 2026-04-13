# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module ActiveJob
      module Handlers
        # Handles resume.active_job to record a span event on the ingress span
        # when a continuable job resumes from a previous execution
        class Resume
          def initialize(parent_span_provider)
            @parent_span_provider = parent_span_provider
          end

          # @param _name [String] of the Event (unused)
          # @param _id [String] of the event (unused)
          # @param payload [Hash] containing job run information
          def start(_name, _id, payload)
            span = @parent_span_provider.current_span
            return unless span.recording?

            job = payload.fetch(:job)

            attributes = {
              'messaging.active_job.continuation.resumptions' => job.resumptions,
              'messaging.active_job.continuation.description' => payload[:description]
            }

            attributes['messaging.active_job.continuation.completed_steps'] = payload[:completed_steps].join(',') if payload[:completed_steps]&.any?

            span.add_event('resume', attributes: attributes)
          end

          def finish(_name, _id, _payload); end
        end
      end
    end
  end
end
