<?php
/**
 * OpenTelemetry Tracing Bootstrap
 * 
 * Initializes OpenTelemetry SDK with OTLP HTTP exporter
 */

use OpenTelemetry\API\Globals;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\SemConv\ResourceAttributes;

$otelEndpoint = getenv('OTEL_EXPORTER_OTLP_ENDPOINT') ?: 'http://localhost:4318';
$serviceName = getenv('OTEL_SERVICE_NAME') ?: 'example-laravel-app';

// Create resource with service name
$resource = ResourceInfoFactory::defaultResource()->merge(
    ResourceInfo::create(Attributes::create([
        ResourceAttributes::SERVICE_NAME => $serviceName,
    ]))
);

// Create OTLP HTTP exporter
$transport = (new OtlpHttpTransportFactory())->create(
    $otelEndpoint . '/v1/traces',
    'application/json'
);
$exporter = new SpanExporter($transport);

// Create tracer provider
$tracerProvider = TracerProvider::builder()
    ->addSpanProcessor(new BatchSpanProcessor($exporter))
    ->setResource($resource)
    ->build();

// Register globally
Globals::registerInitializer(function() use ($tracerProvider) {
    return $tracerProvider;
});

error_log(json_encode([
    'timestamp' => date('c'),
    'level' => 'info',
    'message' => '[tracing] OpenTelemetry initialized',
    'endpoint' => $otelEndpoint,
    'service' => $serviceName,
]));
