# TabletSweeper

**TabletSweeper** helps you find tablets by keeping track of which areas of a zone you've already walked through.

As you move around, the map gradually clears to show the areas you've covered. This makes it much easier to see where you still need to search and helps prevent accidentally missing a tablet just outside an area you thought you'd already checked.

## Installation

1. Download the **TabletSweeper** addon.

2. Place the `TabletSweeper` folder inside your Windower `addons` folder.

   Your folder should look like this:

   `Windower4/addons/TabletSweeper/`

3. In FFXI, load the addon with:

   `//lua load tabletsweeper`

That's it. **No setup or configuration is required.**

TabletSweeper already includes everything it needs for all 29 supported tablet zones.

## Using TabletSweeper

The map will automatically appear when you enter a supported zone and disappear when you leave one.

| Button                 | What it does                              |
| ---------------------- | ----------------------------------------- |
| **− / +**              | Zoom the map out or in                    |
| **Reset**              | Erases your progress for the current zone |
| **Pause**              | Temporarily stops tracking your movement  |
| **−** in the title bar | Minimises the window                      |
| **+** in the title bar | Restores the window                       |

You can also:

* **Drag the title bar** to move the window.
* **Scroll the mouse wheel over the map** to zoom in or out.

## Commands

The only command is to clear all maps. Type the following to do this:

   `//tablet resetall`

## Your Progress Is Saved

Your progress is saved automatically as you explore.

Progress is saved **separately for each character and each zone**, and will remain after:

* Zoning
* Logging out and back in
* Reloading Windower
* Reloading the addon

Your progress will only be removed when you press **Reset**.

**Reset only affects the zone you are currently in.**