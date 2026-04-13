# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module ActiveJob
      module Handlers
        # Handles step_skipped.active_job to record a span event on the ingress span
        # when a previously completed step is skipped during a resumed job execution
        class StepSkipped
          def initialize(parent_span_provider)
            @parent_span_provider = parent_span_provider
          end

          # @param _name [String] of the Event (unused)
          # @param _id [String] of the event (unused)
          # @param payload [Hash] containing job run information
          def start(_name, _id, payload)
            span = @parent_span_provider.current_span
            return unless span.recording?

            span.add_event('step_skipped', attributes: {
                             'messaging.active_job.step.name' => payload[:step].to_s
                           })
          end

          def finish(_name, _id, _payload); end
        end
      end
    end
  end
end
