# Tsurukame Home Screen widget — wiring steps (do once, at a Mac with Xcode)

The widget code is written and committed in this folder, but it can't be activated from the CLI
because adding an **App Group** requires registering it with your Apple Developer account (interactive
Xcode auth). The app already writes the data the widget needs (`WidgetSharedData`), and calls
`WidgetCenter.reloadAllTimelines()` when it changes — so once the steps below are done, it just works.

## Steps in Xcode (`ios/Tsurukame.xcworkspace`)

1. **App Group on the app**
   - Select the **Tsurukame** target → *Signing & Capabilities* → **＋ Capability** → **App Groups**.
   - Click **＋** under App Groups and add `group.com.giorgiobrullo.tsurukame`.
   - This re-adds the entitlement and registers the group with your account.

2. **Create the widget target**
   - **File → New → Target… → Widget Extension**.
   - Product name: **`TsurukameWidget`**. Uncheck "Include Live Activity" and "Include Configuration
     App Intent". Finish → **Activate** the scheme if prompted.
   - Xcode generates a `TsurukameWidget/` group with boilerplate. **Delete the generated
     `TsurukameWidget.swift` and `Info.plist`**, then **Add Files…** and add the ones in this folder
     (`TsurukameWidget.swift`, `Info.plist`, `TsurukameWidget.entitlements`) to the new target.
   - Also add **`WidgetSharedData.swift`** (in the app's main group) to the **TsurukameWidget target
     membership** (File Inspector → Target Membership → check TsurukameWidget). It's shared by both.

3. **App Group on the widget**
   - Select the **TsurukameWidget** target → *Signing & Capabilities*.
   - Set **Team** to your team if it isn't already (the same one the app uses).
   - Point **Code Signing Entitlements** at `TsurukameWidget/TsurukameWidget.entitlements` (or add the
     **App Groups** capability and the same `group.com.giorgiobrullo.tsurukame`).

Build & run. Long-press the Home Screen → add the **Tsurukame** widget (small or medium). It shows
Level • 🔥streak • Lessons • Reviews, updating whenever you open the app (and hourly otherwise).

> Tip: if you'd rather I finish it, just confirm once the target exists and the App Group is added,
> and I'll re-enable the app-group entitlement on the app target + verify the build.
