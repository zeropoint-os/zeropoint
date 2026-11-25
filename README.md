# ZeroPoint OS

ZeroPoint is a ready-to-boot, immutable, container-first OS that runs from USB and manages devcontainer-based applications across one or more machines.

## x86_64 image

The AMD64 image is assembled with the repository's existing pimod pipeline. It includes a physical-hardware Debian kernel, DHCP networking, SSH, Docker, Terraform, hardware-discovery utilities, and the checksum-verified ZeroPoint Agent `v2.0.0` release wheel. No Web UI is included.

The agent runs in live mode as a systemd service. Its API listens on TCP port 2370 and its xDS endpoint listens on TCP port 18000 on all interfaces. It advertises `_zeropoint-agent._tcp.local` with a persistent per-machine identity, exposes fleet metadata at `GET /api/meta`, and serves the canonical graph at `GET /api/graph`. These endpoints are unauthenticated and intended only for a trusted LAN.

Persistent state is rooted at `/var/lib/zeropoint`:

- SQLite graph: `/var/lib/zeropoint/data/state.db`
- Agent execution state: `/var/lib/zeropoint/data/modules`
- Module data: `/var/lib/zeropoint/modules`
- Logs: `/var/lib/zeropoint/logs`

On first start, `zeropoint-init-agent` migrates the SQLite schema and the live agent seeds the canonical settings, modules, system, reboot, and hardware root nodes. Hardware roots resolve immediately and continue refreshing from udev events and the periodic monitor. Existing graph data is preserved on later boots.

## Build

Run the build inside the repository devcontainer:

```bash
./build-image.sh
```

The build downloads the `v2.0.0` universal wheel from the GitHub release and verifies its pinned SHA-256 before invoking pimod. Override `ZEROPOINT_AGENT_VERSION`, `ZEROPOINT_AGENT_RELEASE_URL`, or `ZEROPOINT_AGENT_SHA256` only when intentionally testing another immutable release artifact.

## Write and boot

Write the resulting `.img` file to a USB drive or other boot device. Confirm the target device carefully because this destroys its existing contents:

```bash
sudo dd if=/absolute/path/to/image.img of=/dev/sdX bs=16M status=progress conv=fsync
sync
```

Boot the target x86_64 machine in UEFI mode. The root filesystem expands on first boot, wired interfaces request DHCP, and `zeropoint-agent.service` starts after persistent storage and Docker are ready. Check readiness locally with:

```bash
systemctl status zeropoint-agent
curl http://127.0.0.1:2370/api/health
```
