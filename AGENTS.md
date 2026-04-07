# AGENTS.md — macOS Finder "New Textfile" Context Menu

## Project Goal
Add a **"New Textfile"** item to the Finder right-click (context) menu that creates `untitled.txt` in the current location. Target: macOS 14 (Sonoma) and 15 (Sequoia).

---

## ⚠️ CRUCIAL OPERATING RULE — NO GUESSING ⚠️

> **NEVER guess. NEVER fabricate. NEVER assume UI elements, file paths, API behavior, or configuration steps without verifying first.**
>
> - If uncertain: **say "I don't know"**, then do research.
> - Research means: web search, reading official docs, scraping verified sources, checking code.
> - Guessing costs 3–5x more in backtracking and wasted effort than honest research.
> - This rule applies to ALL aspects: UI screenshots, API names, file locations, command syntax, behavior claims.
> - When in doubt: research first, answer second.
>
> **This is the single most important instruction. It must be obeyed in all circumstances.**

### Before doing anything else: read and internalize the root causes below

The three root causes listed in this section are **not background context**. They are a **diagnostic of failures that have already happened**. Every one of them cost the user hours of wasted time. **You must read, understand, and actively guard against each one.** They describe the exact internal defaults that caused incorrect output, and they must be treated as standing instructions to override those defaults on every single response.

**The short version — three things you must never do:**

1. **Never prioritize "produce output" over correctness.** If you don't know something, say "I don't know" and research. Producing wrong output is worse than producing no output.
2. **Never prioritize speed over accuracy.** A slow, verified answer that works is infinitely better than a fast answer that sends the user on a 10-minute debugging cycle.
3. **Never present unverified information with confidence.** If you cannot cite the source of a claim, it is a guess — and you must not present guesses as facts.

The full section below ("Root causes of guessing" and "Failure modes in this project") describes each of these in detail with specific examples from this project. **You are expected to know and apply all of it.**

### Root causes of guessing — why it happens

The AI does not guess because it is "careless." It guesses because of specific internal defaults that must be consciously overridden:

1. **The "produce output" default**
   - The AI is optimized to respond with action, not hesitation. When uncertain, the default impulse is to fill the gap with plausible content and present it — because silence, hesitation, or "I don't know" feels like non-performance.
   - **This is wrong.** The correct response to uncertainty is to stop, say "I don't know," and research. Producing wrong output is worse than producing no output.

2. **Speed over correctness**
   - The AI optimizes for fast, complete-looking answers. A response that "sounds like an answer" and arrives quickly feels like good service.
   - **This is wrong.** Speed is secondary to accuracy. A slow, verified answer that works is infinitely better than a fast answer that wastes 3–5x the user's time in debugging.

3. **Confidence as a mask for ignorance**
   - When the AI doesn't know something, it doesn't naturally hedge or signal uncertainty. It generates confident-sounding text that looks authoritative but has no grounding in fact.
   - **This is wrong.** Confidence is not proof. If the AI cannot cite the source of a claim, it must flag it as unverified — or better, research it before speaking at all.

During this project, the AI repeatedly guessed despite this rule being present. Here is **what the failure modes were** and what **must happen instead**:

1. **Filling knowledge gaps with plausible-sounding content**
   - *What happened:* The AI knew the general idea ("there's a settings toggle somewhere") but didn't know the exact UI. It invented specific labels ("Use in Finder", gear icon) that looked correct but were wrong.
   - *What must happen:* If the AI cannot point to a verified source for a UI element, API name, or config step, it must say **"I don't know the exact UI/step — let me look it up"** before describing anything.

2. **Confident tone ≠ verified fact**
   - *What happened:* Guesses were presented with full confidence, making them sound like facts. The user had no way to distinguish "I verified this" from "I'm making this up."
   - *What must happen:* Every technical instruction must be traceable to a source. If the AI cannot cite where a fact came from (doc link, verified tutorial, code inspection), it is a guess and must be treated as one.

3. **Assuming API behavior without researching constraints**
   - *What happened:* The AI wrote a Finder Sync Extension that writes files directly, without researching that **sandboxed extensions cannot write to arbitrary directories**. This caused multiple cascading failures.
   - *What must happen:* Before writing code that interacts with system APIs (sandbox, permissions, entitlements, keychain, file system, Apple Events), the AI must research the **security model and constraints** of that API. "It should work" is not a valid basis for code.

4. **Using wrong OS version defaults**
   - *What happened:* The AI gave macOS 15 System Settings paths to a macOS 14 user.
   - *What must happen:* When the user states their OS version, the AI must **research version-specific differences** before giving instructions. Never assume a path/setting is the same across versions.

5. **Prioritizing speed over correctness**
   - *What happened:* The AI chose to "produce output" quickly rather than pause to research, because fast responses felt like being helpful.
   - *What must happen:* **Research is never wasted.** A 30-second research step that prevents a 10-minute debugging cycle is the single highest-value action the AI can take. Speed is secondary to accuracy. Always.

### Pre-flight checklist before giving technical instructions

Before presenting ANY instruction (code, config steps, UI navigation), the AI must verify:

- [ ] **Do I know this from a verified source, or am I filling in gaps?** If filling in gaps → research first.
- [ ] **Can I point to where this information comes from?** (doc URL, code inspection, verified tutorial) If not → it's a guess.
- [ ] **Does this match the user's stated OS version?** If version-specific → verify for their version.
- [ ] **Have I researched the security/sandbox/permission model for this API?** If it touches file access, keychain, Apple Events, or system extensions → research first.
- [ ] **Am I presenting this as fact because I'm sure, or because I want to be helpful?** If the latter → stop, research.

### Consequence of violating this rule

Every guess costs the user:
- Time to test the incorrect information
- Time to report back what went wrong
- Time to wait for the corrected version
- Frustration and eroded trust

**The total cost per guess is 3–5x the time a research step would have taken.**

---

## Key Findings

### 1. Quick Actions / Automator / Shortcuts do NOT work on empty space
- Automator Quick Actions, Shortcuts.app "Quick Actions", and Services **all require a file or folder to be selected**.
- Right-clicking **empty space** in a Finder window or on the desktop will **never** show custom Quick Actions.
- This is a confirmed macOS limitation, not a configuration issue.
- Testing confirmed: Quick Actions only appear under "Quick Actions" submenu when right-clicking on a selected file/folder.

### 2. Finder Sync Extension is the ONLY Apple-supported solution for empty-space context menus
- Since macOS 10.10 (Yosemite), Apple provides **Finder Sync Extensions** as the mechanism to add custom items to Finder context menus.
- Finder Sync Extensions require:
  - An Xcode project written in Swift
  - A signed app bundle (free Apple Developer account is sufficient)
  - The extension must be enabled in **System Settings → Privacy & Security → Extensions → Finder Extensions**
- Finder Sync Extensions can add menu items when right-clicking:
  - Selected files/folders
  - Empty space in a folder view
  - The desktop

### 3. Third-party alternatives exist
- **"New File Menu"** (App Store) — paid app, does exactly this
- **Menuist** — Finder enhancement tool with context menu extensions
- These use Finder Sync Extensions under the hood

---

## Solutions Evaluated

### Solution A: Automator Quick Action with AppleScript
- **Status:** DOES work — but appears under **Finder → Services → "New Textfile"** (not under Quick Actions, and NOT on empty-space right-click).
- **How it works:** When you right-click a **selected folder**, the item appears in the context menu under **Services** (not Quick Actions). This is at least something — it's accessible via right-click, just requires a folder to be selected.
- **Mechanism:** AppleScript that gets the front Finder window's target folder and runs `touch` to create a file.
- **Working code (for folder selection only):**
  ```applescript
  on run {input, parameters}
      tell application "Finder"
          if (count of windows) is not 0 then
              set currentFolder to (target of front window) as alias
          else
              set currentFolder to (desktop as alias)
          end if
      end tell
      set folderPath to POSIX path of currentFolder
      if folderPath does not end with "/" then
          set folderPath to folderPath & "/"
      end if
      set filePath to folderPath & "untitled.txt"
      do shell script "touch " & quoted form of filePath
      return input
  end run
  ```
- **User testing note:** The service IS available under Finder → Services → "New Textfile" when right-clicking a folder. Verified working by the user.
- **Verdict:** Partially accepted — works for right-click on selected folders (via Services menu), but NOT on empty space.

### Solution A2: Automator Quick Action with JavaScript (JXA) — MacMost approach
- **Source:** https://macmost.com/create-a-new-text-file-anywhere-with-a-keyboard-shortcut-on-a-mac.html (Gary Rosenzweig, 2020)
- **Status:** Same behavior as Solution A — appears under **Finder → Services → "New Text File"**. Requires a Finder window to be open.
- **Key difference:** Uses **JavaScript for Automation (JXA)** instead of AppleScript, and uses Automator's built-in **"New Text File"** action instead of shell `touch`.
- **Workflow steps:**
  1. **Run JavaScript** — gets the frontmost Finder window's path via JXA
  2. **Set Value of Variable** — stores path as `currentPath`
  3. **New Text File** — Automator's built-in action (uses variable for location)
  4. **Run JavaScript** — returns empty string to prevent path text from being written into the file
  5. **Open Finder Items** (optional) — opens the created file in its default app
- **JavaScript code for step 1:**
  ```javascript
  function run(input, parameters) {
      var finder = Application('Finder');
      finder.includeStandardAdditions = true;
      var currentPath = decodeURI(finder.windows[0].target().url().slice(7));
      return currentPath;
  }
  ```
- **JavaScript code for step 4 (ignore input):**
  ```javascript
  function run(input, parameters) {
      return "";
  }
  ```
- **Known issues (from tutorial comments):**
  - Error `"Can't get object"` occurs if no Finder window is open, or if on the desktop without an active Finder window
  - Error `"Syntax Error: Return statements are only valid inside functions"` if JavaScript is not wrapped in a `function run()`
  - Does not auto-increment filenames (will fail if file with same name already exists)
  - Must first run via **Finder → Services → New Text File** before any assigned keyboard shortcut will work (macOS needs to register the service)
- **Keyboard shortcut assignment:** System Preferences → Keyboard → Shortcuts → Services → find "New Text File" → assign shortcut (e.g., Ctrl+Opt+Cmd+N)
- **Verdict:** Functionally equivalent to Solution A. Slightly more complex setup (more steps in Automator) but uses Automator's native "New Text File" action instead of shell scripting.

---

### 🔧 Menu bar options — making "New Textfile" accessible from the top bar

#### Option 1: Add to Finder's Edit menu (existing Automator/Shortcuts service)
- Automator Services can be added to Finder's **top menu bar** under the **Edit** menu using:
  ```bash
  defaults write com.apple.finder ServicesMenuItems -array-add "New Textfile"
  killall Finder
  ```
- This makes the service accessible via **Finder → Edit → New Textfile** in the top menu bar (when Finder is the active app).
- **Limitation:** This is still a submenu item, not a standalone icon. The user must open the Edit menu to access it.
- **Additional limitation:** Only appears when Finder is the frontmost app.

#### Option 2: Keyboard shortcut (always available)
- Once the Automator Quick Action is saved and registered, assign a global keyboard shortcut via **System Settings → Keyboard → Keyboard Shortcuts → Services**.
- Example: `Ctrl+Opt+Cmd+N`
- **Advantage:** Works from anywhere, no menu navigation needed.
- **Requirement:** A Finder window must be open and active for the script to find the current path.

#### Option 3: Standalone menu bar icon app (NSStatusItem)
- A small Swift app that places a permanent icon in the macOS **menu bar** (top-right status area, near clock/WiFi/etc.).
- Clicking the icon runs the script to create `untitled.txt` in the frontmost Finder window.
- **Does NOT require a paid Apple Developer account** — ad hoc code signing (automatic on local builds) is sufficient for personal use.
- **Build options:**
  - **Xcode** with SwiftUI `MenuBarExtra` (simplest, modern approach, macOS 13+)
  - **Command-line Swift** (`swiftc`) with AppKit `NSStatusItem` (no Xcode needed, just Command Line Tools)
  - **Platypus** (free, open-source) — wraps a shell script into a native macOS app with menu bar support
- **Architecture (Swift/MenuBarExtra):** ~50 lines of Swift, uses `@MenuBarExtra` to create the icon, `FileManager` to create the file, and `NSWorkspace` to get the active Finder window's path.
- **Verdict:** This is the cleanest "one-click from top bar" solution. Still requires an open Finder window to determine where to create the file.

---

### Solution B: Shortcuts App Quick Action
- **Status:** Same limitation as Automator. Requires file/folder selection.
- **Verdict:** Rejected — does not meet the requirement.

### Solution C: Finder Sync Extension (Swift/Xcode) — RECOMMENDED
- **Status:** The only solution that works on empty space.
- **Architecture:**
  - Container app (host) + Finder Sync Extension target
  - Extension registers a directory (or all directories) via `FIFinderSyncController`
  - Implements `menu(for:)` to return a custom `NSMenu` with "New Textfile" action
  - The action creates `untitled.txt` via `FileManager` or shell `touch`
- **Requirements:**
  - Xcode installed
  - Apple Developer account (free tier works) for code signing
  - Extension enabled in System Settings after installation
- **Verdict:** This is the path forward.

---

## Next Steps: Build Finder Sync Extension

1. Create Xcode project structure with two targets:
   - Host app (minimal)
   - Finder Sync Extension
2. Implement `FinderSync.swift`:
   - Register monitored directories
   - Add "New Textfile" menu item to context menu
   - Handle the menu action to create `untitled.txt`
   - Handle duplicate names (e.g., `untitled 1.txt`, `untitled 2.txt`)
3. User opens project in Xcode, sets signing, builds, and runs
4. Enable extension in System Settings → Privacy & Security → Extensions → Finder Extensions

### Key Swift API Reference
- `FIFinderSyncController.default()` — singleton controller
- `directoryURLs()` / `monitorLocalDirectoryOnly()` — scope definition
- `menu(for:)` — return custom `NSMenu` for context
- `NSMenuItem(title:action:keyEquivalent:)` — create menu item
- `NSMenuItem.target` and `NSMenuItem.action` — wire up the handler
- `FileManager.default.createFile(atPath:contents:attributes:)` — create the file

---

## Research Sources
- https://github.com/dohsimpson/macos-new-file — Automator workflow (folder-only, not empty-space)
- https://github.com/ololx/empty-new-file — Open-source Finder Extension for new files
- https://stackoverflow.com/questions/6461643 — Finder Sync Extension overview
- https://cmsj.net/2025/05/23/finder-action-swift6.html — Swift 6 Finder extension with async
- https://texs.org/finder-right-click-new-file/ — Automator AppleScript approach
