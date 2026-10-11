--[[
===================================================================
  MM2 VALUE PANEL
  The StarPet panel layout, with the bot stripped out

  Right Shift   show / hide the panel

  What it does
  ------------
  Calls Remotes/Extras/GetFullInventory(player), reads the Owned maps
  under Weapons/Pets/Toys/Uniques, matches every entry against the
  value table and totals it per category. It reads other players the
  same way, so no inventory window has to be opened.

  Auto accept
  -----------
  Accepts every incoming trade request and presses ACCEPT in the
  trade window once MM2's countdown ends. No whitelist.
===================================================================
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ===================================================================
-- CONFIG
-- ===================================================================
local INVENTORY_REMOTE   = "Remotes/Extras/GetFullInventory"
local INVENTORY_BRANCHES = { "Weapons", "Pets", "Toys", "Uniques" }
local INVENTORY_TIMEOUT  = 6
local PANEL_POS_FILE     = "mm2_value_panel_position.json"

-- Internal-name to display-name pairs the panel has read off inventory
-- windows. It grows every time you look at anyone's inventory and
-- survives restarts, so a name only has to be seen once, ever.
local NAME_MAP_FILE      = "mm2_name_map_v2.json"

-- Where the value list lives, so prices can be updated without handing
-- anyone a new script. Paste a raw file link here - GitHub's
-- raw.githubusercontent.com works, and unlike the value sites it is not
-- behind bot protection. Leave it empty to use the built-in list only.
local VALUES_URL         = "https://raw.githubusercontent.com/ClipThatDude/ClipHub/main/values.json"
local VALUES_CACHE_FILE  = "mm2_values_cache.json"

-- Key that shows and hides the panel.
local TOGGLE_KEY = Enum.KeyCode.RightShift

-- MM2's own windows draw over the panel unless it asks for a higher
-- layer, and a panel buried under the trade window cannot be dragged
-- out from under it either.
local PANEL_DISPLAY_ORDER = 10000

-- How much of the item picture the trade slots show.
--   "full"   flat images plus MM2's 3D previews  (prettiest, costs the most)
--   "image"  flat images only, no 3D preview     (cheap)
--   "off"    no pictures
-- A 3D preview is a live render, so every one on screen costs frames.
-- The ICONS button on the Trade page switches this without an edit.
local TRADE_ICON_MODE = "image"

-- Your own pictures, which win over whatever the game is showing.
-- The key is the item name, the value is a Roblox asset: a plain id,
-- a library/catalog link or a full rbxassetid:// string all work.
-- Anything not listed here falls back to the game's own card, so the
-- table can be filled in a few items at a time.
--     ["Darksword"] = 123456789,
--     ["Chroma Raygun"] = "rbxassetid://123456789",
local ICON_ASSETS = {
}

-- Which categories count. Anything set to false is hidden entirely.
local SHOW_CATEGORIES = {
	Godly   = true,
	Ancient = true,
	Vintage = true,
	Chroma  = true,
	Unique  = true,
}

-- Items the value table does not recognise. Off, so the report shows
-- only the four categories above. The Inventory page still prints how
-- many were skipped, because a name the panel has not learned yet looks
-- exactly like an item nobody owns, and that is worth noticing.
-- On, now that LEARN ALL supplies MM2's own rarity: the list is no
-- longer every common knife a player owns, it is the short set of
-- Godly/Ancient/Vintage/Chroma items this table has no price for.
local SHOW_UNPRICED = true

-- Everyone owns these, they cannot be traded and are worth nothing.
local HIDDEN_ITEMS = {
	defaultknife = true, defaultgun = true, defaultsword = true,
}

local CATEGORY_ORDER = { "Ancient", "Chroma", "Godly", "Vintage", "Unique" }

-- Per-category text colour, used for the panel display only.
-- The clipboard copy stays plain text.
local CATEGORY_COLOR_HEX = {
	Ancient = "#B56CFF",   -- purple
	Chroma  = "#FF8AD8",   -- light pink
	Godly   = "#FF4FB8",   -- vivid pink
	Unique  = "#FF9A3D",   -- orange, the colour Corrupt carries in game
	Vintage = "#FFD85A",   -- gold, as the game labels them
	Other   = "#A6A8B3",   -- neutral grey
}

-- How the COPY button formats things for Discord.
--   "ansi"  code block with colours   (Discord renders these)
--   "code"  plain monospace code block
--   "plain" bare text, no fences
local COPY_STYLE = "ansi"

-- Discord refuses a message over 2000 characters. Past that it turns
-- the paste into a .txt attachment, and inside an attachment the colour
-- codes are not rendered, they are just printed as gibberish. So the
-- copy trims itself to fit instead, dropping the least valuable items
-- and saying how many it left out.
local DISCORD_LIMIT = 2000

-- What to do when the list is longer than Discord allows.
--   "auto"   colour when it fits in one message, otherwise the full
--            list as plain text, which Discord attaches as a .txt
--   "colour" always the coloured block
--   "plain"  always plain text
-- Colour codes only mean something inside a Discord message. In an
-- attachment they are printed literally, so an over-long paste has to
-- drop them or it arrives as gibberish.
local COPY_LONG = "auto"

-- Windows puts \r\n in the clipboard where the script wrote \n, so the
-- text Discord receives is one character longer per line than the text
-- measured here. That difference alone was enough to push a 1,98x
-- character paste past the limit and into an attachment, which is why
-- every line counts as one extra and a small margin is held back.
local COPY_SAFETY = 24

-- Discord only understands the sixteen classic terminal colours.
local CATEGORY_ANSI = {
	Ancient = "35",   -- magenta
	Chroma  = "36",   -- cyan
	Godly   = "31",   -- red
	Unique  = "37",   -- white; Discord has no orange, and yellow is taken
	Vintage = "33",   -- yellow
	Other   = "37",   -- white
}

-- Same categories again as Color3, for the parts of the panel that
-- paint a frame rather than mark up text.
local CATEGORY_COLOR3 = {
	Ancient = Color3.fromRGB(181, 108, 255),
	Chroma  = Color3.fromRGB(255, 138, 216),
	Godly   = Color3.fromRGB(255,  79, 184),
	Unique  = Color3.fromRGB(255, 154,  61),
	Vintage = Color3.fromRGB(255, 216,  90),
	Other   = Color3.fromRGB(106, 108, 120),
}

local VALUE_COLOR_HEX = "#55B9FF"
local DIM_COLOR_HEX   = "#8A8C99"
local TOTAL_COLOR_HEX = "#64E68C"

-- ===================================================================
-- VALUE TABLE
-- ===================================================================
local DATA = {
  values = {
	["Alienbeam"]=1850,
	["America"]=7,
	["Amerilaser"]=22,
	["Australis"]=140,
	["Bat"]=125,
	["Battleaxe"]=12,
	["Battleaxe II"]=17,
	["Batwing"]=42,
	["Bauble"]=675,
	["Beachy"]=85,
	["Bioblade"]=8,
	["Blaster"]=17,
	["Blizzard"]=295,
	["Blood"]=8,
	["Bloom"]=400,
	["Blossom"]=1320,
	["Blue Seer"]=3,
	["Boneblade"]=7,
	["Borealis"]=145,
	["Candleflame"]=33,
	["Candy"]=80,
	["Celestial"]=2250,
	["Chill"]=10,
	["Chroma Alienbeam"]=24000,
	["Chroma Bauble"]=29000,
	["Chroma Beachy"]=1150,
	["Chroma Blizzard"]=5500,
	["Chroma Boneblade"]=22,
	["Chroma Candleflame"]=40,
	["Chroma Constellation"]=27000,
	["Chroma Cookiecane"]=32,
	["Chroma Darkbringer"]=65,
	["Chroma Deathshard"]=35,
	["Chroma Elderwood Blade"]=37,
	["Chroma Evergreen"]=42000,
	["Chroma Evergun"]=56000,
	["Chroma Fang"]=32,
	["Chroma Gemstone"]=32,
	["Chroma Gingerblade"]=27,
	["Chroma Heart Wand"]=3600,
	["Chroma Heat"]=28,
	["Chroma Icecream"]=1850,
	["Chroma Laser"]=40,
	["Chroma Lightbringer"]=60,
	["Chroma Luger"]=50,
	["Chroma Ornament"]=1825,
	["Chroma Raygun"]=15000,
	["Chroma Sands"]=1200,
	["Chroma Saw"]=23,
	["Chroma Seer"]=28,
	["Chroma Shark"]=32,
	["Chroma Slasher"]=32,
	["Chroma Snow Dagger"]=2350,
	["Chroma Snowcannon"]=7750,
	["Chroma Snowstorm"]=4250,
	["Chroma Sunrise"]=10750,
	["Chroma Sunset"]=7250,
	["Chroma Sweet"]=1725,
	["Chroma Swirly Gun"]=35,
	["Chroma Tides"]=27,
	["Chroma Traveler's Gun"]=140000,
	["Chroma Treat"]=1775,
	["Chroma Vampire's Gun"]=26000,
	["Chroma Watergun"]=2300,
	["Clockwork"]=10,
	["Constellation"]=2600,
	["Cookieblade"]=3,
	["Cookiecane"]=13,
	["Corrupt"]=350,
	["Cowboy"]=4,
	["Darkbringer"]=33,
	["Darkshot"]=1800,
	["Darksword"]=1775,
	["Deathshard"]=13,
	["Eggblade"]=5,
	["Elderwood Blade"]=33,
	["Elderwood Revolver"]=33,
	["Elderwood Scythe"]=38,
	["Eternal"]=7,
	["Eternal II"]=7,
	["Eternal III"]=8,
	["Eternal IV"]=8,
	["Eternalcane"]=13,
	["Evergreen"]=2700,
	["Evergun"]=3450,
	["Fang"]=10,
	["Flames"]=5,
	["Flora"]=405,
	["Flowerwood"]=235,
	["Flowerwood Gun"]=240,
	["Frostbite"]=7,
	["Frostsaber"]=10,
	["Gemstone"]=15,
	["Ghost"]=8,
	["Ghostblade"]=7,
	["Ginger Luger"]=17,
	["Gingerblade"]=13,
	["Gingermint"]=12,
	["Gingerscope"]=15000,
	["Golden"]=4,
	["Green Luger"]=23,
	["Hallow's Blade"]=8,
	["Hallow's Edge"]=8,
	["Hallowgun"]=20,
	["Hallowscythe"]=30,
	["Handsaw"]=8,
	["Harvester"]=250,
	["Heart Wand"]=340,
	["Heartblade"]=65,
	["Heat"]=10,
	["Ice Dragon"]=7,
	["Ice Shard"]=7,
	["Icebeam"]=18,
	["Iceblaster"]=33,
	["Icebreaker"]=65,
	["Icecream"]=155,
	["Iceflake"]=15,
	["Icepiercer"]=160,
	["Icewing"]=13,
	["Jinglegun"]=13,
	["Laser"]=22,
	["Laser|Rare"]=8,
	["Lightbringer"]=32,
	["Logchopper"]=18,
	["Luger"]=18,
	["Lugercane"]=13,
	["Makeshift"]=33,
	["Minty"]=13,
	["Nebula"]=13,
	["Nightblade"]=20,
	["Ocean"]=250,
	["Old Glory"]=15,
	["Orange Seer"]=2,
	["Ornament"]=65,
	["Pearl"]=75,
	["Pearlshine"]=80,
	["Peppermint"]=4,
	["Phantom"]=35,
	["Phaser"]=5,
	["Pixel"]=17,
	["Plasmabeam"]=18,
	["Plasmablade"]=15,
	["Prince"]=6,
	["Prismatic"]=7,
	["Pumpking"]=7,
	["Purple Seer"]=3,
	["Rainbow"]=405,
	["Rainbow Gun"]=410,
	["Raygun"]=1800,
	["Red Luger"]=35,
	["Red Seer"]=3,
	["Sakura"]=1310,
	["Sands"]=85,
	["Saw"]=7,
	["Seer"]=3,
	["Shadow"]=6,
	["Shark"]=20,
	["Slasher"]=15,
	["Snow Dagger"]=175,
	["Snowcannon"]=675,
	["Snowflake"]=5,
	["Snowstorm"]=295,
	["Soul"]=685,
	["Spectre"]=35,
	["Spider"]=10,
	["Spirit"]=675,
	["Splitter"]=3,
	["Sugar"]=32,
	["Sunrise"]=1000,
	["Sunset"]=650,
	["Sweet"]=150,
	["Swirly Axe"]=38,
	["Swirly Blade"]=12,
	["Swirly Gun"]=18,
	["Tides"]=10,
	["Traveler's Axe"]=7750,
	["Traveler's Gun"]=5200,
	["Treat"]=155,
	["Turkey"]=1850,
	["Vampire's Axe"]=1600,
	["Vampire's Edge"]=15,
	["Vampire's Gun"]=1900,
	["Virtual"]=13,
	["Watergun"]=155,
	["Waves"]=245,
	["Winter's Edge"]=5,
	["Xenoknife"]=405,
	["Xenoshot"]=405,
	["Xmas"]=7,
	["Yellow Seer"]=2,
  },
  cats = {
	["Alienbeam"]="Godly",
	["America"]="Vintage",
	["Amerilaser"]="Godly",
	["Australis"]="Godly",
	["Bat"]="Godly",
	["Battleaxe"]="Godly",
	["Battleaxe II"]="Godly",
	["Batwing"]="Ancient",
	["Bauble"]="Godly",
	["Beachy"]="Godly",
	["Bioblade"]="Godly",
	["Blaster"]="Godly",
	["Blizzard"]="Godly",
	["Blood"]="Vintage",
	["Bloom"]="Godly",
	["Blossom"]="Godly",
	["Blue Seer"]="Godly",
	["Boneblade"]="Godly",
	["Borealis"]="Godly",
	["Candleflame"]="Godly",
	["Candy"]="Godly",
	["Celestial"]="Ancient",
	["Chill"]="Godly",
	["Chroma Alienbeam"]="Chroma",
	["Chroma Bauble"]="Chroma",
	["Chroma Beachy"]="Chroma",
	["Chroma Blizzard"]="Chroma",
	["Chroma Boneblade"]="Chroma",
	["Chroma Candleflame"]="Chroma",
	["Chroma Constellation"]="Chroma",
	["Chroma Cookiecane"]="Chroma",
	["Chroma Darkbringer"]="Chroma",
	["Chroma Deathshard"]="Chroma",
	["Chroma Elderwood Blade"]="Chroma",
	["Chroma Evergreen"]="Chroma",
	["Chroma Evergun"]="Chroma",
	["Chroma Fang"]="Chroma",
	["Chroma Gemstone"]="Chroma",
	["Chroma Gingerblade"]="Chroma",
	["Chroma Heart Wand"]="Chroma",
	["Chroma Heat"]="Chroma",
	["Chroma Icecream"]="Chroma",
	["Chroma Laser"]="Chroma",
	["Chroma Lightbringer"]="Chroma",
	["Chroma Luger"]="Chroma",
	["Chroma Ornament"]="Chroma",
	["Chroma Raygun"]="Chroma",
	["Chroma Sands"]="Chroma",
	["Chroma Saw"]="Chroma",
	["Chroma Seer"]="Chroma",
	["Chroma Shark"]="Chroma",
	["Chroma Slasher"]="Chroma",
	["Chroma Snow Dagger"]="Chroma",
	["Chroma Snowcannon"]="Chroma",
	["Chroma Snowstorm"]="Chroma",
	["Chroma Sunrise"]="Chroma",
	["Chroma Sunset"]="Chroma",
	["Chroma Sweet"]="Chroma",
	["Chroma Swirly Gun"]="Chroma",
	["Chroma Tides"]="Chroma",
	["Chroma Traveler's Gun"]="Chroma",
	["Chroma Treat"]="Chroma",
	["Chroma Vampire's Gun"]="Chroma",
	["Chroma Watergun"]="Chroma",
	["Clockwork"]="Godly",
	["Constellation"]="Godly",
	["Cookieblade"]="Godly",
	["Cookiecane"]="Godly",
	["Corrupt"]="Unique",
	["Cowboy"]="Vintage",
	["Darkbringer"]="Godly",
	["Darkshot"]="Godly",
	["Darksword"]="Godly",
	["Deathshard"]="Godly",
	["Eggblade"]="Godly",
	["Elderwood Blade"]="Godly",
	["Elderwood Revolver"]="Godly",
	["Elderwood Scythe"]="Ancient",
	["Eternal"]="Godly",
	["Eternal II"]="Godly",
	["Eternal III"]="Godly",
	["Eternal IV"]="Godly",
	["Eternalcane"]="Godly",
	["Evergreen"]="Godly",
	["Evergun"]="Godly",
	["Fang"]="Godly",
	["Flames"]="Godly",
	["Flora"]="Godly",
	["Flowerwood"]="Godly",
	["Flowerwood Gun"]="Godly",
	["Frostbite"]="Godly",
	["Frostsaber"]="Godly",
	["Gemstone"]="Godly",
	["Ghost"]="Vintage",
	["Ghostblade"]="Godly",
	["Ginger Luger"]="Godly",
	["Gingerblade"]="Godly",
	["Gingermint"]="Godly",
	["Gingerscope"]="Ancient",
	["Golden"]="Vintage",
	["Green Luger"]="Godly",
	["Hallow's Blade"]="Godly",
	["Hallow's Edge"]="Godly",
	["Hallowgun"]="Godly",
	["Hallowscythe"]="Ancient",
	["Handsaw"]="Godly",
	["Harvester"]="Ancient",
	["Heart Wand"]="Godly",
	["Heartblade"]="Godly",
	["Heat"]="Godly",
	["Ice Dragon"]="Godly",
	["Ice Shard"]="Godly",
	["Icebeam"]="Godly",
	["Iceblaster"]="Godly",
	["Icebreaker"]="Ancient",
	["Icecream"]="Godly",
	["Iceflake"]="Godly",
	["Icepiercer"]="Ancient",
	["Icewing"]="Ancient",
	["Jinglegun"]="Godly",
	["Laser"]="Godly",
	["Laser|Rare"]="Vintage",
	["Lightbringer"]="Godly",
	["Logchopper"]="Ancient",
	["Luger"]="Godly",
	["Lugercane"]="Godly",
	["Makeshift"]="Godly",
	["Minty"]="Godly",
	["Nebula"]="Godly",
	["Nightblade"]="Godly",
	["Ocean"]="Godly",
	["Old Glory"]="Godly",
	["Orange Seer"]="Godly",
	["Ornament"]="Godly",
	["Pearl"]="Godly",
	["Pearlshine"]="Godly",
	["Peppermint"]="Godly",
	["Phantom"]="Godly",
	["Phaser"]="Vintage",
	["Pixel"]="Godly",
	["Plasmabeam"]="Godly",
	["Plasmablade"]="Godly",
	["Prince"]="Vintage",
	["Prismatic"]="Godly",
	["Pumpking"]="Godly",
	["Purple Seer"]="Godly",
	["Rainbow"]="Godly",
	["Rainbow Gun"]="Godly",
	["Raygun"]="Godly",
	["Red Luger"]="Godly",
	["Red Seer"]="Godly",
	["Sakura"]="Godly",
	["Sands"]="Godly",
	["Saw"]="Godly",
	["Seer"]="Godly",
	["Shadow"]="Vintage",
	["Shark"]="Godly",
	["Slasher"]="Godly",
	["Snow Dagger"]="Godly",
	["Snowcannon"]="Godly",
	["Snowflake"]="Godly",
	["Snowstorm"]="Godly",
	["Soul"]="Godly",
	["Spectre"]="Godly",
	["Spider"]="Godly",
	["Spirit"]="Godly",
	["Splitter"]="Vintage",
	["Sugar"]="Godly",
	["Sunrise"]="Godly",
	["Sunset"]="Godly",
	["Sweet"]="Godly",
	["Swirly Axe"]="Ancient",
	["Swirly Blade"]="Godly",
	["Swirly Gun"]="Godly",
	["Tides"]="Godly",
	["Traveler's Axe"]="Ancient",
	["Traveler's Gun"]="Godly",
	["Treat"]="Godly",
	["Turkey"]="Godly",
	["Vampire's Axe"]="Ancient",
	["Vampire's Edge"]="Godly",
	["Vampire's Gun"]="Godly",
	["Virtual"]="Godly",
	["Watergun"]="Godly",
	["Waves"]="Godly",
	["Winter's Edge"]="Godly",
	["Xenoknife"]="Godly",
	["Xenoshot"]="Godly",
	["Xmas"]="Godly",
	["Yellow Seer"]="Godly",
  },
  aliases = {
	["ElderwoodKnife"]="Elderwood Blade",
	["Gingermint_K"]="Cookiecane",
	["SunsetKnife"]="Sunset",
	["XenoGun"]="Xenoshot",
	["TreeKnife2023"]="Evergreen",
	["TreeGun2023"]="Evergun",
	["Pearl_G"]="Pearlshine",
	["Bats_K_2024"]="Bat",
	["Blossom_G"]="Blossom",
	["Rainbow_K"]="Rainbow",
	["SunsetGun"]="Sunrise",
	["TravelerGun"]="Traveler's Gun",
	["Turkey2023"]="Turkey",
	["BaubleKnife"]="Ornament",
	["Scythe"]="Batwing",
	["UFOKnife"]="Alienbeam",
	["WraithGun"]="Soul",
	["Sorry"]="Corrupt",
	["AuroraGun"]="Borealis",
	["AuroraKnife"]="Australis",
	["ElderwoodGun"]="Elderwood Revolver",
	["Eternal2"]="Eternal II",
	["Eternal3"]="Eternal III",
	["Eternal4"]="Eternal IV",
	["Phantom2022"]="Phantom",
	["Rainbow_G"]="Rainbow Gun",
	["Waves_K"]="Waves",
	["AB"]="Alienbeam",
	["ALB"]="Alienbeam",
	["Ameri"]="Amerilaser",
	["BA"]="Battleaxe",
	["BA1"]="Battleaxe",
	["BA2"]="Battleaxe II",
	["BB"]="Boneblade",
	["Baub"]="Bauble",
	["Bio"]="Bioblade",
	["Blizz"]="Blizzard",
	["CF"]="Candleflame",
	["CW"]="Clockwork",
	["Cannon"]="Snowcannon",
	["Const"]="Constellation",
	["DB"]="Darkbringer",
	["DS"]="Deathshard",
	["DShot"]="Darkshot",
	["DSword"]="Darksword",
	["Dagger"]="Snow Dagger",
	["E1"]="Eternal",
	["E2"]="Eternal II",
	["E3"]="Eternal III",
	["E4"]="Eternal IV",
	["EGreen"]="Evergreen",
	["EGun"]="Evergun",
	["EW Blade"]="Elderwood Blade",
	["EW Rev"]="Elderwood Revolver",
	["EWB"]="Elderwood Blade",
	["EWG"]="Elderwood Revolver",
	["Ecane"]="Eternalcane",
	["FW"]="Flowerwood",
	["FW Gun"]="Flowerwood Gun",
	["FW Knife"]="Flowerwood",
	["FWG"]="Flowerwood Gun",
	["FWK"]="Flowerwood",
	["FWood"]="Flowerwood",
	["FWood Gun"]="Flowerwood Gun",
	["FWood Knife"]="Flowerwood",
	["GB"]="Gingerblade",
	["GL"]="Green Luger",
	["GM"]="Gingermint",
	["GMint"]="Gingermint",
	["Gem"]="Gemstone",
	["Ginger Lug"]="Ginger Luger",
	["Green Seer"]="Seer",
	["HB"]="Heartblade",
	["HBlade"]="Hallow's Blade",
	["HEdge"]="Hallow's Edge",
	["HG"]="Hallowgun",
	["HS"]="Handsaw",
	["HW"]="Heart Wand",
	["IC"]="Icecream",
	["Jingle"]="Jinglegun",
	["LB"]="Lightbringer",
	["Lcane"]="Lugercane",
	["Lug"]="Luger",
	["MS"]="Makeshift",
	["NB"]="Nightblade",
	["Neb"]="Nebula",
	["OG"]="Old Glory",
	["Orn"]="Ornament",
	["Pris"]="Prismatic",
	["Pure Seer"]="Seer",
	["RB"]="Rainbow",
	["RB Gun"]="Rainbow Gun",
	["RG"]="Raygun",
	["RL"]="Red Luger",
	["Ray"]="Raygun",
	["SR"]="Sunrise",
	["SW Blade"]="Swirly Blade",
	["SW Gun"]="Swirly Gun",
	["SWB"]="Swirly Blade",
	["SWG"]="Swirly Gun",
	["Sak"]="Sakura",
	["Slash"]="Slasher",
	["Spec"]="Spectre",
	["Sug"]="Sugar",
	["TVG"]="Traveler's Gun",
	["Trav Gun"]="Traveler's Gun",
	["VG"]="Vampire's Gun",
	["Vamp Gun"]="Vampire's Gun",
	["Vedge"]="Vampire's Edge",
	["Virt"]="Virtual",
	["WEdge"]="Winter's Edge",
	["WTG"]="Watergun",
	["Wand"]="Heart Wand",
  },
}

-- ===================================================================
-- THEME
-- ===================================================================
local C = {
	bg       = Color3.fromRGB(14, 14, 18),
	panel    = Color3.fromRGB(17, 17, 22),
	page     = Color3.fromRGB(19, 19, 24),
	card     = Color3.fromRGB(24, 24, 29),
	field    = Color3.fromRGB(31, 34, 42),
	stroke   = Color3.fromRGB(37, 38, 45),
	text     = Color3.fromRGB(235, 235, 240),
	dim      = Color3.fromRGB(125, 127, 140),
	faint    = Color3.fromRGB(100, 102, 116),
	accent   = Color3.fromRGB(72, 172, 230),
	green    = Color3.fromRGB(42, 150, 85),
	greenTxt = Color3.fromRGB(100, 230, 140),
	red      = Color3.fromRGB(175, 55, 65),
	blue     = Color3.fromRGB(48, 110, 170),
	neutral  = Color3.fromRGB(45, 48, 58),
}

-- ===================================================================
-- VALUE INDEX
-- ===================================================================
local lookup, catOf, displayOf, sortedItems, itemCount = {}, {}, {}, {}, 0

-- The game and the value site spell the same item differently:
-- "Snow Dagger" / "SnowDagger", "Chroma Darkbringer" / "BeachyChroma".
-- Dropping everything that is not a letter or digit makes them match.
local function squash(s)
	return (tostring(s or ""):lower():gsub("[^%a%d]", ""))
end

local function buildIndex()
	lookup, catOf, displayOf, sortedItems, itemCount = {}, {}, {}, {}, 0

	for name, value in pairs(DATA.values) do
		local category = DATA.cats[name] or "Godly"

		lookup[squash(name)]    = value
		catOf[squash(name)]     = category
		-- "Laser|Vintage" is still printed as "Laser"
		displayOf[squash(name)] = name:match("^(.-)|") or name

		if SHOW_CATEGORIES[category] then
			itemCount = itemCount + 1
			table.insert(sortedItems, { name = name, value = value, category = category })
		end
	end

	for alias, target in pairs(DATA.aliases) do
		local value = DATA.values[target]
		if value then
			lookup[squash(alias)]    = value
			catOf[squash(alias)]     = DATA.cats[target] or "Godly"
			displayOf[squash(alias)] = target
		end
	end

	table.sort(sortedItems, function(a, b) return a.value > b.value end)
end

-- ===================================================================
-- NAME RESOLUTION
--
-- MM2's internal names are not the names players see. Some are only a
-- spelling difference (SnowDagger, GreenLuger), some follow a pattern
-- (Blossom_G, Phantom2022, Rainbow_K), and some are arbitrary: Sorry
-- is Corrupt, WraithGun is Soul, Scythe is Batwing.
--
-- Spelling and patterns are handled here. The arbitrary ones cannot be
-- derived at all, so they come from the alias table and from what the
-- panel learns off the screen (see the learned map below).
-- ===================================================================
local learned = {}   -- squashed internal name -> display name
local rarityOf = {}  -- squashed internal name -> MM2's own rarity

local function resolveDirect(name)
	local key = squash(name)
	if lookup[key] then return key end

	-- the game writes chromas both ways: ChromaDarkbringer, BeachyChroma
	local trailing = tostring(name):match("^(.-)[Cc]hroma$")
	if trailing and #trailing > 0 then
		key = squash("Chroma " .. trailing)
		if lookup[key] then return key end
	end

	return nil
end

-- Patterns MM2 repeats: _G and _K for the gun and knife of a pair, and
-- a release year glued onto a reissued item.
local function resolveByPattern(name)
	local text = tostring(name)
	local tries = {}

	local base = text:match("^(.-)_[Gg]$")
	if base then
		table.insert(tries, base .. " Gun")
		table.insert(tries, base)
	end

	base = text:match("^(.-)_[Kk]$")
	if base then
		table.insert(tries, base)
		table.insert(tries, base .. " Knife")
	end

	-- a release year, with or without the underscore in front of it
	base = text:match("^(.-)_?20%d%d$")
	if base then
		table.insert(tries, base)
		local stem = base:match("^(.-)_[GgKk]$")
		if stem then
			table.insert(tries, stem)
			table.insert(tries, stem .. " Gun")
		end
	end

	-- MM2 glues the weapon type onto the owner's name and drops the
	-- apostrophe: VampireAxe is Vampire's Axe, TravelerGun is
	-- Traveler's Gun. Both spellings are worth trying.
	for _, suffix in ipairs({ "Gun", "Knife", "Axe", "Blade", "Sword",
	                          "Scythe", "Shot", "Wand", "Cane" }) do
		base = text:match("^(.-)" .. suffix .. "$")

		if base and #base > 2 then
			table.insert(tries, base .. " " .. suffix)
			table.insert(tries, base .. "'s " .. suffix)
			table.insert(tries, base)
		end
	end

	for _, candidate in ipairs(tries) do
		local key = resolveDirect(candidate)
		if key then return key end
	end

	return nil
end

local function resolveBase(name)
	local key = resolveDirect(name)
	if key then return key end

	local display = learned[squash(name)]
	if display then
		key = resolveDirect(display)
		if key then return key end
	end

	return resolveByPattern(name)
end

local function resolve(name)
	if not name or name == "" then return nil end

	-- Chroma first, and deliberately before the learned map.
	--
	-- MM2 gives a chroma the plain item's ItemName: TravelerGunChroma is
	-- listed as "Traveler's Gun". LEARN ALL files that pair faithfully,
	-- and the learned map used to win, so a Chroma Traveler's Gun priced
	-- as a Traveler's Gun - 5,200 instead of 140,000.
	local base = tostring(name):match("^(.-)[Cc]hroma$")
		or tostring(name):match("^[Cc]hroma(.+)$")

	if base and #base > 0 then
		local key = resolveDirect("Chroma " .. base)
		if key then return key end

		local baseKey = resolveBase(base)
		local shown = baseKey and displayOf[baseKey]

		if shown then
			key = resolveDirect("Chroma " .. shown)
			if key then return key end
		end
	end

	return resolveBase(name)
end

-- MM2 has more than one weapon that prints the same name: a Godly
-- Laser worth 22 and a Vintage Laser worth 8. They are different items
-- with different internal names, and the game knows which is which, so
-- when its rarity is on hand the value list is asked for that tier
-- first. Entries for those live under "Laser|Vintage".
local function resolveTiered(name)
	local tier = rarityOf[squash(name)]

	if tier then
		local base = resolve(name)
		local shown = base and displayOf[base]

		if shown then
			local qualified = resolveDirect(shown .. "|" .. tier)
			if qualified then return qualified end
		end
	end

	return resolve(name)
end

-- The remote answers with MM2's internal names. Nobody trades by those,
-- so anything shown or copied uses the name on the value list instead:
-- "Corrupt", not "Sorry".
local function displayName(name)
	local key = resolveTiered(name)
	return (key and displayOf[key]) or name
end

local function valueOf(name)
	local key = resolveTiered(name)
	if not key then return 0, nil end

	local category = catOf[key] or "Godly"
	if not SHOW_CATEGORIES[category] then return 0, category end

	return lookup[key], category
end

local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	while true do
		local k
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return s
end

local dataStamp = "built in"

-- ===================================================================
-- REMOTE VALUE LIST
--
-- The built-in table is a snapshot and goes stale. This reads a hosted
-- copy instead, with two safety nets: a local cache so an outage or a
-- slow start still gives you yesterday's prices, and a sanity check so
-- a truncated or mangled download can never wipe the list.
-- ===================================================================
local function applyData(fetched, stamp)
	if type(fetched) ~= "table" then return false end
	if type(fetched.values) ~= "table" then return false end

	local count = 0
	for _ in pairs(fetched.values) do count = count + 1 end

	-- a real list has hundreds of entries; anything tiny is a bad file
	if count < 50 then return false end

	DATA = {
		values  = fetched.values,
		cats    = (type(fetched.cats) == "table") and fetched.cats or {},
		aliases = (type(fetched.aliases) == "table") and fetched.aliases or {},
	}

	buildIndex()
	dataStamp = stamp or fetched.updated or "downloaded"
	return true
end

local function readCachedValues()
	if not (isfile and readfile) then return end

	pcall(function()
		if not isfile(VALUES_CACHE_FILE) then return end

		local raw = readfile(VALUES_CACHE_FILE)
		if type(raw) ~= "string" or raw == "" then return end

		local parsed = HttpService:JSONDecode(raw)
		applyData(parsed, (parsed and parsed.updated or "cached") .. " (cached)")
	end)
end

buildIndex()
readCachedValues()

-- The download happens on its own thread. Blocking startup on a request
-- that might hang would mean no panel at all until it timed out.
local function downloadValues(onDone)
	if VALUES_URL == "" then
		if onDone then onDone(false, "no url set") end
		return
	end

	task.spawn(function()
		local ok, body = pcall(function()
			return game:HttpGet(VALUES_URL, true)
		end)

		if not ok or type(body) ~= "string" then
			if onDone then onDone(false, "could not reach the list") end
			return
		end

		local parsed
		local okJson = pcall(function() parsed = HttpService:JSONDecode(body) end)

		if not okJson or not applyData(parsed) then
			if onDone then onDone(false, "the file was not a usable value list") end
			return
		end

		if writefile then pcall(writefile, VALUES_CACHE_FILE, body) end
		if onDone then onDone(true, dataStamp) end
	end)
end

-- ===================================================================
-- LEARNED NAMES
-- Saved as plain display names rather than resolved keys, so the file
-- stays readable and keeps working if the value table changes.
-- ===================================================================
local function loadLearned()
	if not (isfile and readfile) then return end

	pcall(function()
		if not isfile(NAME_MAP_FILE) then return end

		local raw = readfile(NAME_MAP_FILE)
		if type(raw) ~= "string" or raw == "" then return end

		local data = HttpService:JSONDecode(raw)
		if type(data) ~= "table" then return end

		-- the file used to hold a flat name map; both shapes are read
		local names  = (type(data.names) == "table") and data.names or data
		local tiers  = (type(data.rarity) == "table") and data.rarity or {}

		for internal, display in pairs(names) do
			if type(internal) == "string" and type(display) == "string" then
				learned[squash(internal)] = display
			end
		end

		for internal, tier in pairs(tiers) do
			if type(internal) == "string" and type(tier) == "string" then
				rarityOf[squash(internal)] = tier
			end
		end
	end)
end

local function saveLearned()
	if not writefile then return end

	pcall(function()
		writefile(NAME_MAP_FILE, HttpService:JSONEncode({
			names  = learned,
			rarity = rarityOf,
		}))
	end)
end

loadLearned()

-- ===================================================================
-- CUSTOM ICONS
-- Roblox only renders assets it hosts, so these have to be asset ids;
-- a link to an image on another site cannot be shown in game.
-- ===================================================================
local iconLookup = {}

for name, asset in pairs(ICON_ASSETS) do
	local id = tostring(asset):match("%d+")
	if id then
		iconLookup[squash(name)] = "rbxassetid://" .. id
	end
end

local function iconFor(name)
	local key = resolve(name) or squash(name)
	local id = iconLookup[key]
	if not id then return nil end
	return { kind = "image", id = id }
end

-- ===================================================================
-- RICH TEXT HELPERS
-- A label with RichText on treats < > & as markup, so every piece of
-- text that came from the game has to be escaped before it goes in.
-- ===================================================================
local function escapeRichText(s)
	s = tostring(s or "")
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end

local function tint(hex, s)
	return string.format('<font color="%s">%s</font>', hex, s)
end

local function bold(s)
	return "<b>" .. s .. "</b>"
end

-- Pads to a fixed width first, then escapes, so the columns still line
-- up: an escaped & is four characters of markup but one on screen.
local function cell(text, width, rightAlign)
	local raw = tostring(text or "")
	local pad = width - #raw
	if pad < 0 then pad = 0 end
	if rightAlign then
		return string.rep(" ", pad) .. escapeRichText(raw)
	end
	return escapeRichText(raw) .. string.rep(" ", pad)
end

-- The log was a wall of identical grey lines. Colour by what the line
-- is about, so a failed read or a finished scan is visible at a glance
-- instead of having to be read.
local LOG_RULES = {
	{ "could not", "#FF6B6B" }, { "failed",   "#FF6B6B" },
	{ "no answer", "#FF6B6B" }, { "refused",  "#FF6B6B" },
	{ "nothing",   "#FF6B6B" }, { "already running", "#FF6B6B" },

	{ "scanning",  "#55B9FF" },
	{ "scan all",  "#55B9FF" },

	{ "trade",     "#55C8FF" },

	{ "learned",   "#B56CFF" }, { "up to date", "#B56CFF" },
	{ "matched",   "#B56CFF" }, { "icons",      "#B56CFF" },

	{ "copied",    "#FFD85A" },
	{ "ready",     "#8A8C99" },
}

local function logColour(text)
	local lower = text:lower()

	for _, rule in ipairs(LOG_RULES) do
		if lower:find(rule[1], 1, true) then return rule[2] end
	end

	-- "Name: 12,345 Value (7 types, 20 items)" - a finished reading
	if lower:find(" value", 1, true) then return "#64E68C" end

	return "#A6A8B3"
end

local function colourLog(lines)
	local out = {}

	for _, line in ipairs(lines) do
		local stamp, body = line:match("^(%[%d+:%d+:%d+%])%s*(.*)$")

		if body then
			out[#out + 1] = tint("#6E7080", escapeRichText(stamp))
				.. " " .. tint(logColour(body), escapeRichText(body))
		else
			out[#out + 1] = tint("#A6A8B3", escapeRichText(line))
		end
	end

	return table.concat(out, "\n")
end

-- The one effect worth keeping from the coloured build: the Chroma
-- heading spells itself out in a gradient.
local CHROMA_RAINBOW = { "#FF5A5A", "#FF8A3D", "#FFD84A", "#62E66F",
                         "#55C8FF", "#7B7BFF", "#D96CFF", "#FF5AAE" }

local function rainbow(word)
	local out, n = {}, #CHROMA_RAINBOW
	for i = 1, #word do
		local hex = CHROMA_RAINBOW[((i - 1) % n) + 1]
		table.insert(out, tint(hex, escapeRichText(word:sub(i, i))))
	end
	return table.concat(out)
end

-- ===================================================================
-- INVENTORY READING
-- ===================================================================
local function resolveRemote()
	local node = ReplicatedStorage
	for part in INVENTORY_REMOTE:gmatch("[^/]+") do
		if not node then return nil end
		node = node:FindFirstChild(part)
	end
	if node and node:IsA("RemoteFunction") then return node end
	return nil
end

-- A RemoteFunction with no server handler blocks forever and pcall
-- does not save you, so the call runs on its own thread.
local function invokeWithTimeout(remote, arg)
	local finished, ok, result = false, false, nil

	task.spawn(function()
		local success, value = pcall(function()
			return remote:InvokeServer(arg)
		end)
		ok, result, finished = success, value, true
	end)

	local started = tick()
	while not finished and tick() - started < INVENTORY_TIMEOUT do
		task.wait(0.05)
	end

	if not finished then return "timeout" end
	if not ok then return "error", result end
	return "ok", result
end

-- returns items, or nil plus a short reason
local function readInventory(player)
	local remote = resolveRemote()
	if not remote then return nil, "remote not found" end

	local status, data = invokeWithTimeout(remote, player)

	if status == "timeout" then return nil, "no answer" end
	if status == "error"   then return nil, "refused" end
	if typeof(data) ~= "table" then return nil, "bad reply" end

	local items, unknown = {}, {}

	for _, branch in ipairs(INVENTORY_BRANCHES) do
		local node = data[branch]

		if type(node) == "table" then
			local owned = (type(node.Owned) == "table") and node.Owned or node

			for name, count in pairs(owned) do
				local amount = tonumber(count)

				if type(name) == "string" and amount and amount > 0
				   and not HIDDEN_ITEMS[squash(name)] then

					local value, category = valueOf(name)

					if value > 0 then
						table.insert(items, {
							name     = displayName(name),
							raw      = name,
							amount   = amount,
							value    = value,
							category = category or "Godly",
						})

					elseif not category then
						-- Not in the value table at all. Dropping these
						-- silently is what hid the gap: an item the panel
						-- cannot price looks exactly like an item you do
						-- not own. Now it is listed and says so.
						--
						-- Once LEARN ALL has run, MM2's own rarity is
						-- known, so the junk tiers stay out and what is
						-- left is the short list actually worth pricing.
						-- Once LEARN ALL has run, MM2's own rarity decides:
						-- anything outside the chosen tiers is dropped, so
						-- common knives never reach the list. Before it has
						-- run there is no rarity to go on, and hiding
						-- everything would hide real gaps, so unknowns pass.
						local tier = rarityOf[squash(name)]
						local haveRarities = next(rarityOf) ~= nil

						local wanted = haveRarities
							and (tier ~= nil and SHOW_CATEGORIES[tier] == true)
							or (not haveRarities)

						if wanted and #unknown < 200 then
							table.insert(unknown, {
								name = learned[squash(name)] or name,
								amount = amount,
								rarity = tier,
							})
						end
					end
				end
			end
		end
	end

	-- MM2 can return several internal names that are the same item to a
	-- trader, so without this the report prints "1x Borealis" three
	-- times instead of "3x Borealis".
	local merged, order = {}, {}

	for _, it in ipairs(items) do
		local key = it.name .. "|" .. it.category
		local seen = merged[key]

		if seen then
			seen.amount = seen.amount + it.amount
		else
			merged[key] = it
			table.insert(order, it)
		end
	end

	items = order

	if #items == 0 and #unknown == 0 then return nil, "nothing to count" end

	table.sort(items, function(a, b)
		local av, bv = a.value * a.amount, b.value * b.amount
		if av == bv then return a.name < b.name end
		return av > bv
	end)

	table.sort(unknown, function(a, b) return a.name < b.name end)

	return items, nil, unknown
end

local function totalsOf(items)
	local total, kinds, pieces = 0, 0, 0
	for _, it in ipairs(items or {}) do
		total  = total + it.value * it.amount
		kinds  = kinds + 1
		pieces = pieces + it.amount
	end
	return total, kinds, pieces
end

-- ===================================================================
-- CLIPBOARD FORMAT
-- Pasting bare lines into Discord looks like a wall of text: the
-- client uses a proportional font, so nothing lines up. Wrapping it
-- in a code block fixes the alignment, and Discord renders ANSI
-- escapes inside an "ansi" block, so the colours survive the trip.
-- ===================================================================
local ESC = string.char(27)

local function ansi(code, text)
	if COPY_STYLE ~= "ansi" then return text end
	return ESC .. "[" .. code .. "m" .. text .. ESC .. "[0m"
end

-- Column widths. Every character counts against Discord's 2000, and a
-- narrower line means more items survive the trim, so these are kept
-- just wide enough for the longest real name (ChromaLightbringer, 18)
-- and the largest real total.
local COL_AMOUNT, COL_NAME, COL_VALUE = 4, 22, 8

-- Same padding trick as the panel: pad the raw text, then decorate.
local function pad(text, width, rightAlign)
	local raw = tostring(text or "")
	local n = width - #raw
	if n < 0 then n = 0 end
	if rightAlign then return string.rep(" ", n) .. raw end
	return raw .. string.rep(" ", n)
end

local function buildCopy(groups, owner, total, kinds, pieces, unknown)
	local open  = (COPY_STYLE == "ansi" and "```ansi")
		or (COPY_STYLE == "code" and "```") or nil
	local close = (COPY_STYLE ~= "plain") and "```" or nil

	-- each item rendered both ways, so the choice can be made once the
	-- whole thing has been measured
	local byItem = {}

	for _, group in ipairs(groups) do
		local code = CATEGORY_ANSI[group.category] or CATEGORY_ANSI.Other

		for _, it in ipairs(group.items) do
			local left  = " " .. pad(it.amount .. "x", COL_AMOUNT)
				.. pad(it.name, COL_NAME)
			local right = pad(comma(it.value * it.amount), COL_VALUE, true)

			-- One escape opens the line, one switches to green for the
			-- number, one closes it. Resetting between the two halves,
			-- the way this used to, cost seven characters a line for
			-- nothing, because the next code overrides the previous one.
			-- the unit price only tells you something when there is
			-- more than one, so a single item leaves that column empty
			local unit = (it.amount > 1)
				and (comma(it.value) .. " ea") or ""

			byItem[it] = {
				rich = "  " .. pad(it.amount .. "x", COL_AMOUNT + 1)
					.. pad(it.name, 24)
					.. pad(unit, 12, true) .. "  "
					.. pad(comma(it.value * it.amount), 10, true),

				colour = (COPY_STYLE == "ansi")
					and (ESC .. "[0;" .. code .. "m" .. left
						.. ESC .. "[32m" .. right .. ESC .. "[0m")
					or (left .. right),
			}
		end
	end

	-- Two layouts, picked by where the text is going.
	--
	-- A Discord message is capped, so the coloured one is as narrow as
	-- it can be. A file has no cap, so the plain one spends the room on
	-- being readable: a rule under the header, a unit price beside any
	-- stack, and a total at the foot.
	local RICH_NAME, RICH_UNIT, RICH_TOTAL = 24, 12, 10
	local RICH_LEFT  = 2 + COL_AMOUNT + 1 + RICH_NAME + RICH_UNIT + 2
	local RICH_WIDTH = RICH_LEFT + RICH_TOTAL

	local function assemble(colour)
		local out = {}

		local function paint(code, text)
			if not colour then return text end
			return ansi(code, text)
		end

		-- ---------------------------------------------------------
		-- header
		-- ---------------------------------------------------------
		if colour then
			if open then out[#out + 1] = open end

			out[#out + 1] = paint("1;37", pad(owner or "Inventory", 20))
				.. paint("1;32", pad(comma(total) .. " Value", 12, true))
			out[#out + 1] = paint("0;37",
				string.format("%d types, %d items", kinds, pieces))
		else
			out[#out + 1] = pad(owner or "Inventory", RICH_WIDTH - 13)
				.. pad(comma(total) .. " Value", 13, true)
			out[#out + 1] = string.format("%d types  -  %d items", kinds, pieces)
			out[#out + 1] = string.rep("-", RICH_WIDTH)
		end

		-- ---------------------------------------------------------
		-- categories
		-- ---------------------------------------------------------
		for _, group in ipairs(groups) do
			local code = CATEGORY_ANSI[group.category] or CATEGORY_ANSI.Other

			out[#out + 1] = ""

			if colour then
				out[#out + 1] = paint("1;" .. code,
						pad("[" .. group.category .. "]", COL_AMOUNT + COL_NAME + 1))
					.. paint("1;32", pad(comma(group.subtotal), COL_VALUE, true))
			else
				out[#out + 1] = pad("[" .. group.category:upper() .. "]", RICH_LEFT)
					.. pad(comma(group.subtotal), RICH_TOTAL, true)
			end

			for _, it in ipairs(group.items) do
				out[#out + 1] = colour and byItem[it].colour or byItem[it].rich
			end
		end

		-- ---------------------------------------------------------
		-- items with no price, and the closing total
		-- ---------------------------------------------------------
		if SHOW_UNPRICED and unknown and #unknown > 0 then
			out[#out + 1] = ""

			if colour then
				out[#out + 1] = paint("1;37",
						pad("[Not priced]", COL_AMOUNT + COL_NAME + 1))
					.. paint("0;37", pad(#unknown .. " types", COL_VALUE, true))
			else
				out[#out + 1] = pad("[NOT PRICED]", RICH_LEFT)
					.. pad(#unknown .. " types", RICH_TOTAL, true)
			end

			for _, it in ipairs(unknown) do
				out[#out + 1] = paint("0;37", colour
					and (" " .. pad(it.amount .. "x", COL_AMOUNT) .. it.name)
					or  ("  " .. pad(it.amount .. "x", COL_AMOUNT + 1) .. it.name))
			end
		end

		if colour then
			if close then out[#out + 1] = close end
		else
			out[#out + 1] = ""
			out[#out + 1] = string.rep("-", RICH_WIDTH)
			out[#out + 1] = pad("[TOTAL]", RICH_LEFT)
				.. pad(comma(total), RICH_TOTAL, true)
		end

		return table.concat(out, "\n")
	end

	if COPY_LONG == "plain"  then return assemble(false) end
	if COPY_LONG == "colour" then return assemble(true) end

	-- Windows puts \r\n in the clipboard where this wrote \n, so what
	-- Discord counts is one character longer per line than what is
	-- measured here. A small margin covers the difference.
	local function measure(text)
		local _, newlines = text:gsub("\n", "")
		return #text + newlines
	end

	local coloured = assemble(true)
	if measure(coloured) <= DISCORD_LIMIT - COPY_SAFETY then return coloured end

	-- Too long for one message. It is going to arrive as a file, and a
	-- file shows colour codes as text, so send it without them.
	return assemble(false)
end

-- Grouped by category, copyable
local function buildReport(items, owner, unknown)
	local grouped = {}
	for _, category in ipairs(CATEGORY_ORDER) do grouped[category] = {} end

	for _, it in ipairs(items) do
		local bucket = grouped[it.category] or grouped[CATEGORY_ORDER[1]]
		table.insert(bucket, it)
	end

	local lines, groups = {}, {}

	for _, category in ipairs(CATEGORY_ORDER) do
		local list = grouped[category]

		if #list > 0 then
			local subtotal, kinds, pieces = 0, 0, 0

			for _, it in ipairs(list) do
				subtotal = subtotal + it.value * it.amount
				kinds    = kinds + 1
				pieces   = pieces + it.amount
			end

			local hex = CATEGORY_COLOR_HEX[category] or CATEGORY_COLOR_HEX.Other

			local tag = (category == "Chroma")
				and (tint(hex, "[") .. rainbow("Chroma") .. tint(hex, "]"))
				or  tint(hex, bold("[" .. escapeRichText(category) .. "]"))

			local richHeading = tag .. "   " .. tint(DIM_COLOR_HEX, string.format(
				"%d types  ·  %d items  ·  ", kinds, pieces))
				.. tint(VALUE_COLOR_HEX, bold(comma(subtotal) .. " Value"))

			if #lines > 0 then table.insert(lines, "") end
			table.insert(lines, richHeading)

			table.insert(groups, {
				category = category,
				items    = list,
				subtotal = subtotal,
			})

			-- unit value too: what one of those 23 Harvesters is worth
			for _, it in ipairs(list) do
				table.insert(lines, "   "
					.. tint(DIM_COLOR_HEX, cell(it.amount .. "x", 4)) .. " "
					.. tint(hex, cell(it.name, 24)) .. " "
					.. tint(DIM_COLOR_HEX, cell(comma(it.value), 9, true))
					.. tint(DIM_COLOR_HEX, " ea ")
					.. tint(VALUE_COLOR_HEX, bold(cell(comma(it.value * it.amount), 10, true))))

			end
		end
	end

	-- Items the value table does not know. They carry no value, so they
	-- stay out of every total, but they are shown so a gap in the table
	-- is visible instead of looking like an empty inventory slot.
	if SHOW_UNPRICED and unknown and #unknown > 0 then
		local hex = CATEGORY_COLOR_HEX.Other

		if #lines > 0 then table.insert(lines, "") end
		table.insert(lines, tint(hex, bold("[Not priced]")) .. "   "
			.. tint(DIM_COLOR_HEX, #unknown .. " types  ·  no value in the table"))

		for _, it in ipairs(unknown) do
			table.insert(lines, "   "
				.. tint(DIM_COLOR_HEX, cell(it.amount .. "x", 4)) .. " "
				.. tint(hex, cell(it.name, 24)) .. " "
				.. tint(DIM_COLOR_HEX, cell("-", 9, true)))
		end
	end

	local total, kinds, pieces = totalsOf(items)

	return table.concat(lines, "\n"),
		buildCopy(groups, owner, total, kinds, pieces, unknown)
end

-- ===================================================================
-- STATE
-- ===================================================================
local measured   = {}   -- player name -> { items, total, kinds, pieces, at }
local activeName = nil  -- player shown on the Inventory page
local statusText = "Ready"
local logLines   = {}
local busy       = false
local ui         = {}

local function log(message)
	table.insert(logLines, "[" .. os.date("%H:%M:%S") .. "] " .. tostring(message))
	while #logLines > 16 do table.remove(logLines, 1) end
end

local function setStatus(message)
	statusText = tostring(message or "")
	log(statusText)
end

-- ===================================================================
-- TRADE WINDOW
--
-- MM2 does not send the live trade over a remote, so this reads the
-- trade window itself. It anchors on the two headers, YOUR OFFER and
-- THEIR OFFER, takes the frame that contains both of them, and splits
-- the item labels inside that frame by which header they sit under.
-- Anchoring on the shared parent is what keeps the inventory grid on
-- the left out of the count.
-- ===================================================================
-- Idle polling is slower on purpose: with no trade open there is
-- nothing to watch, and the panel should cost nothing while you play.
local TRADE_POLL_IDLE   = 1.2
local TRADE_POLL_ACTIVE = 0.4

local function textOf(obj)
	local ok, text = pcall(function() return obj.Text end)
	if not ok or type(text) ~= "string" then return "" end
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Visible on its own is not enough: a hidden parent hides the child
-- while the child still reports Visible = true.
local function onScreen(obj)
	local node = obj

	while node and node ~= PlayerGui do
		if node:IsA("ScreenGui") then
			if node.Enabled == false then return false end
		elseif node:IsA("GuiObject") then
			if node.Visible == false then return false end
		end
		node = node.Parent
	end

	return true
end

-- "x2", "2x" and "2" all mean the same thing in a slot corner.
local function quantityOf(text)
	local n = text:match("^[xX](%d+)$") or text:match("^(%d+)[xX]$")
	return tonumber(n)
end

-- Copying ImageLabel.Image alone is not enough. MM2 packs several icons
-- into one sprite sheet, so the crop rectangle has to come along or every
-- slot shows the same corner of the same sheet.
local function snapshotImage(obj)
	local data = {
		kind              = "imageData",
		id                = obj.Image,
		imageColor3       = obj.ImageColor3,
		imageTransparency = obj.ImageTransparency,
		imageRectOffset   = obj.ImageRectOffset,
		imageRectSize     = obj.ImageRectSize,
	}

	pcall(function() data.resampleMode = obj.ResampleMode end)
	return data
end

-- ===================================================================
-- ONE PASS OVER THE TRADE WINDOW
--
-- The earlier build walked the GUI tree once per item, and twice more
-- per item for the count and the picture. With eight slots that is over
-- twenty full walks every poll, which is where the stutter came from.
-- Now the tree is walked once, everything interesting is dropped into
-- three small lists, and each item is matched against those lists by
-- position. Cost stops growing with the number of items.
-- ===================================================================

-- Pictures and counts sit in the same column as the name and above it.
local function nearestInColumn(list, nameLabel, maxDrop)
	local nameCX = nameLabel.AbsolutePosition.X + nameLabel.AbsoluteSize.X / 2
	local nameY  = nameLabel.AbsolutePosition.Y

	local best, bestScore = nil, math.huge

	for _, entry in ipairs(list) do
		local obj = entry.obj
		local cx  = obj.AbsolutePosition.X + obj.AbsoluteSize.X / 2
		local cy  = obj.AbsolutePosition.Y + obj.AbsoluteSize.Y / 2

		local dx = math.abs(cx - nameCX)
		local dy = nameY - cy

		if dx <= 70 and dy >= -10 and dy <= maxDrop then
			local score = dx * 2 + math.abs(dy - 40)
			if score < bestScore then
				best, bestScore = entry, score
			end
		end
	end

	return best
end

-- The trade window lives in one ScreenGui. Remembering which one turns
-- the idle check into a small local scan instead of a walk of the whole
-- PlayerGui every poll.
local cachedYourAnchor, cachedTheirAnchor, cachedTradeScreen = nil, nil, nil
local lastFullScan = 0
local FULL_SCAN_GAP = 2.5

local function isOurs(obj)
	local node = obj
	while node do
		if node.Name == "MM2ValuePanel" then return true end
		node = node.Parent
	end
	return false
end

local function anchorValid(obj)
	if not obj or not obj.Parent then return false end
	if isOurs(obj) then return false end
	return onScreen(obj)
end

local function scanFor(container)
	local yours, theirs

	for _, obj in ipairs(container:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			local text = textOf(obj):lower()

			if not yours and text:find("your offer", 1, true) and onScreen(obj) then
				yours = obj
			elseif not theirs and text:find("their offer", 1, true) and onScreen(obj) then
				theirs = obj
			end

			if yours and theirs then break end
		end
	end

	return yours, theirs
end

local function findAnchors()
	if anchorValid(cachedYourAnchor) and anchorValid(cachedTheirAnchor) then
		return cachedYourAnchor, cachedTheirAnchor
	end

	cachedYourAnchor, cachedTheirAnchor = nil, nil

	-- cheap: look inside the window we already know about
	if cachedTradeScreen and cachedTradeScreen.Parent then
		local yours, theirs = scanFor(cachedTradeScreen)
		if yours and theirs then
			cachedYourAnchor, cachedTheirAnchor = yours, theirs
			return yours, theirs
		end
	end

	-- expensive: walk the whole PlayerGui, but only now and then
	if tick() - lastFullScan < FULL_SCAN_GAP then return nil end
	lastFullScan = tick()

	local yours, theirs
	for _, screen in ipairs(PlayerGui:GetChildren()) do
		if screen:IsA("ScreenGui") and screen.Name ~= "MM2ValuePanel" and screen.Enabled then
			yours, theirs = scanFor(screen)
			if yours and theirs then
				cachedTradeScreen = screen
				break
			end
		end
	end

	cachedYourAnchor, cachedTheirAnchor = yours, theirs
	return yours, theirs
end

local function ancestorsOf(obj)
	local set, node = {}, obj
	while node do
		set[node] = true
		node = node.Parent
	end
	return set
end

local function commonAncestor(a, b)
	local up = ancestorsOf(a)
	local node = b
	while node do
		if up[node] then return node end
		node = node.Parent
	end
	return nil
end

-- returns nil when no trade is open
local function readTrade(includeVisuals)
	local yours, theirs = findAnchors()
	if not yours or not theirs then return nil end

	local root = commonAncestor(yours, theirs)
	if not root then return nil end

	local mode = ui.iconMode or TRADE_ICON_MODE
	local wantVisuals = includeVisuals and mode ~= "off"

	local splitY   = theirs.AbsolutePosition.Y
	local leftEdge = math.min(yours.AbsolutePosition.X, theirs.AbsolutePosition.X) - 40

	local names, counts, pictures, badges = {}, {}, {}, {}
	local partner, mineAccepted, theirAccepted

	-- the single walk
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			local text = textOf(obj)

			if text ~= "" and onScreen(obj) then
				local count = quantityOf(text)

				if count then
					table.insert(counts, { obj = obj, amount = count })

				elseif text:lower():find("accepted", 1, true) then
					-- MM2 lays a green "YOU HAVE ACCEPTED." bar over the
					-- side that has accepted; which side is decided the
					-- same way the items are, by where it sits
					if obj.AbsolutePosition.Y >= splitY then
						theirAccepted = text
					else
						mineAccepted = text
					end

				elseif squash(text) == "chroma" then
					-- The trade card prints the word Chroma on a little
					-- badge of its own, above the name. The name label
					-- underneath just says "Beachy", so without this the
					-- card prices as the plain item.
					table.insert(badges, { obj = obj })

				else
					if not partner then
						partner = text:match("^%((.+)%)$")
					end

					if obj ~= yours and obj ~= theirs
					   and obj.AbsolutePosition.X >= leftEdge
					   and not HIDDEN_ITEMS[squash(text)] then
						table.insert(names, { obj = obj, text = text })
					end
				end
			end

		elseif wantVisuals and obj:IsA("GuiObject") then
			local w, h = obj.AbsoluteSize.X, obj.AbsoluteSize.Y

			-- big enough to be the item art, small enough not to be the
			-- window background
			if w >= 18 and h >= 18 and w <= 220 and h <= 220 and onScreen(obj) then
				if (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and obj.Image ~= "" then
					table.insert(pictures, { obj = obj, image = true })
				elseif obj:IsA("ViewportFrame") and mode == "full" then
					table.insert(pictures, { obj = obj, image = false })
				end
			end
		end
	end

	local mine, their = {}, {}

	for _, entry in ipairs(names) do
		-- A Chroma badge sits just above the name on the same card, so
		-- the chroma reading is tried first and the plain one is the
		-- fallback.
		local badge = nearestInColumn(badges, entry.obj, 70)
		local label = entry.text
		local value, category = 0, nil

		if badge then
			value, category = valueOf("Chroma " .. entry.text)
			if value > 0 then label = "Chroma " .. entry.text end
		end

		if value == 0 then
			value, category = valueOf(entry.text)
		end

		if value > 0 then
			local name  = displayName(label)
			local count = nearestInColumn(counts, entry.obj, 150)
			local visual = iconFor(name)

			if not visual and wantVisuals then
				local hit = nearestInColumn(pictures, entry.obj, 150)
				if hit then
					visual = hit.image and snapshotImage(hit.obj)
						or { kind = "viewport", source = hit.obj }
				end
			end

			local slot = {
				name     = name,
				amount   = count and count.amount or 1,
				value    = value,
				category = category or "Godly",
				visual   = visual,
			}

			if entry.obj.AbsolutePosition.Y >= splitY then
				table.insert(their, slot)
			else
				table.insert(mine, slot)
			end
		end
	end

	return {
		mine = mine, their = their, partner = partner,
		mineAccepted = mineAccepted, theirAccepted = theirAccepted,
	}
end

local function sumOf(list)
	local total, pieces = 0, 0
	for _, it in ipairs(list) do
		total  = total + it.value * it.amount
		pieces = pieces + it.amount
	end
	return total, pieces
end

-- Cheap way to notice "they just added something": fold the trade into
-- a string and compare it with the last one.
local function signatureOf(trade)
	if not trade then return "none" end

	local function fold(list)
		local parts = {}
		for _, it in ipairs(list) do
			table.insert(parts, it.amount .. "x" .. it.name)
		end
		table.sort(parts)
		return table.concat(parts, ",")
	end

	return (trade.partner or "?")
		.. "|" .. fold(trade.mine) .. "|" .. fold(trade.their)
		.. "|" .. tostring(trade.mineAccepted) .. "|" .. tostring(trade.theirAccepted)
end
-- Some MM2 screens claim a high layer of their own, so rather than
-- trusting one constant the panel checks what is actually on screen
-- and puts itself above it.
local function raiseAbove()
	if not ui.gui then return end

	local highest = PANEL_DISPLAY_ORDER

	for _, screen in ipairs(PlayerGui:GetChildren()) do
		if screen:IsA("ScreenGui") and screen ~= ui.gui then
			if screen.DisplayOrder > highest then
				highest = screen.DisplayOrder
			end
		end
	end

	if ui.gui.DisplayOrder <= highest then
		ui.gui.DisplayOrder = highest + 10
	end
end

-- ===================================================================
-- PANEL POSITION
-- ===================================================================
local function loadPosition()
	if isfile and readfile then
		local ok, raw = pcall(function()
			if isfile(PANEL_POS_FILE) then return readfile(PANEL_POS_FILE) end
		end)

		if ok and type(raw) == "string" and raw ~= "" then
			local okJson, d = pcall(function() return HttpService:JSONDecode(raw) end)
			if okJson and type(d) == "table"
			   and tonumber(d.xScale) and tonumber(d.xOffset)
			   and tonumber(d.yScale) and tonumber(d.yOffset) then
				return UDim2.new(d.xScale, d.xOffset, d.yScale, d.yOffset)
			end
		end
	end
	return UDim2.new(0.5, -380, 0.5, -250)
end

local function savePosition(pos)
	if not writefile then return end
	pcall(function()
		writefile(PANEL_POS_FILE, HttpService:JSONEncode({
			xScale = pos.X.Scale, xOffset = pos.X.Offset,
			yScale = pos.Y.Scale, yOffset = pos.Y.Offset,
		}))
	end)
end

-- ===================================================================
-- UI HELPERS
-- ===================================================================
local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

local function stroke(obj, colour)
	local s = Instance.new("UIStroke")
	s.Color = colour or C.stroke
	s.Thickness = 1
	s.Parent = obj
	return s
end

local function label(parent, name, text, pos, size, textSize, bold)
	local x = Instance.new("TextLabel")
	x.Name = name
	x.BackgroundTransparency = 1
	x.Position = pos
	x.Size = size
	x.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	x.Text = text
	x.TextColor3 = C.text
	x.TextSize = textSize or 13
	x.TextXAlignment = Enum.TextXAlignment.Left
	x.TextYAlignment = Enum.TextYAlignment.Center
	x.Parent = parent
	return x
end

local function button(parent, name, text, pos, size, colour)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = colour or C.neutral
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.Text = text
	b.TextColor3 = C.text
	b.TextSize = 12
	b.Parent = parent
	corner(b, 7)
	return b
end

local function card(parent, pos, size)
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = C.card
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 9)
	stroke(f)
	return f
end

local function safeSet(obj, prop, value)
	if not obj then return end
	pcall(function()
		if obj[prop] ~= value then obj[prop] = value end
	end)
end

-- ===================================================================
-- PANEL
-- ===================================================================
local function buildPanel()
	pcall(function()
		local old = PlayerGui:FindFirstChild("MM2ValuePanel")
		if old then old:Destroy() end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MM2ValuePanel"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = PANEL_DISPLAY_ORDER
	gui.Parent = PlayerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromOffset(760, 500)
	main.Position = loadPosition()
	main.BackgroundColor3 = C.bg
	main.BorderSizePixel = 0
	main.Parent = gui
	corner(main, 12)
	stroke(main, Color3.fromRGB(45, 46, 54))

	----------------------------------------------------------------
	-- HEADER
	----------------------------------------------------------------
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundColor3 = C.panel
	header.BorderSizePixel = 0
	header.Parent = main
	corner(header, 12)

	local title = label(header, "Title", "MM2 VALUE PANEL",
		UDim2.fromOffset(16, 0), UDim2.fromOffset(260, 52), 15, true)
	title.TextColor3 = Color3.fromRGB(210, 211, 220)

	ui.count = label(header, "Count", "", UDim2.new(1, -250, 0, 0),
		UDim2.fromOffset(160, 52), 11, false)
	ui.count.TextXAlignment = Enum.TextXAlignment.Right
	ui.count.TextColor3 = C.dim

	local minBtn   = button(header, "Min", "—", UDim2.new(1, -76, 0, 11), UDim2.fromOffset(28, 28))
	local closeBtn = button(header, "Close", "X", UDim2.new(1, -40, 0, 11), UDim2.fromOffset(28, 28))

	local body = Instance.new("Frame")
	body.Position = UDim2.fromOffset(0, 52)
	body.Size = UDim2.new(1, 0, 1, -52)
	body.BackgroundTransparency = 1
	body.Parent = main

	----------------------------------------------------------------
	-- SIDEBAR
	----------------------------------------------------------------
	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.fromOffset(170, 448)
	sidebar.BackgroundColor3 = C.panel
	sidebar.BorderSizePixel = 0
	sidebar.Parent = body

	local profile = Instance.new("Frame")
	profile.Position = UDim2.fromOffset(12, 14)
	profile.Size = UDim2.fromOffset(146, 76)
	profile.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	profile.BorderSizePixel = 0
	profile.Parent = sidebar
	corner(profile, 8)

	local avatar = Instance.new("ImageLabel")
	avatar.Size = UDim2.fromOffset(46, 46)
	avatar.Position = UDim2.fromOffset(10, 15)
	avatar.BackgroundColor3 = Color3.fromRGB(30, 31, 38)
	avatar.BorderSizePixel = 0
	avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150"
	avatar.Parent = profile
	corner(avatar, 8)

	local acc = label(profile, "Account", LocalPlayer.Name,
		UDim2.fromOffset(65, 12), UDim2.fromOffset(75, 24), 12, true)
	acc.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = label(profile, "Sub", "Value Reader",
		UDim2.fromOffset(65, 34), UDim2.fromOffset(75, 18), 10, false)
	sub.TextColor3 = C.dim

	local nav = Instance.new("Frame")
	nav.Position = UDim2.fromOffset(12, 105)
	nav.Size = UDim2.fromOffset(146, 240)
	nav.BackgroundTransparency = 1
	nav.Parent = sidebar

	local function navButton(name, text, y)
		local b = button(nav, name, text, UDim2.fromOffset(0, y), UDim2.fromOffset(146, 38), C.panel)
		b.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.Parent = b
		return b
	end

	local navPlayers = navButton("NavPlayers", "◆   Players", 0)
	local navInv     = navButton("NavInv",     "▣   Inventory",  46)
	local navValues  = navButton("NavValues",  "▤   Values",  92)
	local navTrade   = navButton("NavTrade",   "⇄   Trade",   138)
	local navLogs    = navButton("NavLogs",    "⚙   Logs",    184)

	local hint = label(sidebar, "Hint", "Right Shift\nShow / hide panel",
		UDim2.fromOffset(18, 382), UDim2.fromOffset(138, 44), 10, false)
	hint.TextColor3 = C.faint
	hint.TextYAlignment = Enum.TextYAlignment.Top

	----------------------------------------------------------------
	-- PAGES
	----------------------------------------------------------------
	local pages = Instance.new("Frame")
	pages.Position = UDim2.fromOffset(170, 0)
	pages.Size = UDim2.new(1, -170, 1, 0)
	pages.BackgroundColor3 = C.page
	pages.BorderSizePixel = 0
	pages.Parent = body

	local function newPage()
		local p = Instance.new("Frame")
		p.Size = UDim2.new(1, 0, 1, 0)
		p.BackgroundTransparency = 1
		p.Visible = false
		p.Parent = pages
		return p
	end

	local pagePlayers, pageInv, pageValues = newPage(), newPage(), newPage()
	local pageTrade, pageLogs = newPage(), newPage()
	local allPages = { pagePlayers, pageInv, pageValues, pageTrade, pageLogs }
	local allNav   = { navPlayers, navInv, navValues, navTrade, navLogs }

	local function pageTitle(parent, text, subtext)
		local t = label(parent, "PageTitle", text, UDim2.fromOffset(26, 18), UDim2.fromOffset(300, 28), 18, true)
		t.TextColor3 = Color3.fromRGB(222, 223, 230)
		local s = label(parent, "PageSub", subtext, UDim2.fromOffset(26, 45), UDim2.fromOffset(400, 20), 10, false)
		s.TextColor3 = Color3.fromRGB(115, 117, 130)
	end

	local function showPage(index)
		for i, p in ipairs(allPages) do p.Visible = (i == index) end
		for i, b in ipairs(allNav) do
			b.BackgroundColor3 = (i == index) and Color3.fromRGB(31, 32, 40) or C.panel
			b.TextColor3 = (i == index) and C.accent or Color3.fromRGB(165, 167, 180)
		end
	end

	----------------------------------------------------------------
	-- PLAYERS
	----------------------------------------------------------------
	pageTitle(pagePlayers, "Players", "Scan a player and read their inventory value")

	local topCard = card(pagePlayers, UDim2.fromOffset(26, 83), UDim2.fromOffset(519, 62))
	ui.serverTotal = label(topCard, "Total", "Server total: 0 Value",
		UDim2.fromOffset(14, 8), UDim2.fromOffset(330, 22), 13, true)
	ui.serverTotal.TextColor3 = C.greenTxt
	ui.serverSub = label(topCard, "Sub", "0 / 0 players scanned",
		UDim2.fromOffset(14, 32), UDim2.fromOffset(330, 18), 10, false)
	ui.serverSub.TextColor3 = C.dim

	local scanAllBtn = button(topCard, "ScanAll", "SCAN ALL",
		UDim2.fromOffset(356, 14), UDim2.fromOffset(148, 34), C.green)

	local playerList = Instance.new("ScrollingFrame")
	playerList.Position = UDim2.fromOffset(26, 157)
	playerList.Size = UDim2.fromOffset(519, 259)
	playerList.BackgroundColor3 = C.card
	playerList.BorderSizePixel = 0
	playerList.ScrollBarThickness = 5
	playerList.CanvasSize = UDim2.fromOffset(0, 0)
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.Parent = pagePlayers
	corner(playerList, 9)
	stroke(playerList)

	local playerLayout = Instance.new("UIListLayout")
	playerLayout.Padding = UDim.new(0, 6)
	playerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	playerLayout.Parent = playerList

	local playerPad = Instance.new("UIPadding")
	playerPad.PaddingTop = UDim.new(0, 8)
	playerPad.PaddingLeft = UDim.new(0, 8)
	playerPad.PaddingRight = UDim.new(0, 8)
	playerPad.PaddingBottom = UDim.new(0, 8)
	playerPad.Parent = playerList

	----------------------------------------------------------------
	-- INVENTORY
	----------------------------------------------------------------
	pageTitle(pageInv, "Inventory", "Item breakdown for the scanned player")

	local invTop = card(pageInv, UDim2.fromOffset(26, 83), UDim2.fromOffset(519, 76))
	ui.invWho = label(invTop, "Who", "No scan yet",
		UDim2.fromOffset(14, 10), UDim2.fromOffset(340, 22), 12, true)
	ui.invSummary = label(invTop, "Summary", "",
		UDim2.fromOffset(14, 34), UDim2.fromOffset(340, 18), 10, false)
	ui.invSummary.TextColor3 = C.dim

	local valueBox = Instance.new("Frame")
	valueBox.Position = UDim2.fromOffset(356, 21)
	valueBox.Size = UDim2.fromOffset(148, 34)
	valueBox.BackgroundColor3 = Color3.fromRGB(30, 31, 38)
	valueBox.BorderSizePixel = 0
	valueBox.Parent = invTop
	corner(valueBox, 7)
	stroke(valueBox, Color3.fromRGB(47, 49, 58))

	ui.invValue = label(valueBox, "Value", "0 Value",
		UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0), 12, true)
	ui.invValue.TextColor3 = C.greenTxt
	ui.invValue.RichText = true
	ui.invValue.TextXAlignment = Enum.TextXAlignment.Center

	local invList = Instance.new("ScrollingFrame")
	invList.Position = UDim2.fromOffset(26, 172)
	invList.Size = UDim2.fromOffset(519, 206)
	invList.BackgroundColor3 = C.card
	invList.BorderSizePixel = 0
	invList.ScrollBarThickness = 5
	invList.CanvasSize = UDim2.fromOffset(0, 0)
	invList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invList.Parent = pageInv
	corner(invList, 9)
	stroke(invList)

	ui.invText = label(invList, "Text", "Scan a player from the Players page.",
		UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 180), 11, false)
	ui.invText.Font = Enum.Font.Code
	ui.invText.TextYAlignment = Enum.TextYAlignment.Top
	ui.invText.TextWrapped = false
	ui.invText.AutomaticSize = Enum.AutomaticSize.Y
	ui.invText.TextColor3 = Color3.fromRGB(180, 182, 192)
	ui.invText.RichText = true

	local copyBtn = button(pageInv, "Copy", "COPY",
		UDim2.fromOffset(290, 388), UDim2.fromOffset(255, 30), C.blue)

	local learnAllBtn = button(pageInv, "LearnAll", "LEARN ALL",
		UDim2.fromOffset(26, 388), UDim2.fromOffset(255, 30), C.neutral)

	----------------------------------------------------------------
	-- VALUES
	----------------------------------------------------------------
	pageTitle(pageValues, "Values", "Search the value table")

	local searchBox = Instance.new("TextBox")
	searchBox.Position = UDim2.fromOffset(26, 83)
	searchBox.Size = UDim2.fromOffset(519, 34)
	searchBox.BackgroundColor3 = C.field
	searchBox.BorderSizePixel = 0
	searchBox.ClearTextOnFocus = false
	searchBox.Font = Enum.Font.Gotham
	searchBox.PlaceholderText = "Search item...  (Batwing, Chroma Raygun, Gingerscope)"
	searchBox.PlaceholderColor3 = C.dim
	searchBox.Text = ""
	searchBox.TextColor3 = C.text
	searchBox.TextSize = 12
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Parent = pageValues
	corner(searchBox, 7)

	local sPad = Instance.new("UIPadding")
	sPad.PaddingLeft = UDim.new(0, 10)
	sPad.Parent = searchBox

	local valuesList = Instance.new("ScrollingFrame")
	valuesList.Position = UDim2.fromOffset(26, 129)
	valuesList.Size = UDim2.fromOffset(519, 275)
	valuesList.BackgroundColor3 = C.card
	valuesList.BorderSizePixel = 0
	valuesList.ScrollBarThickness = 5
	valuesList.CanvasSize = UDim2.fromOffset(0, 0)
	valuesList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	valuesList.Parent = pageValues
	corner(valuesList, 9)
	stroke(valuesList)

	ui.valuesText = label(valuesList, "Text", "",
		UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 260), 11, false)
	ui.valuesText.Font = Enum.Font.Code
	ui.valuesText.TextYAlignment = Enum.TextYAlignment.Top
	ui.valuesText.AutomaticSize = Enum.AutomaticSize.Y
	ui.valuesText.TextColor3 = Color3.fromRGB(180, 182, 192)
	ui.valuesText.RichText = true

	local function refreshValues()
		local query = squash(searchBox.Text)
		local lines, shown = {}, 0

		for _, entry in ipairs(sortedItems) do
			if query == "" or squash(entry.name):find(query, 1, true) then
				shown = shown + 1
				local hex = CATEGORY_COLOR_HEX[entry.category] or CATEGORY_COLOR_HEX.Other
				table.insert(lines,
					tint(hex, cell(entry.name, 28)) .. " "
					.. tint(VALUE_COLOR_HEX, bold(cell(comma(entry.value), 10, true)))
					.. "   " .. tint(DIM_COLOR_HEX, escapeRichText(entry.category)))
				if shown >= 150 then break end
			end
		end

		safeSet(ui.valuesText, "Text",
			#lines > 0 and table.concat(lines, "\n")
				or tint(DIM_COLOR_HEX, "No matching items."))
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(refreshValues)

	local coverBtn = button(pageValues, "Cover", "UNMATCHED ITEMS",
		UDim2.fromOffset(26, 414), UDim2.fromOffset(180, 30), C.neutral)

	----------------------------------------------------------------
	-- TRADE
	----------------------------------------------------------------
	pageTitle(pageTrade, "Trade", "Reads the open trade window and prices both sides")

	local tradeTop = card(pageTrade, UDim2.fromOffset(26, 83), UDim2.fromOffset(519, 70))

	ui.tradeWho = label(tradeTop, "Who", "No trade open",
		UDim2.fromOffset(14, 9), UDim2.fromOffset(340, 22), 12, true)
	ui.tradeSub = label(tradeTop, "Sub", "Open a trade and the panel picks it up on its own",
		UDim2.fromOffset(14, 32), UDim2.fromOffset(340, 18), 10, false)
	ui.tradeSub.TextColor3 = C.dim

	local diffBox = Instance.new("Frame")
	diffBox.Position = UDim2.fromOffset(356, 18)
	diffBox.Size = UDim2.fromOffset(148, 34)
	diffBox.BackgroundColor3 = Color3.fromRGB(30, 31, 38)
	diffBox.BorderSizePixel = 0
	diffBox.Parent = tradeTop
	corner(diffBox, 7)
	stroke(diffBox, Color3.fromRGB(47, 49, 58))

	ui.tradeDiff = label(diffBox, "Diff", "—",
		UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0), 12, true)
	ui.tradeDiff.TextColor3 = C.dim
	ui.tradeDiff.RichText = true
	ui.tradeDiff.TextXAlignment = Enum.TextXAlignment.Center

	----------------------------------------------------------------
	-- OFFER SLOTS
	-- Same shape as the game's trade window: four boxes a side, the
	-- name on a coloured strip along the bottom and the stack count in
	-- the corner, so the panel reads like the thing it is mirroring.
	----------------------------------------------------------------
	local SLOT_COUNT = 4
	local SLOT_W, SLOT_H, SLOT_GAP = 121, 86, 11

	local function buildSlot(parent, index)
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. index
		slot.Position = UDim2.fromOffset((index - 1) * (SLOT_W + SLOT_GAP), 0)
		slot.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
		slot.BackgroundColor3 = Color3.fromRGB(26, 27, 33)
		slot.BorderSizePixel = 0
		slot.ClipsDescendants = true
		slot.Parent = parent
		corner(slot, 7)

		local edge = stroke(slot, Color3.fromRGB(45, 46, 54))

		-- the picture sits under everything else and fills the card
		-- above the name strip
		local art = Instance.new("Frame")
		art.Name = "Art"
		art.Position = UDim2.fromOffset(0, 0)
		art.Size = UDim2.new(1, 0, 1, -20)
		art.BackgroundTransparency = 1
		art.ClipsDescendants = true
		art.Parent = slot

		-- a square host, so item art does not come out stretched inside
		-- a card that is wider than it is tall
		local host = Instance.new("Frame")
		host.Name = "VisualHost"
		host.AnchorPoint = Vector2.new(0.5, 0.5)
		host.Position = UDim2.fromScale(0.5, 0.46)
		host.Size = UDim2.new(1, -8, 1, -10)
		host.BackgroundTransparency = 1
		host.ClipsDescendants = true
		host.Parent = art

		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.DominantAxis = Enum.DominantAxis.Height
		ratio.Parent = host

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = ""
		icon.Parent = host

		local amount = label(slot, "Amount", "",
			UDim2.fromOffset(0, 4), UDim2.new(1, -7, 0, 14), 11, true)
		amount.TextXAlignment = Enum.TextXAlignment.Right
		amount.TextColor3 = Color3.fromRGB(255, 255, 255)
		amount.TextStrokeTransparency = 0.4
		amount.ZIndex = 4

		-- a dark bar keeps the number readable over the picture
		local valueBar = Instance.new("Frame")
		valueBar.Name = "ValueBar"
		valueBar.Position = UDim2.new(0, 0, 1, -40)
		valueBar.Size = UDim2.new(1, 0, 0, 20)
		valueBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		valueBar.BackgroundTransparency = 0.45
		valueBar.BorderSizePixel = 0
		valueBar.ZIndex = 3
		valueBar.Parent = slot

		local value = label(valueBar, "Value", "—",
			UDim2.fromOffset(4, 0), UDim2.new(1, -8, 1, 0), 12, true)
		value.TextXAlignment = Enum.TextXAlignment.Center
		value.TextColor3 = C.faint
		value.ZIndex = 4

		local strip = Instance.new("Frame")
		strip.Name = "Strip"
		strip.Position = UDim2.new(0, 0, 1, -20)
		strip.Size = UDim2.new(1, 0, 0, 20)
		strip.BackgroundColor3 = Color3.fromRGB(34, 35, 42)
		strip.BorderSizePixel = 0
		strip.ZIndex = 3
		strip.Parent = slot

		local nameLabel = label(strip, "Name", "empty",
			UDim2.fromOffset(4, 0), UDim2.new(1, -8, 1, 0), 10, true)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextColor3 = C.faint
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 4

		return {
			frame = slot, edge = edge, art = art, host = host, icon = icon,
			amount = amount, valueBar = valueBar, value = value,
			strip = strip, name = nameLabel,
		}
	end

	-- A cloned preview has to be re-pointed at its own camera, otherwise
	-- it renders empty. Clones are cached, and a slot does no work at all
	-- when the picture it is already showing is the right one.
	local viewportCache = {}

	local function resetIcon(icon)
		icon.Image = ""
		icon.ImageColor3 = Color3.new(1, 1, 1)
		icon.ImageTransparency = 0
		icon.ImageRectOffset = Vector2.new(0, 0)
		icon.ImageRectSize = Vector2.new(0, 0)
		icon.ScaleType = Enum.ScaleType.Fit
	end

	-- The crop rectangle is the part that matters: without it every slot
	-- shows the same corner of MM2's sprite sheet.
	local function applyImageData(icon, visual)
		icon.Image = visual.id or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ImageColor3 = visual.imageColor3 or Color3.new(1, 1, 1)
		icon.ImageTransparency = visual.imageTransparency or 0
		icon.ImageRectOffset = visual.imageRectOffset or Vector2.new(0, 0)
		icon.ImageRectSize = visual.imageRectSize or Vector2.new(0, 0)

		if visual.resampleMode ~= nil then
			pcall(function() icon.ResampleMode = visual.resampleMode end)
		end
	end

	local function visualKeyOf(name, visual)
		if not visual then return name .. "|none" end

		if visual.kind == "image" then
			return name .. "|asset|" .. tostring(visual.id)
		elseif visual.kind == "imageData" then
			return name .. "|img|" .. tostring(visual.id)
				.. "|" .. tostring(visual.imageRectOffset)
				.. "|" .. tostring(visual.imageRectSize)
		end

		return name .. "|vp|" .. tostring(visual.source)
	end

	local function showVisual(slot, visual, name)
		local key = visualKeyOf(name or "", visual)
		if slot.visualKey == key then return end
		slot.visualKey = key

		resetIcon(slot.icon)

		for _, child in ipairs(slot.host:GetChildren()) do
			if child ~= slot.icon then child.Parent = nil end
		end

		if not visual then return end

		if visual.kind == "image" then
			slot.icon.Image = visual.id
			return
		end

		if visual.kind == "imageData" then
			applyImageData(slot.icon, visual)
			return
		end

		if not visual.source then return end

		local clone = viewportCache[key]

		if not clone then
			local ok, made = pcall(function()
				local wasArchivable = visual.source.Archivable
				visual.source.Archivable = true
				local c = visual.source:Clone()
				visual.source.Archivable = wasArchivable
				return c
			end)
			if not ok or not made then return end

			made.Name = "ItemViewport"
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.Position = UDim2.fromScale(0.5, 0.5)
			made.Size = UDim2.fromScale(1, 1)
			made.BackgroundTransparency = 1
			made.Visible = true

			-- a clone can still be pointing at the original's camera
			local cloned = made:FindFirstChildWhichIsA("Camera", true)
			if cloned then
				pcall(function() made.CurrentCamera = cloned end)
			elseif visual.source.CurrentCamera then
				local okCam, cam = pcall(function()
					return visual.source.CurrentCamera:Clone()
				end)
				if okCam and cam then
					cam.Parent = made
					made.CurrentCamera = cam
				end
			end

			viewportCache[key] = made
			clone = made
		end

		clone.Parent = slot.host
	end

	local function buildSide(title, y)
		local head = label(pageTrade, "Head", title,
			UDim2.fromOffset(26, y), UDim2.fromOffset(300, 18), 11, true)
		head.TextColor3 = Color3.fromRGB(205, 207, 216)

		local sum = label(pageTrade, "Sum", "0 items  ·  0 Value",
			UDim2.fromOffset(245, y), UDim2.fromOffset(300, 18), 11, true)
		sum.TextXAlignment = Enum.TextXAlignment.Right
		sum.RichText = true
		sum.TextColor3 = C.dim

		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(26, y + 22)
		row.Size = UDim2.fromOffset(519, SLOT_H)
		row.BackgroundTransparency = 1
		row.Parent = pageTrade

		local slots = {}
		for i = 1, SLOT_COUNT do slots[i] = buildSlot(row, i) end

		-- the same green bar MM2 lays over an accepted offer
		local banner = Instance.new("Frame")
		banner.Name = "Accepted"
		banner.AnchorPoint = Vector2.new(0.5, 0.5)
		banner.Position = UDim2.fromScale(0.5, 0.5)
		banner.Size = UDim2.new(1, 0, 0, 26)
		banner.BackgroundColor3 = Color3.fromRGB(8, 10, 9)
		banner.BackgroundTransparency = 0.55
		banner.BorderSizePixel = 0
		banner.Visible = false
		banner.ZIndex = 8
		banner.Parent = row

		local bannerText = label(banner, "Text", "", UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 1, 0), 13, true)
		bannerText.TextXAlignment = Enum.TextXAlignment.Center
		bannerText.TextColor3 = Color3.fromRGB(80, 235, 120)
		bannerText.ZIndex = 9

		return { head = head, sum = sum, slots = slots,
		         banner = banner, bannerText = bannerText }
	end

	local mySide    = buildSide("YOUR OFFER",  166)
	local theirSide = buildSide("THEIR OFFER", 280)

	-- Watching and the icon mode were buttons that only ever sat on one
	-- setting, so they are just that setting now.
	local tradeCopyBtn = button(pageTrade, "TradeCopy", "COPY",
		UDim2.fromOffset(26, 396), UDim2.fromOffset(160, 30), C.blue)

	----------------------------------------------------------------
	-- TRADE RENDERING
	----------------------------------------------------------------
	local function clearSlot(slot)
		showVisual(slot, nil, "")
		safeSet(slot.amount, "Text", "")
		safeSet(slot.value, "Text", "—")
		slot.value.TextColor3 = C.faint
		slot.valueBar.BackgroundTransparency = 1
		safeSet(slot.name, "Text", "empty")
		slot.name.TextColor3 = C.faint
		slot.strip.BackgroundColor3 = Color3.fromRGB(34, 35, 42)
		slot.frame.BackgroundColor3 = Color3.fromRGB(22, 23, 28)
		slot.edge.Color = Color3.fromRGB(40, 41, 48)
	end

	local function fillSlot(slot, item)
		local tone = CATEGORY_COLOR3[item.category] or CATEGORY_COLOR3.Other

		showVisual(slot, item.visual, item.name)

		safeSet(slot.amount, "Text", item.amount > 1 and ("x" .. item.amount) or "")
		safeSet(slot.value, "Text", item.amount > 1
			and (comma(item.value * item.amount) .. "   " .. comma(item.value) .. " ea")
			or comma(item.value))
		slot.value.TextColor3 = C.greenTxt
		slot.valueBar.BackgroundTransparency = item.visual and 0.45 or 1
		safeSet(slot.name, "Text", item.name)
		slot.name.TextColor3 = Color3.fromRGB(255, 255, 255)
		slot.strip.BackgroundColor3 = tone
		slot.frame.BackgroundColor3 = Color3.fromRGB(26, 27, 33)
		slot.edge.Color = tone
	end

	-- Four boxes, so anything past the fourth is folded into the last.
	local function paintSide(side, list, title)
		table.sort(list, function(a, b)
			return a.value * a.amount > b.value * b.amount
		end)

		local total, pieces = sumOf(list)

		safeSet(side.head, "Text", title)
		safeSet(side.sum, "Text", tint(DIM_COLOR_HEX, pieces .. " items  ·  ")
			.. tint(VALUE_COLOR_HEX, bold(comma(total) .. " Value")))

		for i = 1, SLOT_COUNT do
			local slot = side.slots[i]

			if list[i] and (i < SLOT_COUNT or #list == SLOT_COUNT) then
				fillSlot(slot, list[i])
			elseif list[i] then
				-- more items than boxes: roll the rest into the last one
				local rest, restValue = 0, 0
				for j = SLOT_COUNT, #list do
					rest = rest + list[j].amount
					restValue = restValue + list[j].value * list[j].amount
				end
				fillSlot(slot, {
					name = "+" .. (#list - SLOT_COUNT + 1) .. " more",
					amount = rest, value = math.floor(restValue / math.max(rest, 1)),
					category = "Other",
				})
				safeSet(slot.value, "Text", comma(restValue))
			else
				clearSlot(slot)
			end
		end

		return total
	end

	local lastTradeCopy = ""

	local function renderTrade(trade)
		if not trade then
			safeSet(ui.tradeWho, "Text", "No trade open")
			safeSet(ui.tradeSub, "Text", "Open a trade and the panel picks it up on its own")
			safeSet(ui.tradeDiff, "Text", tint(DIM_COLOR_HEX, "—"))

			for _, side in ipairs({ theirSide, mySide }) do
				for i = 1, SLOT_COUNT do clearSlot(side.slots[i]) end
				safeSet(side.sum, "Text", tint(DIM_COLOR_HEX, "0 items  ·  0 Value"))
				safeSet(side.banner, "Visible", false)
			end

			safeSet(mySide.head, "Text", "YOUR OFFER")
			safeSet(theirSide.head, "Text", "THEIR OFFER")
			lastTradeCopy = ""
			return
		end

		local function setAccepted(side, text)
			safeSet(side.bannerText, "Text", text and text:upper() or "")
			safeSet(side.banner, "Visible", text ~= nil)
		end

		setAccepted(mySide, trade.mineAccepted)
		setAccepted(theirSide, trade.theirAccepted)

		local theirTotal = paintSide(theirSide, trade.their,
			"THEIR OFFER" .. (trade.partner and ("   (" .. trade.partner .. ")") or ""))
		local myTotal = paintSide(mySide, trade.mine, "YOUR OFFER")

		local diff = theirTotal - myTotal
		local hex  = (diff > 0 and TOTAL_COLOR_HEX) or (diff < 0 and "#FF6B6B") or DIM_COLOR_HEX
		local sign = (diff > 0 and "+") or ""

		safeSet(ui.tradeWho, "Text", trade.partner
			and ("Trading with " .. trade.partner) or "Trade open")
		safeSet(ui.tradeSub, "Text", string.format("They offer %s  ·  you offer %s",
			comma(theirTotal), comma(myTotal)))
		safeSet(ui.tradeDiff, "Text", tint(hex, bold(sign .. comma(diff))))

		----------------------------------------------------------
		-- clipboard copy, still plain text
		----------------------------------------------------------
		local copy = {}

		local function block(title, list)
			local total, pieces = sumOf(list)
			table.insert(copy, string.format("%s  (%d items, %s Value)", title, pieces, comma(total)))
			if #list == 0 then
				table.insert(copy, "   empty")
			else
				for _, it in ipairs(list) do
					table.insert(copy, string.format("   %s %s %s",
						pad(it.amount .. "x", 4), pad(it.name, 22),
						pad(comma(it.value * it.amount), 10, true)))
				end
			end
		end

		-- your side first, the same order the page shows
		block("YOUR OFFER", trade.mine)
		table.insert(copy, "")
		block("THEIR OFFER" .. (trade.partner and ("  (" .. trade.partner .. ")") or ""), trade.their)
		table.insert(copy, "")
		table.insert(copy, string.format("%s%s Value %s",
			sign, comma(diff), diff >= 0 and "in your favour" or "against you"))

		local head = (COPY_STYLE == "ansi" and "```ansi\n")
			or (COPY_STYLE == "code" and "```\n") or ""
		local tail = (COPY_STYLE ~= "plain") and "\n```" or ""
		lastTradeCopy = head .. table.concat(copy, "\n") .. tail
	end

	renderTrade(nil)

	tradeCopyBtn.MouseButton1Click:Connect(function()
		if lastTradeCopy == "" then
			setStatus("No trade to copy")
			return
		end
		if not setclipboard then
			setStatus("Executor has no setclipboard")
			return
		end
		local ok = pcall(setclipboard, lastTradeCopy)
		setStatus(ok and "Trade copied" or "Copy failed")
	end)

	ui.tradeWatching = true
	ui.iconMode = TRADE_ICON_MODE

	ui.renderTrade = renderTrade
	ui.showPage    = showPage
	----------------------------------------------------------------
	-- LOGS
	----------------------------------------------------------------
	pageTitle(pageLogs, "Logs", "Recent activity")

	local logCard = card(pageLogs, UDim2.fromOffset(26, 83), UDim2.fromOffset(519, 333))
	ui.logText = label(logCard, "Text", "", UDim2.fromOffset(14, 14), UDim2.new(1, -28, 1, -28), 11, false)
	ui.logText.TextYAlignment = Enum.TextYAlignment.Top
	ui.logText.TextWrapped = true
	ui.logText.TextColor3 = Color3.fromRGB(180, 182, 192)
	ui.logText.RichText = true
	ui.logText.Font = Enum.Font.Code

	----------------------------------------------------------------
	-- PLAYER ROWS
	----------------------------------------------------------------
	local showInventory   -- forward declaration
	local refreshPlayers

	local function scanPlayer(player)
		if busy then
			setStatus("A scan is already running")
			return false, "busy"
		end

		busy = true
		setStatus("Scanning: " .. player.Name)

		local items, reason, unknown = readInventory(player)
		busy = false

		if not items then
			setStatus(player.Name .. " could not be read: " .. tostring(reason))
			return false, reason
		end

		local total, kinds, pieces = totalsOf(items)
		local report, copyText = buildReport(items, player.Name, unknown)

		measured[player.Name] = {
			items  = items,
			total  = total,
			kinds  = kinds,
			pieces = pieces,
			report = report,
			copy   = copyText,
			unknown = unknown,
			at     = os.time(),
		}

		activeName = player.Name
		setStatus(player.Name .. ": " .. comma(total) .. " Value  (" ..
			kinds .. " types, " .. pieces .. " items)")

		refreshPlayers()
		showInventory()
		return true
	end

	showInventory = function()
		local rec = activeName and measured[activeName]

		if not rec then
			safeSet(ui.invWho, "Text", "No scan yet")
			safeSet(ui.invSummary, "Text", "")
			safeSet(ui.invValue, "Text", tint(DIM_COLOR_HEX, "0 Value"))
			safeSet(ui.invText, "Text",
				tint(DIM_COLOR_HEX, "Scan a player from the Players page."))
			return
		end

		safeSet(ui.invWho, "Text", activeName)
		local extra = (rec.unknown and #rec.unknown > 0)
			and ("  ·  " .. #rec.unknown .. " not priced") or ""
		safeSet(ui.invSummary, "Text",
			rec.kinds .. " types  ·  " .. rec.pieces .. " items" .. extra)
		safeSet(ui.invValue, "Text",
			tint(TOTAL_COLOR_HEX, bold(comma(rec.total))) .. tint(DIM_COLOR_HEX, " Value"))
		safeSet(ui.invText, "Text", rec.report)
	end

	refreshPlayers = function()
		for _, child in ipairs(playerList:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end

		local players = Players:GetPlayers()

		table.sort(players, function(a, b)
			local av = measured[a.Name] and measured[a.Name].total or -1
			local bv = measured[b.Name] and measured[b.Name].total or -1
			if av == bv then return a.Name:lower() < b.Name:lower() end
			return av > bv
		end)

		local serverTotal, known = 0, 0

		for index, player in ipairs(players) do
			local rec = measured[player.Name]
			if rec then
				serverTotal = serverTotal + rec.total
				known = known + 1
			end

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 46)
			row.BackgroundColor3 = Color3.fromRGB(30, 31, 38)
			row.BorderSizePixel = 0
			row.LayoutOrder = index
			row.Parent = playerList
			corner(row, 7)

			local nameText = player.Name
			if player == LocalPlayer then nameText = nameText .. "   (you)" end

			local n = label(row, "Name", nameText, UDim2.fromOffset(12, 5),
				UDim2.fromOffset(200, 20), 12, true)
			n.TextTruncate = Enum.TextTruncate.AtEnd

			local info = rec
				and (rec.kinds .. " types  ·  " .. rec.pieces .. " items")
				or "not scanned"

			local s = label(row, "Sub", info, UDim2.fromOffset(12, 24),
				UDim2.fromOffset(200, 16), 10, false)
			s.TextColor3 = C.dim

			local v = label(row, "Value", rec and (comma(rec.total) .. " Value") or "-",
				UDim2.fromOffset(222, 0), UDim2.fromOffset(130, 46), 12, true)
			v.TextXAlignment = Enum.TextXAlignment.Right
			v.TextColor3 = rec and C.greenTxt or C.dim

			local scanBtn = button(row, "Scan", "scan",
				UDim2.new(1, -112, 0.5, -13), UDim2.fromOffset(50, 26), C.green)

			scanBtn.MouseButton1Click:Connect(function()
				if scanBtn.Text == ".." then return end
				scanBtn.Text = ".."
				task.spawn(function()
					local ok, reason = scanPlayer(player)
					if scanBtn.Parent then
						scanBtn.Text = ok and "ok" or (reason or "error")
						task.delay(1.5, function()
							if scanBtn.Parent then scanBtn.Text = "scan" end
						end)
					end
				end)
			end)

			local openBtn = button(row, "Open", "open",
				UDim2.new(1, -56, 0.5, -13), UDim2.fromOffset(44, 26), C.neutral)

			openBtn.MouseButton1Click:Connect(function()
				if not measured[player.Name] then
					setStatus(player.Name .. " has not been scanned yet")
					return
				end
				activeName = player.Name
				showInventory()
				showPage(2)
			end)
		end

		safeSet(ui.serverTotal, "Text", "Server total: " .. comma(serverTotal) .. " Value")
		safeSet(ui.serverSub, "Text", known .. " / " .. #players .. " players scanned")
	end

	-- Scans one after another with a gap between players rather than
	-- firing the calls back to back.
	scanAllBtn.MouseButton1Click:Connect(function()
		if scanAllBtn.Text ~= "SCAN ALL" then return end
		scanAllBtn.Text = "SCANNING..."

		task.spawn(function()
			for _, player in ipairs(Players:GetPlayers()) do
				scanPlayer(player)
				task.wait(1.2)
			end
			scanAllBtn.Text = "SCAN ALL"
			setStatus("Scan all finished")
		end)
	end)

	copyBtn.MouseButton1Click:Connect(function()
		local rec = activeName and measured[activeName]

		if not rec then
			setStatus("Nothing to copy")
			return
		end

		if not setclipboard then
			setStatus("Executor has no setclipboard")
			return
		end

		local ok = pcall(setclipboard, rec.copy)

		if not ok then
			setStatus("Copy failed")
			return
		end

		local size = #rec.copy

		-- Past the limit Discord turns the paste into a file. That is
		-- fine, the text is already plain in that case, but say which
		-- one is coming so it is not a surprise.
		if size > DISCORD_LIMIT then
			setStatus(string.format("%s copied - %d chars, Discord will send it as a file",
				activeName, size))
		else
			setStatus(string.format("%s copied - %d chars, fits one message",
				activeName, size))
		end
	end)

	-- The remote answers with MM2's internal names (Sorry, AuroraGun),
	-- while the inventory window shows the names players use (Corrupt,
	-- Borealis). The card's own object is usually named after the
	-- internal name, so with the window open the two can be paired up
	-- and the missing aliases read straight off the screen.
	-- Reads every item card on screen and pairs the card's object name
	-- (MM2's internal name) with the label printed on it (the name
	-- players use). Anything learned is written to disk, so the panel
	-- can price that item from then on without ever having owned it.
	-- Looking at another trader's inventory teaches it their items too.
	-- MM2 has to keep its own list of every weapon somewhere, and that
	-- list is the complete answer: no scrolling, no screenshots, no
	-- waiting to meet someone who owns the item. Two places are worth
	-- looking.
	--
	-- Only modules whose name suggests data are opened. Requiring an
	-- arbitrary module can run its code or block forever, so behaviour
	-- modules are left alone.
	local DATA_MODULE_HINTS = {
		"item", "weapon", "knife", "gun", "value", "shop",
		"unbox", "crate", "info", "list", "data", "catalog",
	}

	local DISPLAY_FIELDS = {
		"DisplayName", "Display", "Name", "Title", "ItemName", "Label",
	}

	local function looksLikeData(name)
		local lower = name:lower()
		for _, hint in ipairs(DATA_MODULE_HINTS) do
			if lower:find(hint, 1, true) then return true end
		end
		return false
	end

	-- a pair is only kept when the caption is an item the value table
	-- knows and the key is not already understood
	local function offer(key, display, found)
		if type(key) ~= "string" or type(display) ~= "string" then return found end
		if #key < 3 or #key > 40 or #display < 2 or #display > 40 then return found end
		if not resolveDirect(display) then return found end
		if resolve(key) then return found end

		local squashed = squash(key)
		if learned[squashed] == display then return found end

		learned[squashed] = display
		return found + 1
	end

	local function captionOf(entry)
		if type(entry) == "string" then return entry end
		if type(entry) ~= "table" then return nil end

		for _, field in ipairs(DISPLAY_FIELDS) do
			if type(entry[field]) == "string" then return entry[field] end
		end

		return nil
	end

	-- MM2 keeps every weapon it has ever made in Database/Sync/Item,
	-- about a thousand of them, each one shaped like this:
	--
	--   ["AuroraGun"] = { ItemName = "Borealis", ItemType = "Gun",
	--                     Rarity = "Godly", ItemID = ... }
	--
	-- That is the whole answer to the naming problem, straight from the
	-- game. No scrolling an inventory, no waiting to meet someone who
	-- owns the item.
	--
	-- Pairs from here are trusted without checking the caption against
	-- the value table, which is what the screen harvest has to do. This
	-- is the game's own record, not a guess about what a frame contains,
	-- and a name learned now is still useful later, when the item
	-- finally gets a value.
	local function learnFromGame()
		local found, entries, modules = 0, 0, 0

		for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
			if obj:IsA("ModuleScript") and looksLikeData(obj.Name) and modules < 60 then
				modules = modules + 1

				local ok, data = pcall(require, obj)

				if ok and type(data) == "table" then
					for key, entry in pairs(data) do
						if type(key) == "string" and type(entry) == "table"
						   and type(entry.ItemName) == "string" then

							entries = entries + 1

							-- MM2 says what tier each item is, which is a
							-- better answer than guessing from the name
							if type(entry.Rarity) == "string" then
								rarityOf[squash(key)] = entry.Rarity
							end

							local display = entry.ItemName

							-- A chroma is listed under the plain item's
							-- name. Filing that pair would teach the panel
							-- the wrong price, so it is either corrected
							-- to the chroma or left to the chroma rule.
							if squash(key):find("chroma", 1, true)
							   and not squash(display):find("chroma", 1, true) then
								if resolveDirect("Chroma " .. display) then
									display = "Chroma " .. display
								else
									display = nil
								end
							end

							if display and squash(key) ~= squash(display)
							   and #key > 1 and #display > 1
							   and learned[squash(key)] ~= display then
								learned[squash(key)] = display
								found = found + 1
							end
						end
					end
				end
			end
		end

		return found, entries
	end

	-- The other direction. LEARN ALL answers "what does this internal
	-- name mean"; this answers "which of my 190 priced items does the
	-- game never actually produce a name for". Those are the entries
	-- that can never be matched, so they are the ones to check: a
	-- renamed item, a typo, or a weapon that no longer exists.
	local function unmatchedItems()
		local reachable, byName, scanned = {}, {}, 0

		for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
			if obj:IsA("ModuleScript") and looksLikeData(obj.Name) then
				local ok, data = pcall(require, obj)

				if ok and type(data) == "table" then
					for key, entry in pairs(data) do
						if type(key) == "string" and type(entry) == "table"
						   and type(entry.ItemName) == "string" then

							scanned = scanned + 1

							-- what the game calls this item, so a missing
							-- entry can be shown next to the keys that do
							-- print the same name
							local printed = squash(entry.ItemName)
							byName[printed] = byName[printed] or {}

							if #byName[printed] < 6 then
								table.insert(byName[printed],
									key .. " [" .. tostring(entry.Rarity or "?") .. "]")
							end

							for _, candidate in ipairs({ key, entry.ItemName }) do
								local hit = resolveTiered(candidate)
								if hit then reachable[hit] = true end
							end
						end
					end
				end
			end
		end

		local missing = {}

		for name in pairs(DATA.values) do
			if not reachable[squash(name)] then
				-- "Chroma Ornament" is listed in the game under whatever
				-- Ornament is called, so look the base name up too
				local base = name:match("^(.-)|") or name
				base = base:match("^[Cc]hroma%s+(.+)$") or base

				table.insert(missing, {
					name = name,
					value = DATA.values[name],
					category = DATA.cats[name] or "?",
					seen = byName[squash(base)],
				})
			end
		end

		table.sort(missing, function(a, b)
			if a.value == b.value then return a.name < b.name end
			return a.value > b.value
		end)

		return missing, scanned
	end

	coverBtn.MouseButton1Click:Connect(function()
		coverBtn.Text = "CHECKING..."

		task.spawn(function()
			local ok, missing, scanned = pcall(unmatchedItems)

			coverBtn.Text = "UNMATCHED ITEMS"

			if not ok then
				setStatus("Could not read the game's item list")
				return
			end

			if scanned == 0 then
				setStatus("No item list found - press LEARN ALL first")
				return
			end

			local total = 0
			for _ in pairs(DATA.values) do total = total + 1 end

			if #missing == 0 then
				setStatus(string.format("All %d priced items appear in the game (%d entries checked)",
					total, scanned))
				return
			end

			local lines = {}
			table.insert(lines, string.format("%d of %d priced items never appear in the game's list:",
				#missing, total))

			for _, row in ipairs(missing) do
				table.insert(lines, string.format("  %-24s %8s   %s",
					row.name, comma(row.value), row.category))

				if row.seen then
					table.insert(lines, "      game lists: "
						.. table.concat(row.seen, ", "))
				else
					table.insert(lines, "      game lists: nothing by that name")
				end
			end

			local text = table.concat(lines, "\n")

			if setclipboard then pcall(setclipboard, text) end

			setStatus(string.format("%d of %d priced items unmatched - copied",
				#missing, total))
		end)
	end)

	-- When the guess finds nothing, the useful thing is not another
	-- guess but a look inside the modules that hold the data. MM2 keeps
	-- its item list in Database/Sync/Item, so the shape of one entry is
	-- all that is needed to read the whole thing.
	local function shortValue(value)
		local kind = type(value)

		if kind == "string" then
			return '"' .. (#value > 28 and (value:sub(1, 28) .. "...") or value) .. '"'
		elseif kind == "number" or kind == "boolean" then
			return tostring(value)
		elseif kind == "table" then
			local n = 0
			for _ in pairs(value) do n = n + 1 end
			return "{" .. n .. " fields}"
		end

		return kind
	end

	local function describeModules()
		local out = {}
		local function w(line) table.insert(out, line) end

		local function pathOf(obj)
			local parts, node, depth = {}, obj, 0
			while node and node ~= ReplicatedStorage and depth < 8 do
				table.insert(parts, 1, node.Name)
				node = node.Parent
				depth = depth + 1
			end
			return table.concat(parts, "/")
		end

		local looked = 0

		for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
			if obj:IsA("ModuleScript") and looksLikeData(obj.Name) and looked < 20 then
				looked = looked + 1

				local path = pathOf(obj)
				local ok, data = pcall(require, obj)

				if not ok then
					w(path .. "  ->  could not be read")

				elseif type(data) ~= "table" then
					w(path .. "  ->  " .. type(data))

				else
					local keys = {}
					for key in pairs(data) do table.insert(keys, tostring(key)) end
					table.sort(keys)

					w(string.format("%s  ->  table, %d keys", path, #keys))

					-- a handful of keys, and the fields of the first
					-- couple of entries that are themselves tables
					local sample = {}
					for i = 1, math.min(8, #keys) do table.insert(sample, keys[i]) end
					w("   keys: " .. table.concat(sample, ", "))

					local shown = 0

					for _, key in ipairs(keys) do
						local entry = data[key]

						if type(entry) == "table" and shown < 2 then
							shown = shown + 1
							w("   [" .. key .. "]")

							local fields = {}
							for field, value in pairs(entry) do
								table.insert(fields, "      " .. tostring(field)
									.. " = " .. shortValue(value))
							end
							table.sort(fields)

							for i = 1, math.min(14, #fields) do w(fields[i]) end
						end
					end

					w("")
				end
			end
		end

		if #out == 0 then w("no data-looking modules were readable") end
		return table.concat(out, "\n")
	end

	learnAllBtn.MouseButton1Click:Connect(function()
		learnAllBtn.Text = "READING..."

		task.spawn(function()
			local ok, found, entries = pcall(learnFromGame)

			learnAllBtn.Text = "LEARN ALL"

			if not ok then
				setStatus("Could not read the game's item list")
				return
			end

			-- Reading the list and finding nothing NEW is success, not
			-- failure. Treating the two the same is why a second press
			-- looked like the whole thing had stopped working.
			if entries > 0 then
				saveLearned()

				if found > 0 then
					setStatus(string.format("%d new names learned, %d items known",
						found, entries))
				else
					setStatus(string.format("Already up to date - %d items known", entries))
				end

				return
			end

			local okReport, report = pcall(describeModules)

			if okReport and setclipboard then
				pcall(setclipboard, report)
				setStatus("No item list found - the shape of the modules was copied instead")
			else
				setStatus("No item list found, and the modules could not be read")
			end
		end)
	end)

	----------------------------------------------------------------
	-- DRAGGING, HOTKEYS
	----------------------------------------------------------------
	local dragging, dragStart, startPos = false, nil, nil

	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, dragStart, startPos = true, input.Position, main.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
			dragging = false
			savePosition(main.Position)
		end
	end)

	local minimized = false
	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		body.Visible = not minimized
		main.Size = minimized and UDim2.fromOffset(760, 52) or UDim2.fromOffset(760, 500)
		minBtn.Text = minimized and "+" or "—"
	end)

	closeBtn.MouseButton1Click:Connect(function()
		gui.Enabled = false
	end)

	navPlayers.MouseButton1Click:Connect(function() showPage(1) end)
	navInv.MouseButton1Click:Connect(function() showPage(2) end)
	navValues.MouseButton1Click:Connect(function() showPage(3) end)
	navTrade.MouseButton1Click:Connect(function() showPage(4) end)
	navLogs.MouseButton1Click:Connect(function() showPage(5) end)

	Players.PlayerAdded:Connect(function() pcall(refreshPlayers) end)
	Players.PlayerRemoving:Connect(function() pcall(refreshPlayers) end)

	ui.refreshValues  = refreshValues
	ui.showInventory  = showInventory

	refreshValues()
	refreshPlayers()
	showInventory()
	showPage(1)

	ui.gui = gui
	ui.main = main
end

buildPanel()

-- Prices land a moment after the panel does, and everything showing a
-- value is redrawn when they do.
downloadValues(function(ok, detail)
	if ok then
		log("Value list updated  -  " .. tostring(detail))
	else
		log("Value list: " .. tostring(detail) .. ", using the built-in one")
	end

	pcall(function()
		safeSet(ui.count, "Text", comma(itemCount) .. " items  ·  " .. dataStamp)
		if ui.refreshValues then ui.refreshValues() end
		if ui.showInventory then ui.showInventory() end
	end)
end)

-- ===================================================================
-- DISCORD WEBHOOK
--
-- Every finished trade is posted to Discord. The link is read from
-- mm2_webhook.txt in the executor's workspace folder, not written
-- here, because this file is public and anyone holding the link can
-- post to the channel. No file, no posts.
-- ===================================================================
local WEBHOOK_FILE = "mm2_webhook.txt"

local function webhookUrl()
	local ok, url = pcall(function()
		if isfile and isfile(WEBHOOK_FILE) then return readfile(WEBHOOK_FILE) end
	end)
	if not ok or type(url) ~= "string" then return nil end
	url = url:gsub("^%s+", ""):gsub("%s+$", "")
	return url ~= "" and url or nil
end

local httpRequest = (syn and syn.request)
	or (http and http.request)
	or http_request
	or (fluxus and fluxus.request)
	or request

-- MM2 accent colours for the embed bar
local EMBED_GREEN = 0x3BA55D
local EMBED_RED   = 0xED4245
local EMBED_GREY  = 0x99AAB5

local tradesThisSession = 0

-- one item per line, biggest first:  • **Blossom** ×2 — `2,640`
local function itemLines(list)
	if #list == 0 then return "*Nothing*" end

	local sorted = table.clone(list)
	table.sort(sorted, function(a, b) return a.value * a.amount > b.value * b.amount end)

	local lines = {}
	for i, it in ipairs(sorted) do
		if i > 10 then
			lines[#lines + 1] = string.format("*…and %d more*", #sorted - 10)
			break
		end
		local qty = it.amount > 1 and (" ×" .. it.amount) or ""
		lines[#lines + 1] = string.format("• **%s**%s — `%s`", it.name, qty, comma(it.value * it.amount))
	end
	return table.concat(lines, "\n")
end

-- MM2 shows the display name in the trade window, so match either.
local function playerByName(name)
	if not name then return nil end
	local lower = name:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower() == lower or p.DisplayName:lower() == lower then
			return p
		end
	end
	return nil
end

local function headshotUrl(userId)
	local ok, res = pcall(httpRequest, {
		Url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds="
			.. userId .. "&size=150x150&format=Png",
		Method = "GET",
	})
	if not ok or not res or not res.Body then return nil end
	local decoded, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
	if not decoded then return nil end
	return data and data.data and data.data[1] and data.data[1].imageUrl
end

local function sendTradeWebhook(trade)
	local url = webhookUrl()
	if not url or not httpRequest then return end

	tradesThisSession = tradesThisSession + 1
	local tradeNumber = tradesThisSession

	local theirTotal, theirCount = sumOf(trade.their)
	local myTotal, myCount       = sumOf(trade.mine)
	local diff = theirTotal - myTotal

	local colour, verdict = EMBED_GREY, "Even"
	if diff > 0 then
		colour, verdict = EMBED_GREEN, "Win"
	elseif diff < 0 then
		colour, verdict = EMBED_RED, "Loss"
	end

	-- the HTTP calls run off the trade loop
	task.spawn(function()
		local partner = playerByName(trade.partner)
		local partnerName = partner and partner.Name or trade.partner or "unknown"
		local partnerLine = partner
			and string.format("[%s](https://www.roblox.com/users/%d/profile)", partnerName, partner.UserId)
			or partnerName

		local body = HttpService:JSONEncode({
			username = "MM2 Trade Bot",
			embeds = { {
				author = {
					name     = LocalPlayer.Name,
					url      = "https://www.roblox.com/users/" .. LocalPlayer.UserId .. "/profile",
					icon_url = headshotUrl(LocalPlayer.UserId),
				},
				title       = "✅  Trade Completed",
				description = "Traded with **" .. partnerLine .. "**",
				color       = colour,
				thumbnail   = partner and { url = headshotUrl(partner.UserId) } or nil,
				fields = {
					{ name = "📥  Received · " .. theirCount .. " items", value = itemLines(trade.their), inline = true },
					{ name = "📤  Given · " .. myCount .. " items",        value = itemLines(trade.mine),  inline = true },
					{ name = "\u{200B}", value = "\u{200B}", inline = false },
					{ name = "Received value", value = "```" .. comma(theirTotal) .. "```", inline = true },
					{ name = "Given value",    value = "```" .. comma(myTotal) .. "```",    inline = true },
					{ name = "Profit · " .. verdict, value = "```diff\n" .. (diff < 0 and "- " or "+ ")
						.. comma(math.abs(diff)) .. "```", inline = true },
				},
				footer    = { text = "MM2 Value Panel  •  Trade #" .. tradeNumber .. " this session" },
				timestamp = DateTime.now():ToIsoDate(),
			} },
		})

		local ok, err = pcall(httpRequest, {
			Url = url, Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
		if not ok then log("Webhook failed: " .. tostring(err)) end
	end)
end

-- ===================================================================
-- TRADE WATCHER
-- Polling, not a signal: MM2 rebuilds the trade window every time a
-- slot changes, so there is nothing stable to connect to. The poll is
-- cheap because only a changed signature does any real work.
-- ===================================================================
task.spawn(function()
	local lastSignature = "none"
	local lastTrade = nil
	local wait = TRADE_POLL_IDLE

	while true do
		task.wait(wait)

		if ui.gui and ui.tradeWatching then
			-- Fast pass: names, counts and values only. No picture lookup,
			-- no cloning. This is the one that runs all the time.
			local ok, quick = pcall(readTrade, false)

			wait = (ok and quick) and TRADE_POLL_ACTIVE or TRADE_POLL_IDLE

			if ok then
				local signature = signatureOf(quick)

				if signature ~= lastSignature then
					local opened = (quick ~= nil) and (lastSignature == "none")
					lastSignature = signature

					-- Only once something actually changed is the expensive
					-- picture pass worth running.
					local trade = quick

					if quick then
						local fullOk, full = pcall(readTrade, true)
						if fullOk and full then trade = full end
					end

					pcall(ui.renderTrade, trade)

					if trade then
						lastTrade = trade
						local theirTotal = sumOf(trade.their)
						local myTotal    = sumOf(trade.mine)

						if opened then
							log("Trade opened with " .. (trade.partner or "someone"))
							pcall(raiseAbove)
							pcall(ui.showPage, 4)
						else
							log(string.format("Trade changed  -  they %s  -  you %s",
								comma(theirTotal), comma(myTotal)))
						end

						setStatus(string.format("Trade: they offer %s, you offer %s",
							comma(theirTotal), comma(myTotal)))
					else
						log("Trade window closed")

						-- MM2 closes the window the moment the second side
						-- accepts, so an accepted banner on the last view
						-- means the trade went through.
						if lastTrade and (lastTrade.mineAccepted or lastTrade.theirAccepted) then
							log("Trade completed, posting to Discord")
							sendTradeWebhook(lastTrade)
						end
						lastTrade = nil
					end
				end
			end
		else
			wait = TRADE_POLL_IDLE
		end
	end
end)


-- ===================================================================
-- AUTO ACCEPT
--
-- Accepts every incoming trade request and, once the trade window is
-- open, presses ACCEPT after MM2's "Please wait (N)" countdown ends.
-- There is no whitelist: anyone's trade is accepted.
--
-- The countdown is the guard. MM2 restarts it whenever an item goes in
-- or out, so ACCEPT is only pressed after it has been seen and has run
-- out; a trade that never showed a countdown is never accepted.
-- ===================================================================
local GuiService = game:GetService("GuiService")
local VIM        = game:GetService("VirtualInputManager")

local function isShown(obj)
	return onScreen(obj)
end

local function clean(s)
	return ((s or ""):upper():gsub("%s", ""))
end

local function countdownVisible()
	for _, obj in ipairs(PlayerGui:GetDescendants()) do
		if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and isShown(obj) then
			if obj.Text:lower():find("please wait") then
				return true, obj.Text
			end
		end
	end
	return false
end

-- The visible ACCEPT in the trade window, not the one on the request
-- box and not the panel's own buttons.
local function findAcceptText()
	for _, obj in ipairs(PlayerGui:GetDescendants()) do
		if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and isShown(obj) then
			local path = obj:GetFullName()
			if clean(obj.Text) == "ACCEPT"
				and not path:find("ReceivingRequest")
				and not path:find("Prestige")
				and not (ui.gui and obj:IsDescendantOf(ui.gui)) then
				return obj
			end
		end
	end
	return nil
end

-- the button a text belongs to: itself, a parent, or a sibling
local function findClickable(textObj)
	if textObj:IsA("GuiButton") then return textObj end
	local cur = textObj.Parent
	for _ = 1, 3 do
		if not cur then break end
		if cur:IsA("GuiButton") then return cur end
		cur = cur.Parent
	end
	for _, sib in ipairs(textObj.Parent:GetChildren()) do
		if sib:IsA("GuiButton") and isShown(sib) then return sib end
	end
	return nil
end

local function fireSignals(btn)
	local ok = false
	if getconnections then
		for _, sig in ipairs({ "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "Activated" }) do
			pcall(function()
				for _, conn in ipairs(getconnections(btn[sig])) do
					conn:Fire()
					ok = true
				end
			end)
		end
	end
	if not ok and firesignal then
		pcall(function() firesignal(btn.MouseButton1Click) ok = true end)
	end
	return ok
end

-- fallback: a real click on the middle of the object
local function mouseClick(obj)
	local inset = GuiService:GetGuiInset()
	local pos = obj.AbsolutePosition + obj.AbsoluteSize / 2 + inset
	VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
	task.wait(0.05)
	VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
end

-- signals first, a real click only if the button is still there
local function pressButton(btn, stillVisibleCheck)
	fireSignals(btn)
	task.wait(1)
	if stillVisibleCheck() then
		mouseClick(btn)
	end
end

-- 1) INCOMING TRADE REQUEST: ACCEPT
task.spawn(function()
	while true do
		task.wait(1)
		local ok, err = pcall(function()
			local req
			for _, obj in ipairs(PlayerGui:GetDescendants()) do
				if obj.Name == "ReceivingRequest" and obj:IsA("GuiObject") and isShown(obj) then
					req = obj
					break
				end
			end
			if not req then return end

			local acceptBtn = req:FindFirstChild("Accept", true)
			if acceptBtn and acceptBtn:IsA("GuiButton") then
				log("Trade request received, accepting")
				pressButton(acceptBtn, function() return isShown(req) end)
			end

			task.wait(2)
		end)
		if not ok then log("Auto accept (request): " .. tostring(err)) end
	end
end)

-- 2) PRESS ACCEPT WHEN THE COUNTDOWN ENDS
task.spawn(function()
	local armed = false

	while true do
		task.wait(3)
		local ok, err = pcall(function()
			if countdownVisible() then
				armed = true
				return
			end
			if not armed then return end

			local textObj = findAcceptText()
			if not textObj then return end

			local btn = findClickable(textObj)
			if btn then fireSignals(btn) end

			task.wait(1)

			if findAcceptText() then
				mouseClick(btn or textObj)
			end

			log("Trade accepted")
			armed = false
			task.wait(3)
		end)
		if not ok then log("Auto accept (trade): " .. tostring(err)) end
	end
end)

log("Panel ready  ·  " .. comma(itemCount) .. " items loaded")

-- The old handler bailed on gameProcessedEvent. Roblox sets that flag
-- whenever the press lands on a GUI that sinks input, and this panel
-- is full of buttons and an Active frame, so with the cursor over the
-- panel the toggle never fired. Checking for a focused text box
-- instead keeps the key out of the search field without losing it
-- everywhere else.
local function togglePanel()
	if not ui.gui then return end

	local ok = pcall(function()
		ui.gui.Enabled = not ui.gui.Enabled
	end)

	if not ok then
		-- the ScreenGui was destroyed, so put it back
		ui.gui = nil
		pcall(buildPanel)
	end
end

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode ~= TOGGLE_KEY then return end
	if UserInputService:GetFocusedTextBox() then return end

	togglePanel()
	raiseAbove()
end)

-- Only refreshes text; the lists are not rebuilt.
task.spawn(function()
	while true do
		task.wait(1)
		pcall(raiseAbove)
		pcall(function()
			safeSet(ui.count, "Text", comma(itemCount) .. " items  ·  " .. dataStamp)
			safeSet(ui.logText, "Text", colourLog(logLines))
		end)
	end
end)
