# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

require_relative '../../../../../lib/opentelemetry/instrumentation/active_job'

require 'active_job/continuation/test_helper' if defined?(ActiveJob::Continuable)

describe OpenTelemetry::Instrumentation::ActiveJob::Handlers::StepSkipped do
  let(:instrumentation) { OpenTelemetry::Instrumentation::ActiveJob::Instrumentation.instance }
  let(:config) { { propagation_style: :link, span_naming: :queue } }
  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }

  before do
    skip 'Requires ActiveJob::Continuable (Rails 8.1+)' unless defined?(ActiveJob::Continuable)

    singleton_class.include ActiveJob::Continuation::TestHelper

    OpenTelemetry::Instrumentation::ActiveJob::Handlers.unsubscribe
    instrumentation.instance_variable_set(:@config, config)
    instrumentation.instance_variable_set(:@installed, false)

    instrumentation.install(config)
    ActiveJob::Base.queue_adapter = :test

    exporter.reset
  end

  after do
    ActiveJob::Base.queue_adapter = :inline
  end

  describe 'when a step is skipped on resume' do
    it 'adds a step_skipped event to the process span' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }
      exporter.reset
      perform_enqueued_jobs

      process_span = spans.find { |s| s.name == 'default process' }
      skipped_events = process_span.events&.select { |e| e.name == 'step_skipped' } || []

      _(skipped_events.length).must_equal 1
    end

    it 'includes the step name' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }
      exporter.reset
      perform_enqueued_jobs

      process_span = spans.find { |s| s.name == 'default process' }
      skipped_event = process_span.events.find { |e| e.name == 'step_skipped' }

      _(skipped_event.attributes['messaging.active_job.step.name']).must_equal 'first_step'
    end
  end

  describe 'when no steps are skipped' do
    it 'does not add a step_skipped event' do
      ContinuableJob.perform_later
      perform_enqueued_jobs

      process_span = spans.find { |s| s.name == 'default process' }
      skipped_events = process_span.events&.select { |e| e.name == 'step_skipped' } || []

      _(skipped_events).must_be(:empty?)
    end
  end
end
