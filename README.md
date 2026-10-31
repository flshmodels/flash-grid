# Flash Grid

Snap selected part centers to a world grid, with a preview and one undo step.

## Install

1. Download this repository as a ZIP and extract it. No package installation is needed to use the plugin.
2. Open a separate Studio test place in edit mode. Use Explorer's **Insert from File** action to insert `FlashGrid.rbxmx`.
3. The imported root is a Script named `FlashGrid` with four child ModuleScripts. Select that root and choose **Save as Local Plugin**.
4. Remove the imported root from the place after saving the plugin. Open **Flash Grid → Snap** on the Plugins toolbar.

Changes happen only after Preview and Apply. Selection or option edits clear the preview. Apply is refused during a play test. A successful batch uses one Studio undo recording. If a write fails, the plugin asks Studio to cancel the batch. Start on a copy of your place and verify Undo and Redo before using it on important work.

## Use it

Select loose, anchored BaseParts in Workspace. Enter a grid size, such as `0.5`, and the axes to change, such as `XZ`. Click **Preview selection**, review the positions, then **Apply preview**.

For example, `(0.4, 2.2, -0.5)` with a 1-stud XZ grid becomes `(0, 2.2, -1)`. Halfway values round away from zero. The origin is `(0, 0, 0)`; this version has no custom or local grid.

Rotation and size are preserved. Each selected part moves independently. The preview is a text list, not ghost geometry in the viewport.

## Limits

- Select 1–500 parts, not Models or folders. Descendants are not expanded.
- Grid size: 0.01–1024 studs. Coordinates must be finite and within one million studs of the origin.
- Locked, unanchored or rigidly connected parts are refused. Constraint-driven mechanisms are outside this tool's scope; use loose scenery parts.
- This snaps centers, not edges, surfaces or vertices. It does not check collisions, resize parts, edit terrain or preserve model spacing.
- A moved, removed, reparented, locked or newly connected target requires another preview.

## Code

`Rules.plan(rows, options)` takes position records and `{step, axes}` and returns only changed positions. `Adapter.plan(selection, options)` reads Studio instances and builds those records. `Adapter.write(entry)` translates the captured CFrame without changing its rotation. Nothing is written during planning.

## Development and tests

The source is in `src`. There are no runtime dependencies, network requests or external assets. `Ui` creates a dock panel using Studio's theme. `Transaction` handles preflight checks and undo recordings; it does not create its own undo stack. These two modules are shared with the other Flash editing plugins, with a copy in each repository so each plugin can be installed on its own.

Rebuild after changing source (Python 3.11+):

```sh
python build.py
python -m unittest discover -s tests -v
```

Rule, adapter and transaction checks use Lune 0.11.1:

```sh
lune run tests/run
```

The tests compile every source file, exercise the real planner and adapter with fake Studio objects, and check commit/cancel behavior with a fake history service. Packaging tests compare the XML plugin against its source. GitHub Actions runs both sets of checks. The CI job installs Lune on its runner, not on your computer.

**Automated tests do not verify the dock widget, plugin installation, real constraints or Studio's undo engine.** See [Studio checks](docs/STUDIO-CHECKS.md) for the manual checklist. No live Studio pass is claimed here.

See Roblox's [plugin guide](https://create.roblox.com/docs/studio/plugins) and [ChangeHistoryService reference](https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService). MIT licensed; see [LICENSE](LICENSE).
