//+------------------------------------------------------------------+
//|                                 DisplacementOrderBlocksDump.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (a test tool, not part of the indicator): dumps the 13  |
//| Displacement Order Blocks MT4 buffers and checks repainting in   |
//| the Strategy Tester, via IndTest4/Dump4.mqh. The indicator runs  |
//| over the whole history, so the final values are those of the     |
//| running instance. Compare the CSVs with the Python reference:    |
//|   python3 tests/check_parity.py <dump folder> --mt4              |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#define DUMP4_BUFFERS "0,1,2,3,4,5,6,7,8,9,10,11,12"
#define DUMP4_PROBE   "0,2,6,8"   // new demand / supply zones, zones tested, zones broken

input int    InpSwing     = 3;
input int    InpATR       = 14;
input double InpDispMult  = 1.0;
input double InpBodyPct   = 55.0;
input int    InpSearch    = 12;
input int    InpBaseMode  = 0;
input int    InpZoneMode  = 0;
input int    InpTestMode  = 0;
input int    InpBreakMode = 0;
input int    InpMaxLive   = 12;

double IndValue(const int buf,const int shift)
  {
   return(iCustom(NULL,0,"DisplacementOrderBlocks\\DisplacementOrderBlocks",InpSwing,InpATR,InpDispMult,InpBodyPct,InpSearch,
                  InpBaseMode,InpZoneMode,InpTestMode,InpBreakMode,InpMaxLive,
                  true,false,true,true,false,1000,60,15,true,C'38,120,90',C'150,52,60',C'110,110,110',
                  false,false,"alert.wav",false,false,true,true,false,buf,shift));
  }

#include <IndTest4/Dump4.mqh>
//+------------------------------------------------------------------+
