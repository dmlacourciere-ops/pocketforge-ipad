# Try the browser build on your iPad

This is the compiled **browser version**, separate from the native iOS installer.

1. Extract `PocketForge-Browser-Windows.zip` on your Windows PC.
2. Double-click **Start-PocketForge.cmd**. This PC already has Python; the launcher uses it to serve the compiled app files.
3. Connect the iPad and PC to the same home network. Open the address printed by the launcher in **Safari on the iPad**.
4. Press **Run project** to try Neon Drift. Open **Model settings** and enter your DeepSeek API key there to try the agent. Do not share the key in chat.

The agent loop, project editing, game preview and test execution run in the iPad browser. DeepSeek provides remote model inference. Windows only serves the static app bundle; keep its window open for loading/reloading. Projects use browser storage; the API key must be entered again after reopening. Browser screenshots are unsupported.

The browser build has been checked in desktop Chrome and WebKit, including portrait layout, actual failed/passing game assertions, project persistence, and session-only key behavior. Physical iPad behavior and a live DeepSeek run still need verification.

If Safari cannot connect, confirm both devices are on the same network and the launcher is still running. Guest Wi-Fi can block device-to-device traffic. The launcher does not change Windows firewall settings or configure your router. Do not set up internet port forwarding for this local test.

This route needs the Windows static-file server for delivery. The intended native app will bundle these assets and still needs a successful Apple build, signing and device testing.
