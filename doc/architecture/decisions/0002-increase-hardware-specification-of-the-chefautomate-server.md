<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [2. Increase hardware specification of the chefautomate server](#2-increase-hardware-specification-of-the-chefautomate-server)
  - [Status](#status)
  - [Context](#context)
  - [Decision](#decision)
  - [Consequences](#consequences)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# 2. Increase hardware specification of the chefautomate server

Date: 2018-06-15

## Status

Accepted

## Context

Since the creation of this template, the hardware requirments on the chefautomate server have increased to a minimum of 16Gb RAM and of >=80Gb free on /var.  The current ARM template did not meet these requirements and as a result the "automate-ctl preflight-check" was failing.

## Decision

Therefore, it was decided to increase the Azure VM size from Standard_F4s (with 8Gb RAM) to Standard_DS4_v2 (with 16Gb RAM) and the OS disk size from 30Gb to 100Gb.

## Consequences

Consequently, the automate-ctl preflight-check is passing and the server is ready by default for the setup of the automate server.
