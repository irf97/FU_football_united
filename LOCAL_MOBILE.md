# Open Spontaan on your phone

This runs the full Phoenix/PostgreSQL hobby platform on your computer. Your
phone uses its mobile interface over the same private Wi-Fi/network. The
computer and Docker Desktop stay on while you use it. It is a local mobile web
app; it does not install an Android APK or provision a hosted service.

## Windows

1. Install and open [Docker Desktop](https://www.docker.com/products/docker-desktop/).
   Use Linux containers and wait until the engine is ready.
2. Extract this source folder and double-click **Start_Spontaan.cmd**.
   The first start builds the app; later starts reuse the downloaded layers.
3. Open the printed **OPEN ON YOUR PHONE** address in Chrome on your phone.
   Both devices must be on the same network. If Windows asks, allow Docker
   access on your private network.
4. Sign in as **Ari: +31680000601**. Press **Send code**, read the local code
   displayed on the phone, and verify it. No real SMS account or message is used.

No Elixir, Node or PostgreSQL installation is needed on your computer. Docker
runs the app and its isolated database. The launcher generates and retains its
own cookie secret and database password in `fu/.env.local-mobile`; keep that file
with this workspace.

The app opens Explore. Try “I want to play ping pong”, join or create an activity,
change your main hobby/theme, open Equipment or use an event's organizer and
referee controls. Commons supplies twelve fictional identities, six activities,
equipment and scoreboards. Existing session timing, membership and role checks
apply. The local code signs into a chosen fictional identity; it proves no
ownership of a real phone number.

## Stop, restart and choose an address

Double-click the launcher again to restart. Stopping preserves the database:

```powershell
.\fu\local-mobile.ps1 -Action Stop
```

Use `-Action Status` or `-Action Logs` for diagnostics. If automatic address
selection chooses the wrong interface, supply your computer's private IPv4:

```powershell
.\fu\local-mobile.ps1 -HostIP 192.168.1.25 -Port 4000
```

Use the actual address printed by the launcher, not this example and not
`localhost` on the phone. Guest Wi-Fi/client isolation can prevent devices from
reaching each other. The launcher binds only the selected address and exports
no database port. Do not forward its HTTP port onto the public internet.

The seed is additive: reopening does not reset edits, invent fresh observations
or move old events into the future. After the initial events' time window,
create a fresh activity; previous activity remains in My events.

## Build boundary

`Dockerfile.local-mobile` is a separate development build with prebuilt assets,
no source reload/debug console, no default admin password, explicit WebSocket
origins and local-only login codes. It accepts only an isolated database and
private/loopback host settings. The normal production image rejects
`FU_LOCAL_MOBILE=1`; its OTP delivery and production boundaries stay separate.
This workspace sends no provider requests and includes no physical BLE scanner.

The launcher's execution-policy setting applies only to its child PowerShell
process. It does not change the computer's saved execution policy.
