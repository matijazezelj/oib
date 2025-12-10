<?php
/**
 * Example: Instrumented PHP Application
 * 
 * This example shows how to integrate a PHP app with all OIB stacks:
 * - Logs -> Loki (via stdout, collected by Alloy)
 * - Metrics -> Prometheus (via promphp/prometheus_client_php)
 * - Traces -> Tempo (via OpenTelemetry)
 */

require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../bootstrap/tracing.php';
require_once __DIR__ . '/../bootstrap/metrics.php';

use OpenTelemetry\API\Globals;

// Get tracer
$tracer = Globals::tracerProvider()->getTracer('example-laravel-app');

// Simple router
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

// JSON response helper
function jsonResponse(array $data, int $status = 200): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode($data);
}

// Structured log helper
function logMessage(string $level, string $message, array $context = []): void {
    $log = array_merge([
        'timestamp' => date('c'),
        'level' => $level,
        'message' => $message,
        'service' => 'example-laravel-app',
    ], $context);
    error_log(json_encode($log));
}

// Track request metrics
$startTime = microtime(true);
register_shutdown_function(function() use ($startTime, $uri, $method) {
    $duration = microtime(true) - $startTime;
    $status = http_response_code();
    recordRequestMetrics($method, $uri, $status, $duration);
});

// Routes
switch (true) {
    case $uri === '/' && $method === 'GET':
        logMessage('info', 'Home accessed', ['endpoint' => '/']);
        jsonResponse(['message' => 'Hello from OIB Example App!', 'status' => 'healthy']);
        break;

    case $uri === '/api/data' && $method === 'GET':
        $span = $tracer->spanBuilder('process_data')->startSpan();
        $scope = $span->activate();
        
        try {
            // Simulate work with random delay
            $delay = rand(50, 500) / 1000;
            usleep((int)($delay * 1000000));
            
            $span->setAttribute('delay_seconds', $delay);
            logMessage('info', 'Data processed', ['endpoint' => '/api/data', 'delay' => $delay]);
            
            jsonResponse(['data' => [1, 2, 3, 4, 5], 'processed_in' => round($delay, 3)]);
        } finally {
            $scope->detach();
            $span->end();
        }
        break;

    case $uri === '/api/error' && $method === 'GET':
        logMessage('error', 'Error triggered intentionally', ['endpoint' => '/api/error']);
        jsonResponse(['error' => 'Something went wrong!'], 500);
        break;

    case $uri === '/health' && $method === 'GET':
        jsonResponse(['status' => 'healthy', 'service' => 'example-laravel-app']);
        break;

    case $uri === '/metrics' && $method === 'GET':
        header('Content-Type: text/plain; version=0.0.4');
        echo renderMetrics();
        break;

    default:
        jsonResponse(['error' => 'Not Found'], 404);
        break;
}
