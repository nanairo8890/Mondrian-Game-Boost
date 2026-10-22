#!/usr/bin/env python3
"""Builds the two power HAL configs of Mondrian-Game-Boost from the one the ROM ships.

    gen_powerhint.py <base powerhint.json> <out dir> <version>

Writes <out dir>/powerhint-alto.json and <out dir>/powerhint-maximo.json.

The base (vendor/etc/powerhint.json of Project Infinity-X 4.1, identical in MistOS 5.1 Beta) has no
action for the GAME and GAME_LOADING modes, which Android's GameManager sends to the power HAL while
a game is the only app on top and while a game in performance mode says it is loading. Each file
adds them for one level: libperfmgr allows a single action per node and hint, so the two levels
are two files and the level is picked at boot.

Node changes, the same in both files:
- UclampTAMin / UclampFGMin: the ROM lists the values from low to high, and libperfmgr applies the
  value with the lowest index among the active requests, so the smallest boost won (a touch held
  a game's or a launch's uclamp down). Listed from high to low, like every frequency node, so the
  biggest boost wins; the default stays "0".
- CPU*DownRateLimit default "0" and CPULittleClusterMinFreq default "556800": the values the
  vendor post_boot script (init.kernel.post_boot-cape.sh) sets at boot, so the power HAL puts those
  back when a game ends instead of its own older defaults. The ROM's INTERACTIVE (screen on) asks
  the DownRateLimit nodes for "2000", which was its default index, so the power HAL never wrote it
  and the phone ran at post_boot's 0; INTERACTIVE now asks for "0" too, so outside games it stays 0.
- GAME_LOADING actions last 10 s at most (repeated calls renew them), in case a game never reports
  the end of its loading; GAME is ended by the framework when the game leaves the top.

New node ThermalScene: the scene mi_thermald applies (/sys/.../thermal_message/sconfig, the file
XiaomiParts' thermal profiles write). The ROM keeps scene 0 (thermal-normal: prime core capped at
2246400 and gold at 2572800 from 25 C, GPU cooling from 15 C). While a game is on top the level
asks for 13 (thermal-tgame, the Gaming profile: no CPU cap below 45 C) or 10 (thermal-nolimits,
the Benchmark profile: nothing below 51 C); the highest listed wins and "0" comes back when the game
ends. The power HAL needs the module's sepolicy.rule to write it; without it the write only fails
and is retried (FileNode::Update logs and retries, it never aborts).

The output is checked with the rules libperfmgr's HintManager::ParseNodes / ParseActions apply
(LineageOS android_hardware_google_pixel lineage-24.0): any failure there makes the power HAL abort
before it registers, and system_server waits for it.
"""
import copy
import json
import os
import sys

MARK_KEY = "GameBoostModule"  # not read by libperfmgr (it reads Nodes, Actions, AdpfConfig,
                              # GpuSysfsPath, OtherConfigs); lets the scripts tell the file is ours

GAME_ALTO = {
    "PMQoSCpuDmaLatency": "44",
    "UclampTAMin": "35",
    "UclampFGMin": "20",
    "UclampTALatency": "1",
    "SchedUpmigrate": "90 80",
    "SchedDownmigrate": "80 70",
    "CPULittleClusterDownRateLimit": "20000",
    "CPUBigClusterDownRateLimit": "10000",
    "CPUBigPlusClusterDownRateLimit": "5000",
    "CPUBigClusterMinFreq": "1555200",
    "CPUBigPlusClusterMinFreq": "1651200",
    "GPUMinFreq": "580000000",
    "GPUIdleTimer": "500",
    "CPUBWMinFreq": "2092000",
    "LLCCBWMinFreq": "806000",
    "L3MinFreq": "1267200",
    "ThermalScene": "13",
}

# On top of GAME_ALTO (same node -> this value)
GAME_MAX = {
    "CPULittleClusterMinFreq": "9999999",
    "CPUBigClusterMinFreq": "9999999",
    "CPUBigPlusClusterMinFreq": "9999999",
    "GPUMinFreq": "900000000",
    "GPUIdleTimer": "5000",
    "CPUBWMinFreq": "3196000",
    "LLCCBWMinFreq": "1066000",
    "L3MinFreq": "1708800",
    "UclampTAMin": "60",
    "UclampFGMin": "50",
    "SleepDisabled": "1",
    "PredictionDisabled": "1",
    "ThermalScene": "10",
}

GAME_LOADING = {
    "PMQoSCpuDmaLatency": "44",
    "UclampTAMin": "60",
    "UclampFGMin": "50",
    "UclampTALatency": "1",
    "SchedUpmigrate": "90 80",
    "SchedDownmigrate": "80 70",
    "CPUBigClusterMinFreq": "9999999",
    "CPUBigPlusClusterMinFreq": "9999999",
    "GPUMinFreq": "710000000",
    "GPUIdleTimer": "5000",
    "CPUBWMinFreq": "3196000",
    "LLCCBWMinFreq": "1066000",
    "L3MinFreq": "1708800",
    "ThermalScene": "10",
}

# Added to the ROM's nodes (the real path, not the /sys/class/thermal symlink, so the power HAL
# needs no access to read symlinks; init gives the file system:system 0664 and the power HAL runs
# as root)
NEW_NODES = [
    {
        "Name": "ThermalScene",
        "Path": "/sys/devices/virtual/thermal/thermal_message/sconfig",
        "Values": ["10", "13", "0"],
        "DefaultIndex": 2,
        # A power HAL restarted mid-game (the ROM restarts it when the framework restarts) writes
        # "0" again instead of believing it is already there
        "ResetOnInit": True,
    },
]

GAME_LOADING_MS = 10000

# (hint, node) of the ROM's actions -> new value
ROM_ACTION_VALUES = {
    ("INTERACTIVE", "CPULittleClusterDownRateLimit"): "0",
    ("INTERACTIVE", "CPUBigClusterDownRateLimit"): "0",
    ("INTERACTIVE", "CPUBigPlusClusterDownRateLimit"): "0",
}

REVERSE_VALUES = ["UclampTAMin", "UclampFGMin"]
# node -> (value to add at the end if missing, value that becomes the default)
POST_BOOT_DEFAULTS = {
    "CPULittleClusterDownRateLimit": "0",
    "CPUBigClusterDownRateLimit": "0",
    "CPUBigPlusClusterDownRateLimit": "0",
    "CPULittleClusterMinFreq": "556800",
}


def is_uint(v):
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def check(cfg):
    """libperfmgr's parse rules for Nodes and Actions (each failure discards the whole config)."""
    names, paths = {}, set()
    for i, n in enumerate(cfg["Nodes"]):
        name = n.get("Name", "")
        assert name, f"Node[{i}] without Name"
        assert name not in names, f"Duplicate Node[{i}]'s Name {name}"
        node_paths = [n["Path"]] if n.get("Path") else []
        for p in n.get("Paths", []):
            assert p, f"Node[{i}] empty path in Paths"
            node_paths.append(p)
        assert node_paths, f"Node[{i}] ({name}) without Path/Paths"
        for p in node_paths:
            assert p not in paths, f"Duplicate Node[{i}]'s Paths {p}"
            paths.add(p)
        ntype = n.get("Type", "")
        assert ntype in ("", "Event", "File", "Property"), f"Invalid Node[{i}]'s Type {ntype}"
        values = n.get("Values", [])
        assert values, f"Node[{i}] ({name}) without Values"
        assert len(set(values)) == len(values), f"Duplicate value parsed in Node[{i}] ({name})"
        if ntype in ("", "File"):
            assert all(v != "" for v in values), f"Node[{i}] ({name}) empty value"
        if "DefaultIndex" in n:
            assert is_uint(n["DefaultIndex"]) and n["DefaultIndex"] <= len(values) - 1, \
                f"Node[{i}] ({name}) DefaultIndex out of range"
        for k in ("ResetOnInit", "HoldFd", "Truncate"):
            assert k not in n or isinstance(n[k], bool), f"Node[{i}] ({name}) {k} not bool"
        names[name] = values
    seen = set()
    for i, a in enumerate(cfg["Actions"]):
        hint = a.get("PowerHint", "")
        assert hint, f"Action[{i}] without PowerHint"
        atype = a.get("Type", "")
        assert atype in ("", "DoHint", "EndHint", "MaskHint"), f"Invalid Action[{i}]'s Type {atype}"
        if atype:
            assert a.get("Value"), f"Action[{i}] ({hint}) hint action without Value"
            continue
        node = a.get("Node", "")
        assert node in names, f"Action[{i}] ({hint}): no node {node!r}"
        assert a.get("Value") in names[node], f"Action[{i}] ({hint}): {node} has no value {a.get('Value')!r}"
        assert "Duration" in a and is_uint(a["Duration"]), f"Action[{i}] ({hint}): bad Duration"
        assert (hint, node) not in seen, f"Action[{i}]'s NodeIndex is duplicated ({hint}, {node})"
        seen.add((hint, node))


def node(cfg, name):
    return next(n for n in cfg["Nodes"] if n["Name"] == name)


def adjust_nodes(cfg):
    for name in REVERSE_VALUES:
        n = node(cfg, name)
        default = n["Values"][n.get("DefaultIndex", len(n["Values"]) - 1)]
        n["Values"] = list(reversed(n["Values"]))
        n["DefaultIndex"] = n["Values"].index(default)
    for name, value in POST_BOOT_DEFAULTS.items():
        n = node(cfg, name)
        if value not in n["Values"]:
            n["Values"].append(value)
        n["DefaultIndex"] = n["Values"].index(value)
    found = 0
    for a in cfg["Actions"]:
        key = (a["PowerHint"], a.get("Node"))
        if key in ROM_ACTION_VALUES:
            a["Value"] = ROM_ACTION_VALUES[key]
            found += 1
    assert found == len(ROM_ACTION_VALUES), "ROM actions to change not found"


def build(base, level, version):
    cfg = copy.deepcopy(base)
    adjust_nodes(cfg)
    cfg["Nodes"] = cfg["Nodes"] + copy.deepcopy(NEW_NODES)
    game = dict(GAME_ALTO)
    if level == "maximo":
        game.update(GAME_MAX)
    new = [{"PowerHint": "GAME", "Node": n, "Duration": 0, "Value": v} for n, v in game.items()]
    new += [{"PowerHint": "GAME_LOADING", "Node": n, "Duration": GAME_LOADING_MS, "Value": v}
            for n, v in GAME_LOADING.items()]
    cfg["Actions"] = cfg["Actions"] + new
    check(cfg)
    out = {MARK_KEY: f"mondrian_game_boost {version} {level}"}
    out.update(cfg)
    return out, len(new)


def main(base_path, out_dir, version):
    with open(base_path) as f:
        base = json.load(f)
    check(base)
    assert not {a["PowerHint"] for a in base["Actions"]} & {"GAME", "GAME_LOADING"}, \
        "the base already has GAME actions"
    for level in ("alto", "maximo"):
        cfg, added = build(base, level, version)
        # Nothing of the base changes except the nodes and actions adjusted above
        diff = [(b["PowerHint"], b.get("Node")) for b, n in zip(base["Actions"], cfg["Actions"]) if b != n]
        assert sorted(diff) == sorted(ROM_ACTION_VALUES), diff
        assert cfg["AdpfConfig"] == base["AdpfConfig"]
        changed = [b["Name"] for b, n in zip(base["Nodes"], cfg["Nodes"]) if b != n]
        assert sorted(changed) == sorted(REVERSE_VALUES + list(POST_BOOT_DEFAULTS)), changed
        assert cfg["Nodes"][len(base["Nodes"]):] == NEW_NODES
        path = os.path.join(out_dir, f"powerhint-{level}.json")
        with open(path, "w") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
        print(f"{os.path.basename(path)}: {len(cfg['Nodes'])} nodes, {len(cfg['Actions'])} actions "
              f"({added} new), nodes adjusted: {', '.join(changed)}, "
              f"added: {', '.join(n['Name'] for n in NEW_NODES)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
