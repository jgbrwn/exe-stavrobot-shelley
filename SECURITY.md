# Security Policy

## Reporting a vulnerability

Please report security issues privately to the project maintainers.

Include:
- affected component/script
- reproduction steps
- impact assessment
- suggested mitigation (if known)

Do not publish exploit details until maintainers confirm remediation status.

## Basic hardening guidance

- keep API keys/secrets out of git
- avoid exposing internal admin endpoints publicly without auth
- prefer least-privilege host/network setup on VM
