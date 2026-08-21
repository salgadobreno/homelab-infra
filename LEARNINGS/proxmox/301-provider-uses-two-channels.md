# The bpg provider talks over two channels, not one

`[hit]` · 2026-08-20

The API token is enough for almost everything, but **snippet uploads go over SSH** —
PVE exposes no API endpoint for them. This surfaced as a confusing "unable to
authenticate user" error at apply time, long after the token had been proven working.

Fundamental: a Terraform provider's credentials are not necessarily one thing. Worth
asking of any provider: what does it need, and for which operations?
