# Repaint check results (copied from the run output files of the development repo)

MT5, Strategy Tester every-tick run, EURUSD H1, 2026-01 to 2026-10, default inputs (RepaintProbe EA; probed buffers: new
demand zone, new supply zone, zones tested, zones broken):

| field | value |
|---|---|
| ticks processed | 10,411,052 |
| closed bars checked | 4,644 |
| zone events seen when the bar closed | 531 |
| values changed after the close | 0 |
| signals ever shown on the live bar | 0 |

MT4, Strategy Tester (Dump4.mqh + DisplacementOrderBlocksDump.mq4), 49 runs = 4 input sets x 4 symbols (EURUSD, GBPJPY, XAUUSD,
BTCUSD) x M15/H1/H4, plus one every-tick EURUSD H1 run; totals over all 49 runs:

| field | value |
|---|---|
| closed bars checked | 1,005,828 |
| mismatches with the final values | 0 |
| signals on the live bar | 0 |
| bars not found again | 0 |

The raw price dumps behind the parity runs are not published (broker price data).
