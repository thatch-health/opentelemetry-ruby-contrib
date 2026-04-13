# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

require_relative '../../../../../lib/opentelemetry/instrumentation/active_job'

require 'active_job/continuation/test_helper' if defined?(ActiveJob::Continuable)

describe OpenTelemetry::Instrumentation::ActiveJob::Handlers::Interrupt do
  let(:instrumentation) { OpenTelemetry::Instrumentation::ActiveJob::Instrumentation.instance }
  let(:config) { { propagation_style: :link, span_naming: :queue } }
  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }
  let(:process_span) { spans.find { |s| s.name == 'default process' } }

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

  describe 'when a job is interrupted between steps' do
    it 'adds an interrupt event to the process span' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }

      interrupt_events = process_span.events&.select { |e| e.name == 'interrupt' } || []

      _(interrupt_events.length).must_equal 1
    end

    it 'includes the interrupt reason' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }

      interrupt_event = process_span.events.find { |e| e.name == 'interrupt' }

      _(interrupt_event.attributes['messaging.active_job.continuation.reason']).must_equal 'stopping'
    end

    it 'includes the description' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }

      interrupt_event = process_span.events.find { |e| e.name == 'interrupt' }

      _(interrupt_event.attributes['messaging.active_job.continuation.description']).wont_be_nil
    end

    it 'includes completed steps' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }

      interrupt_event = process_span.events.find { |e| e.name == 'interrupt' }

      _(interrupt_event.attributes['messaging.active_job.continuation.completed_steps']).must_equal 'first_step'
    end
  end

  describe 'when a job is interrupted during a step' do
    it 'adds an interrupt event to the process span, not the step span' do
      ContinuableWithCursorJob.perform_later
      interrupt_job_during_step(ContinuableWithCursorJob, :process_items, cursor: 2) { perform_enqueued_jobs }

      step_span = spans.find { |s| s.name == 'default process_items' }
      step_interrupt_events = step_span&.events&.select { |e| e.name == 'interrupt' } || []
      process_interrupt_events = process_span.events&.select { |e| e.name == 'interrupt' } || []

      _(step_interrupt_events).must_be(:empty?)
      _(process_interrupt_events.length).must_equal 1
    end
  end

  describe 'when a job completes without interruption' do
    it 'does not add an interrupt event' do
      ContinuableJob.perform_later
      perform_enqueued_jobs

      interrupt_events = process_span.events&.select { |e| e.name == 'interrupt' } || []
      _(interrupt_events).must_be(:empty?)
    end
  end
end
