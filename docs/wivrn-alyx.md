# WiVRn / Half-Life: Alyx compatibility (experimental)

This is the hand-tested state of the `images/wivrn` image as of September 23,
2026. It is **not** a general claim that all versions of WiVRn, Proton, Alyx,
or xrizer work together. Re-test on the actual headset after changing any of
them. See `images/wivrn/build/pins.env` for the current pins and
`images/wivrn/README.md` for the runner profile.

## Known-working path

On the GoW server, the user reached Alyx's menu, loaded a level, and played
with the following combination:

- WiVRn server 26.9, matching headset client, on the GoW Fedora 44 image.
- Alyx forced to run with Proton (the native Linux build exited at startup).
- The **xrizer PR #426 build from CI run 34992836807**, downloaded from
  `https://nightly.link/Supreeeme/xrizer/actions/runs/34992836807/xrizer-nightly-release.zip`.
  This is an unmerged, experimental upstream PR; the image pins the ZIP and
  the extracted library by SHA-256 in `pins.env`. The last successful manual
  test used the extracted runtime under `/home/retro/xrizer-hla/xrizer`.
- Alyx-only Steam launch option in the tested container:
  `VR_OVERRIDE=/home/retro/xrizer-hla/xrizer %command%`.
- **Headset hand tracking disabled** in the WiVRn headset app, with physical
  controllers awake *before* connecting. With hand tracking enabled the user
  lost controllers in-game and subsequently saw `ERROR_SESSION_LOST`.

Commit `80627c3` packages the **identical, checksum-verified `vrclient.so`** at
`/usr/lib64/xrizer/runtime/bin/linux64/vrclient.so`. In the new image, the
equivalent Alyx-only launch option is
`VR_OVERRIDE=/run/host/usr/lib64/xrizer/runtime %command%` (Steam's Pressure
Vessel exposes host `/usr` under `/run/host/usr`). **The image-packaged path
still needs a headset test** after CI builds and the server pulls the new image;
only the home-directory path above has been played in-game so far. Keep the
image's global OpenComposite default: VRChat was confirmed working with it.
Do not change `WIVRN_OPENVR_COMPAT_PATH` globally to xrizer merely for Alyx.

## How we got here (failures that distinguish the layers)

1. VRChat initially launched on the desktop with no HMD image or tracking.
   Fedora's OpenComposite runtime is nested at
   `/usr/lib64/opencomposite/runtime/bin/linux64/vrclient.so`, and games inside
   Pressure Vessel need the `/run/host/usr/...` prefix. With the corrected
   default and `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1`, VRChat worked.
2. Alyx did not appear in the headset launcher despite being in Steam's
   `steamapps.vrmanifest`. WiVRn 26.9 selects the **first existing** Steam
   root (`~/.steam/debian-installation` before `~/.local/share/Steam`); on this
   server the former lacked the manifest. Commit `7bf6674` links the manifest
   into that first root when missing. Alyx and Tabletop Simulator now appear.
   Their **missing icons remain unresolved**; WiVRn reads icon metadata from
   the selected root's `appcache/appinfo.vdf` and `steam/games/`, which the
   manifest-only link does not populate. Verify those paths before changing
   icon discovery. Source: [WiVRn 26.9 Steam discovery code][steam-info].
3. Proton Experimental 11, GE 11.7 and 9.0-4 with Fedora OpenComposite
   produced `OpenComposite DLLMain ERROR: unknown/unsupported interface
   IVRSystem_026`. The first Proton log also contained an enormous repeated
   Wine fault trace (17 GB). Do not enable `PROTON_LOG=1` by default; remove
   it after collecting a bounded excerpt. Changing Proton alone did not fix
   this user's OpenComposite failure.
4. An XR SIG Fedora xrizer RPM built from commit `0989a7f` implements
   `IVRSystem_026`, but Alyx panicked at `src/system.rs:872:9`, the
   unimplemented `GetDXGIOutputInfo`. Merely checking for the interface
   string in the library cannot prove game compatibility.
5. [xrizer PR #426][alyx-pr] explicitly addresses the new Alyx release by
   responding to `GetDXGIOutputInfo` and `GetD3D9AdapterIndex`. A pinned
   artifact from its successful CI run 34992836807 passed the user's test up
   through in-game play when hand tracking was off. Another tester reported
   success on that PR. This PR is not merged as of this note.
6. When hand tracking was enabled, xrizer logged
   `src/compositor.rs:1178:32: ... ERROR_SESSION_LOST` after controller loss.
   That line is `wait_frame().unwrap()` after an OpenXR session was lost;
   the log alone does **not** establish why the session stopped. In the later
   successful run, xrizer reported both controllers as
   `/interaction_profiles/meta/touch_controller_plus`. After several minutes
   it logged `STOPPING`, then an `ERROR_SESSION_LOST` panic ten seconds later;
   whether that final panic was caused by ending the session was not checked.

## Updating or replacing the experimental artifact

The tested artifact is a GitHub Actions artifact accessed via nightly.link;
it can expire or disappear. A future agent should replace the pin rather than
silently falling back to the older XR SIG RPM or the xrizer v0.5 release (v0.5
lacks `IVRSystem_026`). For a new candidate:

1. Check the upstream [Alyx PR][alyx-pr] and xrizer release history for a
   merged/released equivalent, plus any fixes for session loss and controller
   interaction profiles. Record the exact commit or release and build source.
2. Verify the download's SHA-256 and its `bin/linux64/vrclient.so` SHA-256;
   update **all three** `XRIZER_*` pins in `images/wivrn/build/pins.env`.
   `images/wivrn/build/Dockerfile` extracts only that library and verifies both
   hashes; `images/wivrn/tests/smoke-wivrn-runtime.sh` checks the installed
   hash. The WiVRn updater scripts only update WiVRn itself, **not xrizer**.
3. Run `./tests/policy-check.sh` and, with Docker available, build the image
   and run `IMAGE_NAME=... images/wivrn/tests/run-smoke.sh`. Those checks do
   **not** exercise Alyx or the headset; compare with an Alyx launch and a
   VRChat launch on real hardware before changing the default translator.
4. Keep hand-tracking state, selected Proton version, Steam launch options,
   and headset/client versions in any new test report. Change one variable at
   a time. If xrizer crashes, its focused log is at
   `~/.local/state/xrizer/xrizer.txt`; inspect the **first** error, not only
   the final panic. A panic on `ERROR_SESSION_LOST` may follow another cause.

## Relevant upstream references

- [WiVRn v26.9 Steam / Pressure Vessel guide][wivrn-steam]. WiVRn is the
  OpenXR streaming runtime; xrizer and OpenComposite translate OpenVR calls.
- [WiVRn 26.9 Steam discovery][steam-info].
- [xrizer PR #426: new Alyx release][alyx-pr] and its [successful artifact
  build][artifact-run]. The packaged image pins this build, not the original
  XR SIG RPM.
- [xrizer session-loss report #425][session-loss]. This describes a similar
  `ERROR_SESSION_LOST` unwrap; it does not prove the cause of this user's
  controller loss.

[wivrn-steam]: https://github.com/WiVRn/WiVRn/blob/v26.9/docs/steamvr.md
[steam-info]: https://github.com/WiVRn/WiVRn/blob/v26.9/common/utils/steam_info.cpp
[alyx-pr]: https://github.com/Supreeeme/xrizer/pull/426
[artifact-run]: https://github.com/Supreeeme/xrizer/actions/runs/34992836807
[session-loss]: https://github.com/Supreeeme/xrizer/issues/425
