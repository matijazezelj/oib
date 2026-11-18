Mounted at /etc/prometheus/scrape in restricted mode (OIB_MODE=restricted)
instead of ../scrape, so Prometheus does not scrape cAdvisor, which restricted
mode does not run. Put scrape jobs you want in restricted mode here as *.yml
files with a top-level `scrape_configs:` list.
