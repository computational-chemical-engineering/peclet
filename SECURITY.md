# Security Policy

## Supported versions

peclet is pre-1.0 research software; security fixes are applied to the latest release on `main`.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅         |
| < 0.1   | ❌         |

## Reporting a vulnerability

Please report suspected vulnerabilities **privately** — do not open a public issue for a security problem.

- Preferred: use GitHub's **[Report a vulnerability](https://github.com/computational-chemical-engineering/peclet/security/advisories/new)**
  (Security → Advisories) on the relevant repository, or
- email **e.a.j.f.peters@gmail.com** with a description and a minimal reproducer.

Please allow a reasonable time for a fix before public disclosure. As scientific-computing software with no
network-facing services, the most likely issues are memory-safety bugs reachable from crafted inputs
(e.g. SDF/VTI files); include the input and environment in your report.
