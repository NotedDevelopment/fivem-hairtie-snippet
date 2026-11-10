# fivem hairtie snippet

A single client file that adds `/hairtie`. It lets players tie their hair up when they wear a hat, a mask, or all the time, and lets it back down when they take them off.

## Requirements

- [Qbox](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)

## Install

Drop `client.lua` into one of your resources and load it after ox_lib and the Qbox player data module:

```lua
shared_script '@ox_lib/init.lua'

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client.lua',
}
```

## Config

The config sits at the top of `client.lua`.

| Key | What it does |
| --- | --- |
| `command` | The command name, `hairtie` by default |
| `duration` | How long the progress bar takes, in ms |
| `anim` | The progress bar animation (`clothingtie` / `check_out_a`, upper body) |
| `checkLoop` | Re-checks the hair every second, skipping while a NUI has focus. `false` by default. See [Hats and masks can come off at any time](#hats-and-masks-can-come-off-at-any-time). |
| `hair` | The tied-up hairstyle for each ped model. Defaults are drawable 7 for `mp_m_freemode_01` and 4 for `mp_f_freemode_01`. Check these against your server's hair list, especially if you stream addon hair. |

Peds whose model isn't in `hair` can't use the hair tie.

## How it works

`/hairtie` opens an ox_lib dialog with three checkboxes:

- When wearing a hat
- When wearing a mask
- All the time

Tick hat and mask together to tie it up for either. The choices are saved per character in a resource KVP (`hairtie:<citizenid>`), so they stay between sessions. Unticking everything deletes the KVP.

A progress bar and hair tie animation play when the hair tie goes from off to on, or on to off. Changing options while it's already on just saves them.

The hairstyle a player had before it got tied up is kept in memory on the client, not in the KVP. If a player saves their appearance in a clothing store while their hair is tied, the tied hairstyle becomes their saved hair, so there's nothing to switch back to after a relog.

The hair gets checked automatically when the ped changes (ox_lib's `cache.ped`), when the player loads in, and when the resource starts. Anything else that puts on or takes off a hat or mask has to call the export, unless `checkLoop` is on.

## Export

```lua
exports.your_resource:checkHairTie()
```

Swap `your_resource` for the resource you put `client.lua` in. It checks the player's ped and their saved choices, then ties the hair up or lets it back down. If nothing needs to change it does nothing, so it's safe to call as often as you like. It doesn't yield, and doesn't play the progress bar.

Call it right after your scripts change a hat (prop 0) or mask (component 1).

### Hats and masks can come off at any time

Hats get knocked off when ragdolling, falling or getting hit, and other scripts can change hats and masks without calling the export. If that can happen on your server, set `checkLoop = true` in the config. It starts this thread:

```lua
CreateThread(function()
    while true do
        Wait(1000)
        if not IsNuiFocused() then
            update(cache.ped)
        end
    end
end)
```

`update(cache.ped)` is the same check the export runs.

The `IsNuiFocused()` check stops it from swapping hair while someone is in a clothing menu like illenium-appearance, picking out a hat or hairstyle. The illenium menu takes NUI focus while it's open, so this covers it. It also pauses while the inventory, phone, ox_lib dialogs or any other focused menu is open. That's harmless, because the check picks up again a second after the menu closes.

### Only skipping illenium-appearance

illenium-appearance doesn't have an export or event that says when its menu is open. If you'd rather skip only that menu instead of every NUI, add an export to it. In `illenium-appearance/game/customization.lua`, the local `config` is set when the menu opens and cleared when it closes. Add this next to the existing `exports("startPlayerCustomization", ...)` line:

```lua
exports("isCustomizing", function() return config ~= nil end)
```

Then swap the condition in the `checkLoop` thread in `client.lua`:

```lua
            if not exports['illenium-appearance']:isCustomizing() then
```

You'll need to add the export again whenever you update illenium-appearance.

Neither way stops the store from saving the tied hairstyle if a player opens it with their hair already up. To handle that you'd let the hair down when the menu opens, for example using `isCustomizing()`.

## qbx_radialmenu changes

Out of the box, `/hat`, `/mask` and the radial menu's clothing buttons don't call the export. All of these changes go in `qbx_radialmenu/client/clothing.lua`.

### 1. Add a helper

Put this above `function ResetClothing(anim)`:

```lua
local function checkHairTie()
	if GetResourceState('your_resource') == 'started' then
		exports.your_resource:checkHairTie()
	end
end
```

The `GetResourceState` check keeps the radial menu working if the hair tie resource isn't running.

### 2. Fix `/hat` so it puts your hat back

This is a bug in qbx_radialmenu itself. The `/hat` command calls `ToggleProps({'Hat'})` with a new table each time, and the removed hat is saved under that table as a key. The second `/hat` looks it up under a different table, finds nothing, and says there's nothing to put on. The radial menu button passes the string `'Hat'`, so it doesn't have this problem.

At the top of `ToggleProps`, replace

```lua
	local Prop = Props[id] or Props[id[1]]
```

with

```lua
	if type(id) == 'table' then id = id[1] end
	local Prop = Props[id]
```

Now `/hat` and the radial menu button share one saved hat, so one can take it off and the other can put it back.

### 3. Check the hair when a hat comes off or goes on

In `ToggleProps`, in the `if not Prop.Variants then` branch, change

```lua
		if Cur.Prop ~= -1 then
			PlayToggleEmote(Prop.Emote.Off, function() LastEquipped[id] = Cur ClearPedProp(cache.ped, Prop.Prop) end) return true
		else
			local Last = LastEquipped[id]
			if Last then
				PlayToggleEmote(Prop.Emote.On, function() SetPedPropIndex(cache.ped, Prop.Prop, Last.Prop, Last.Texture, true) end) LastEquipped[id] = false return true
			end
		end
```

to

```lua
		if Cur.Prop ~= -1 then
			PlayToggleEmote(Prop.Emote.Off, function() LastEquipped[id] = Cur ClearPedProp(cache.ped, Prop.Prop) end)
			if Prop.Prop == 0 then checkHairTie() end
			return true
		else
			local Last = LastEquipped[id]
			if Last then
				PlayToggleEmote(Prop.Emote.On, function() SetPedPropIndex(cache.ped, Prop.Prop, Last.Prop, Last.Texture, true) end) LastEquipped[id] = false
				if Prop.Prop == 0 then checkHairTie() end
				return true
			end
		end
```

The visor uses prop 0 too, so in the `else` (variants) branch change

```lua
				PlayToggleEmote(Prop.Emote.On, function() SetPedPropIndex(cache.ped, Prop.Prop, v, Cur.Texture, true) end) return true
```

to

```lua
				PlayToggleEmote(Prop.Emote.On, function() SetPedPropIndex(cache.ped, Prop.Prop, v, Cur.Texture, true) end)
				if Prop.Prop == 0 then checkHairTie() end
				return true
```

`PlayToggleEmote` waits for the emote before swapping the prop, so by the time `checkHairTie()` runs the hat has already changed.

### 4. Check the hair when a mask comes off or goes on

The mask goes through `ToggleClothing`, in the `else` branch of `if not Toggle.Table.Standalone then`. There are two `PlayToggleEmote(...)` calls there, one that takes it off and one that puts it back. Add the check after each one, just before its `return true`:

```lua
				end)
				if Toggle.Drawable == 1 then checkHairTie() end
				return true
```

```lua
			end)
			if Toggle.Drawable == 1 then checkHairTie() end
			return true
```

`Toggle.Drawable == 1` makes sure it only runs for the mask, not the shirt, pants or bag that share this branch.

### 5. Check the hair after clothes are reset

`ResetClothing` puts everything back on when the radial menu restarts or `qb-radialmenu:ResetClothing` fires. Add the check at the end:

```lua
	LastEquipped = {}
	checkHairTie()
end
```
