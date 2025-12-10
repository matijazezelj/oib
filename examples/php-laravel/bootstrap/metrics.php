<?php
/**
 * Prometheus Metrics Bootstrap
 * 
 * Simple in-memory metrics for demonstration
 * For production, use Redis or APCu storage
 */

// Simple in-memory counters (reset on each request in PHP)
// For real apps, use promphp/prometheus_client_php with Redis/APCu backend

$GLOBALS['metrics'] = [
    'requests_total' => [],
    'request_duration' => [],
];

/**
 * Record request metrics
 */
function recordRequestMetrics(string $method, string $path, int $status, float $duration): void {
    $key = "{$method}|{$path}|{$status}";
    
    if (!isset($GLOBALS['metrics']['requests_total'][$key])) {
        $GLOBALS['metrics']['requests_total'][$key] = 0;
    }
    $GLOBALS['metrics']['requests_total'][$key]++;
    
    if (!isset($GLOBALS['metrics']['request_duration'][$key])) {
        $GLOBALS['metrics']['request_duration'][$key] = ['sum' => 0, 'count' => 0];
    }
    $GLOBALS['metrics']['request_duration'][$key]['sum'] += $duration;
    $GLOBALS['metrics']['request_duration'][$key]['count']++;
}

/**
 * Render metrics in Prometheus format
 */
function renderMetrics(): string {
    $output = [];
    
    // Request counter
    $output[] = "# HELP http_requests_total Total number of HTTP requests";
    $output[] = "# TYPE http_requests_total counter";
    foreach ($GLOBALS['metrics']['requests_total'] as $key => $count) {
        [$method, $path, $status] = explode('|', $key);
        $output[] = "http_requests_total{method=\"{$method}\",path=\"{$path}\",status=\"{$status}\"} {$count}";
    }
    
    // Request duration histogram (simplified)
    $output[] = "";
    $output[] = "# HELP http_request_duration_seconds Duration of HTTP requests";
    $output[] = "# TYPE http_request_duration_seconds summary";
    foreach ($GLOBALS['metrics']['request_duration'] as $key => $data) {
        [$method, $path, $status] = explode('|', $key);
        $output[] = "http_request_duration_seconds_sum{method=\"{$method}\",path=\"{$path}\"} {$data['sum']}";
        $output[] = "http_request_duration_seconds_count{method=\"{$method}\",path=\"{$path}\"} {$data['count']}";
    }
    
    // Basic PHP info
    $output[] = "";
    $output[] = "# HELP php_info PHP version info";
    $output[] = "# TYPE php_info gauge";
    $output[] = "php_info{version=\"" . PHP_VERSION . "\"} 1";
    
    return implode("\n", $output) . "\n";
}

error_log(json_encode([
    'timestamp' => date('c'),
    'level' => 'info',
    'message' => '[metrics] Prometheus metrics initialized',
    'service' => 'example-php-app',
]));
