# AGENTS.md - DSC (Dynamic SOF Campaign)

An Arma 3 mod for dynamic Special Operations Forces mission generation.

## Quick Reference

| Command | Description |
|---------|-------------|
| `hemtt launch` | Build and launch with default mods (CBA_A3) |
| `hemtt launch developer` | Launch with dev tools (ADT, Pythia) |
| `hemtt launch developer_extended_factions` | Launch with RHS, Aegis faction mods |
| `hemtt build` | Build PBOs without launching |

## Project Structure

```
DSC/
├── addons/
│   ├── main/           # Core mod addon (currently empty)
│   └── maps/           # Map-specific missions
│       └── DSC_Altis.Altis/
│           ├── mission.sqm      # Eden editor mission file
│           ├── initServer.sqf   # Server-side initialization
│           └── initPlayerLocal.sqf  # Client-side initialization
└── .hemtt/
    ├── project.toml    # HEMTT project config
    └── launch.toml     # Launch configurations with workshop mods
```

## Development Workflow

1. Edit SQF files in `DSC/addons/maps/`
2. Run `hemtt launch developer_extended_factions` to test with faction mods
3. Check Arma 3 RPT logs at `C:\Users\Adam\AppData\Local\Arma 3\arma3_x64_*.rpt`
4. Use `diag_log` for debugging - logs appear in RPT files

## Arma 3 SQF Conventions

### Config Access Patterns
```sqf
// Get all classes from a config
"true" configClasses (configFile >> "CfgFactionClasses")

// Get config value
getText (_cfg >> "displayName")
getNumber (_cfg >> "side")
getArray (_cfg >> "items")

// Check class name
configName _cfg
```

### Key Configs for Faction System
- `CfgFactionClasses` - All available factions
- `CfgVehicles` - All units, vehicles, objects (use `isMan` to filter infantry)
- `CfgGroups` - Pre-defined group compositions (Infantry, SpecOps, Armor, etc.)

### Side Numbers
| Number | Side |
|--------|------|
| 0 | OPFOR |
| 1 | BLUFOR |
| 2 | Independent |
| 3 | Civilian |

### Unit Classification via `editorSubcategory`
```sqf
getText (_unitCfg >> "editorSubcategory")
```
Common values:
- `EdSubcat_Personnel` - Standard infantry
- `EdSubcat_Personnel_SpecialForces` - SOF units
- `EdSubcat_Personnel_Snipers` - Snipers
- `EdSubcat_Personnel_Crew` - Vehicle crew
- `EdSubcat_Personnel_Pilots` - Pilots

## Current Focus: Mod-Agnostic Factioning

The goal is to dynamically discover and use factions from any loaded mods (RHS, CUP, CFP, Aegis, 3CB, vanilla) without hardcoding.

### Approach
1. Scan `CfgFactionClasses` for available factions
2. Use `CfgGroups` for pre-configured squad compositions (most reliable)
3. Fall back to `CfgVehicles` filtering for custom group building
4. Map factions to campaign roles (Host Nation, Occupier, Insurgent, etc.)

### Reference Material
- See `.crush/faction-notes.md` for detailed faction system design notes
- Dynamic Recon Ops is a reference mod for this approach

## Testing

1. Launch game with `hemtt launch developer_extended_factions`
2. Check RPT log for `DSC:` prefixed messages
3. Look for faction discovery output to verify configs are being read correctly

## Gotchas

- `CfgGroups` structure varies by mod - some mods define groups differently
- `editorSubcategory` reliability varies by mod (RHS/3CB excellent, CFP less consistent)
- Always use `getOrDefault` with hashmaps for safety
- RPT logs are timestamped - check the most recent file after each launch
