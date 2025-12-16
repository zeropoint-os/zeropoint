# zeropoint-os
A ready-to-boot, immutable, container-first OS that runs from USB and manages devcontainer-based apps across one or more machines

## Introduction

Growing mistrust of centralized services, opaque platforms, user exploitation, price gouging, and subscription-based lock-in is driving a renewed interest in self-hosted services. This shift is clearly visible in the rapid growth of homelabs and the massive popularity of self-hosting content among technically capable users. 

However, this space remains inaccessible to many: most available software is still designed for public cloud environments and professional DevOps teams, adding a high bar of entry to what should be easily accessible in this day and age.

Zeropoint proposes a simpler model: an immutable, USB-bootable, container-first homelab appliance OS. It is designed to feel like an appliance:

1. Plug in a USB drive containing Zeropoint
2. Power it on
3. Use the Zeropoint API/app to connect to one or more Zeropoint nodes
4. Install, remove, or manage services from a publicly curated set of open-source AI services, applications, and utilities

Zeropoint aims to make it trivial to stand up a personal infrastructure appliance spanning one or more nodes, capable of running AI workloads, private services, and self-owned alternatives to cloud platforms with minimal setup, predictable behavior, and easy recovery.

The system emphasizes trust, transparency, determinism, portability, and developer ergonomics over generality or scale.                                                                                        