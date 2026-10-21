# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Compare what MT5's Displacement Order Blocks wrote (DumpIndicator CSVs, buffers b0..b12) with the Python reference, bar by bar.

    python3 tests/check_parity.py <dump dir> [--mt4]     (needs numpy and pandas)

Each CONFIG is one DumpIndicator run (tag -> reference kwargs, the same overrides as tests/configs.tsv). Pass: on every
closed bar every buffer is equal (prices within 1e-9 relative, counts exactly, empty where the reference has nothing)."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from reference import KEYS, dz_zones  # noqa: E402

CONFIGS = {
    "dz_default": dict(),
    "dz_body_mid_wick": dict(swing=5, zone_mode=1, test_mode=1, break_mode=1, max_live=0),
    "dz_mixed_far": dict(swing=2, atr=10, disp_mult=1.5, body_pct=60.0, search=5, zone_mode=2, test_mode=2, max_live=3),
    "dz_move_base": dict(base_mode=1, zone_mode=1, test_mode=1, max_live=0),
}


def check(csv: Path, kw: dict, mt4=False) -> tuple[bool, str]:
    d = pd.read_csv(csv)
    if mt4:                            # Dump4 writes the bar time as text (server time, as MT5's epoch seconds)
        d["time"] = (pd.to_datetime(d["time"], format="%Y.%m.%d %H:%M") - pd.Timestamp(0)) // pd.Timedelta(seconds=1)
    t, o, h, l, c = (d[k].to_numpy(float) for k in ("time", "open", "high", "low", "close"))
    ref, zones, breaks, _, _ = dz_zones(t, o, h, l, c, **kw)
    closed = slice(0, len(d) - 1)
    bad, badcols = 0, []
    for j, k in enumerate(KEYS):
        mt, rf = d[f"b{j}"].to_numpy(float)[closed], ref[k][closed]
        same = np.isclose(mt, rf, rtol=1e-9, atol=0, equal_nan=True)
        if not same.all():
            bad += int((~same).sum())
            first = int(np.argmax(~same))
            badcols.append(f"{k}:{int((~same).sum())}(first bar {first}: mt5 {mt[first]} ref {rf[first]})")
    states = [z["state"] for z in zones]
    ok = bad == 0
    return ok, (f"{csv.stem:30} bars {len(d):>6}  zones {len(zones):>5} (tested {sum(z['retests'] > 0 for z in zones):>5}, "
                f"broken {states.count(2):>5})  breaks {len(breaks):>5}  "
                f"{'all 13 buffers equal' if ok else 'DIFFER ' + ' '.join(badcols)}")


if __name__ == "__main__":
    mt4 = "--mt4" in sys.argv          # MT4 dumps from Dump4.mqh
    root = Path([a for a in sys.argv[1:] if a != "--mt4"][0])
    allok, n = True, 0
    for tag, kw in CONFIGS.items():
        for f in sorted(root.glob(f"{tag}_*.csv")):
            ok, msg = check(f, kw, mt4)
            allok &= ok
            n += 1
            print(("PASS " if ok else "FAIL ") + msg)
    print(f"\n{'ALL PASS' if allok and n else 'FAILURES'} ({n} files)")
    sys.exit(0 if allok and n else 1)
