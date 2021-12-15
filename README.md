# Setup OOB

[![Continuous Integration](https://github.com/vicariousinc/setup-oob/workflows/Continuous%20Integration/badge.svg)](https://github.com/vicariousinc/setup-oob/actions?query=workflow%3AContinuous%20Integration)

This is a utility for configuring out-of-band management systems from within
the running (Linux) OS.

It is built to be highly modular and easy to add support for new types of OOB
devices.

As of current writing it supports SuperMicro's SMC systems and Dell's iDRAC
systems.

It is specifically designed to be easy to run from a Configuration Management
system such as Chef, and thus has a 'check' mode to enable idempotent behavior.

Setup OOB attempts to do as much as possible with the generic `ipmitool`, and
falls back to vendor-specific tools only where necessary. In fact, great
lengths were taken to determine the underlying IPMI commands in order to not
rely on vendor tools.

## General Use

Note that the `--help` message is always the best place to find all the current
options. This section instead attempts to provide and overview of usage, not an
exhaustive list of all options.

You must tell Setup OOB what type of device it needs to configure with the
`--type` option. As of now it takes either `smc` or `drac`. Let's say you want
to configure an iDRAC system, you might check to see if it's configured
properly with:

```shell
setup_oob --type drac --check --name server001-oob --network-mode shared \
  --network-src dhcp
```

This would return 0 if these were all configured this way or non-zero if
something didn't match. If it was not correct, you could converge it to the
desired settings by re-running without `--check`:

```shell
setup_oob --type drac --name server001-oob --network-mode shared \
  --network-src dhcp
```

If configuring a local system, IPMI does not need a password, however for some
devices, when vendor-specific tooling is required, it may fail without
specifying the password via `--old-password` (unless it's still the device
default).

## SMC Licensing

Setup OOB can "activate" SMC systems for you. Automating this can be a bit
difficult without having to store every single license in code or have your
Configuration Management system reach out to an external database.

However, license keys can be derived from the host MAC address and a private
key. *IF YOU HAVE PURCHASED LICENSES* (and if your legal team approves), you
can find the key on the internet and pass it into `--key-file`. If you do this,
then Setup OOB can generate the license key and activate the license for you.

To be clear: *DO NOT DO THIS IF YOU HAVE NOT PURCHASED A LICENSE FOR THE
MACHINES IN QUESTION*. Doing so is certainly a violation of your agreement with
SMC.

The authors of this software are not responsible for illegal use of this
option.

## External tools

Setup OOB requires `ipmitool` at a minimum. For SMC hosts, that is the only
requirement. For DRAC hosts, it also requires racadm.
