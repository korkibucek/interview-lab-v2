# Roadmap

Current state: a working, validated single-host AlmaLinux 10 lab with six
layered faults, idempotent deploy/reset/uninstall, and pre/post validation.

## Possible future enhancements

- **Difficulty tiers.** An `easy/standard/hard` flag to enable/disable specific
  faults or remove the second layer of A and B.
- **Fault randomisation.** Vary which faults are active so repeat candidates
  can't share answers.
- **More scenarios.** Additional independent fault packs (e.g. a failing timer,
  a permissions cascade, a full inode table) selectable at install.
- **Time tracking.** Optional timestamping in `validate-fixed.sh` to record how
  long each objective took.
- **SELinux hard mode.** Turn an SELinux denial (currently set permissive) into
  an intended objective for senior candidates.
- **Terraform module.** Codify the DigitalOcean droplet + cloud firewall so the
  whole environment is one `terraform apply` / `destroy`.
- **Report export.** Have `validate-fixed.sh` emit a JSON/Markdown scorecard for
  the assessor's records.
- **Candidate sandboxing.** Optionally constrain `sudo` to the commands needed,
  for tighter control on shared infrastructure.

## Explicit non-goals

- Multi-node / cluster scenarios.
- Supporting OS families beyond AlmaLinux 10.
- Anything resembling real malware, persistence, or data exfiltration.
