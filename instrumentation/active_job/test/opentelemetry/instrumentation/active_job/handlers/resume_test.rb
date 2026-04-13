# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

require_relative '../../../../../lib/opentelemetry/instrumentation/active_job'

require 'active_job/continuation/test_helper' if defined?(ActiveJob::Continuable)

describe OpenTelemetry::Instrumentation::ActiveJob::Handlers::Resume do
  let(:instrumentation) { OpenTelemetry::Instrumentation::ActiveJob::Instrumentation.instance }
  let(:config) { { propagation_style: :link, span_naming: :queue } }
  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }
  let(:process_spans) { spans.select { |s| s.name == 'default process' } }

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

  describe 'when a job resumes' do
    it 'adds a resume event to the process span' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }
      perform_enqueued_jobs

      resumed_process_span = process_spans.last
      resume_events = resumed_process_span.events&.select { |e| e.name == 'resume' } || []

      _(resume_events.length).must_equal 1
    end

    it 'includes resumptions count' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }
      perform_enqueued_jobs

      resumed_process_span = process_spans.last
      resume_event = resumed_process_span.events.find { |e| e.name == 'resume' }

      _(resume_event.attributes['messaging.active_job.continuation.resumptions']).must_equal 1
    end

    it 'includes description' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }
      perform_enqueued_jobs

      resumed_process_span = process_spans.last
      resume_event = resumed_process_span.events.find { |e| e.name == 'resume' }

      _(resume_event.attributes['messaging.active_job.continuation.description']).must_equal "after 'first_step'"
    end

    it 'includes completed steps' do
      ContinuableJob.perform_later
      interrupt_job_after_step(ContinuableJob, :first_step) { perform_enqueued_jobs }
      perform_enqueued_jobs

      resumed_process_span = process_spans.last
      resume_event = resumed_process_span.events.find { |e| e.name == 'resume' }

      _(resume_event.attributes['messaging.active_job.continuation.completed_steps']).must_equal 'first_step'
    end
  end

  describe 'when a job has not been interrupted' do
    it 'does not add a resume event' do
      ContinuableJob.perform_later
      perform_enqueued_jobs

      process_span = process_spans.first
      resume_events = process_span.events&.select { |e| e.name == 'resume' } || []

      _(resume_events).must_be(:empty?)
    end
  end
end
