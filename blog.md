# Your App Works on Localhost. Do You Know What Happens Next?

I've spent 25 years in infrastructure. Started as a sysadmin, moved through DevOps, now I'm in SecOps. Along the way I've worked on systems handling petabytes of data and hundreds of thousands of requests per second.

And in all that time, one thing hasn't changed: most developers have no idea how their application actually behaves in production.

I don't mean that as criticism. It's not their job to know the internals of Prometheus or wrestle with Loki configurations. They're busy writing features, fixing bugs, shipping code. But the gap between "it works on my machine" and "it works at scale" is where careers get made or broken — and where outages happen at 3 AM.

## The Pattern I Keep Seeing

A dev writes an app. It works locally. It passes CI. It gets deployed. Then, weeks later:

- "Why is the API slow?"
- "Is this endpoint even being used?"
- "What was happening when that error occurred?"
- "How much memory does this thing actually need?"

Nobody knows. There's no observability. Maybe there's some basic logging that writes to stdout and disappears into the void. Maybe someone set up metrics once but the Grafana dashboard is broken and nobody remembers the password.

So everyone's flying blind, and when something breaks, the debugging process is pure archaeology.

## Why Observability Gets Skipped

Setting up proper observability is annoying. You need:

- A metrics stack (Prometheus, exporters, maybe a pushgateway)
- A logging stack (Loki or Elasticsearch, log shippers, retention policies)
- A tracing stack (Tempo or Jaeger, instrumentation, sampling)
- Grafana to visualize all of it
- Everything wired together correctly
- Dashboards that actually show useful information

That's a lot of YAML. A lot of documentation. A lot of "I'll do it later" that turns into never.

I get it. I've set this up dozens of times and it still takes me a few hours to do it right. For someone who just wants to see if their app is healthy, the barrier is too high.

## So I Built Something

I call it **OIB — Observability in a Box**.

It's a single repo that gives you the complete Grafana LGTM stack (Loki, Grafana, Tempo, Mimir/Prometheus) configured and ready to go. Clone it, run `make install`, and you have:

- **Logs**: Loki with automatic Docker log collection
- **Metrics**: Prometheus with Node Exporter and cAdvisor (host and container metrics out of the box)
- **Traces**: Tempo with OTLP endpoints ready to receive spans
- **Dashboards**: Pre-built Grafana dashboards for system overview, logs, and traces

The whole thing runs in Docker. It's designed for local development and self-hosted environments, but the patterns scale — this is the same stack running in production at companies you've heard of.

## What You Get

After running `make install` and `make demo`, you can open Grafana and immediately see:

- CPU, memory, and disk usage for your host
- Resource consumption per container
- Log streams from all your Docker containers
- A traces explorer with example queries

More importantly, your apps can now:

- Push metrics to Prometheus or the Pushgateway
- Send traces via OTLP (gRPC on 4317, HTTP on 4318)
- Have their logs automatically collected if they're running in Docker

The repo includes working examples in Python, Node.js, Ruby, and PHP showing exactly how to instrument your code.

## Who This Is For

- **Developers** who want to understand how their app behaves without becoming observability experts
- **Self-hosters** who want proper monitoring without the enterprise complexity
- **Small teams** who need observability but don't have dedicated SRE staff
- **Anyone learning** about metrics, logs, and traces in a hands-on way

## The Real Point

Observability shouldn't be a barrier. You shouldn't need to read 50 pages of documentation just to see how much memory your app is using.

I built OIB because I was tired of watching smart people debug production issues with `print` statements and hope. The tools exist. They're free. They just need to be easier to set up.

If you've ever wondered what your app is actually doing once it leaves your laptop — give it a try.

**GitHub**: [github.com/matijazezelj/oib](https://github.com/matijazezelj/oib)

---

*Questions? Find me on reddit u/matijaz. If you build something cool with OIB, I'd love to hear about it.*
