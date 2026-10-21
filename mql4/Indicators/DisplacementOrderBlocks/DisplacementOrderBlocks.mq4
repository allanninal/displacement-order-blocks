//+------------------------------------------------------------------+
//|                                     DisplacementOrderBlocks.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Demand and supply zones left by a displacement candle that      |
//| closes through the newest swing: the zone is the nearest candle |
//| of the other colour before that candle. Each zone is fresh until|
//| price comes back to it, tested after that (re-entries counted)  |
//| and broken once price closes (or wicks) beyond its far edge.    |
//| Decided from closed bars only, so nothing appears, moves or     |
//| disappears after a bar closed. Rules: DzEngine.mqh.             |
//| An indicator, not a trading system: it draws and alerts only.   |
//| MT4 edition: the same engine (DzEngine.mqh, an exact copy of the |
//| MT5 one), the same inputs and the same 13 iCustom buffers.       |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property description "Demand and supply zones from displacement candles that close through a swing: fresh, tested and broken states."
#property description "Non-repainting: zones are decided from closed bars and never change afterwards. Alerts for new, tested and broken zones."
#property indicator_chart_window
#property indicator_buffers 13

#include "DzEngine.mqh"
#include "DzDraw.mqh"

enum ENUM_DZ_ZONE
  {
   DZ_ZONE_FULL=0,      // Whole base candle (high to low)
   DZ_ZONE_BODY=1,      // Base candle body only
   DZ_ZONE_MIXED=2      // Body plus the wick on the far side
  };
enum ENUM_DZ_BASE
  {
   DZ_BASE_NEAREST=0,   // Nearest candle of the other colour
   DZ_BASE_MOVE=1       // Other-colour candle where the move began
  };
enum ENUM_DZ_TEST
  {
   DZ_TEST_NEAR=0,      // Price reaches the near edge
   DZ_TEST_MID=1,       // Price reaches the middle
   DZ_TEST_FAR=2        // Price reaches the far edge
  };
enum ENUM_DZ_BREAK
  {
   DZ_BREAK_CLOSE=0,    // A bar closes beyond the far edge
   DZ_BREAK_WICK=1      // A wick goes beyond the far edge
  };

input int           InpSwing      = 3;              // Swing strength, bars on each side
input int           InpATR        = 14;             // ATR period
input double        InpDispMult   = 1.0;            // Candle range at least, x ATR
input double        InpBodyPct    = 55.0;           // Candle body at least, % of its range
input int           InpSearch     = 12;             // Bars searched back for the base candle
input ENUM_DZ_BASE  InpBaseMode   = DZ_BASE_NEAREST; // Base candle
input ENUM_DZ_ZONE  InpZoneMode   = DZ_ZONE_FULL;   // Zone covers
input ENUM_DZ_TEST  InpTestMode   = DZ_TEST_NEAR;   // A zone is tested when
input ENUM_DZ_BREAK InpBreakMode  = DZ_BREAK_CLOSE; // A zone is broken when
input int           InpMaxLive    = 12;             // Live zones kept per side (0 = no limit)
input bool          InpShowTested = true;           // Keep tested zones (dashed outline)
input bool          InpShowBroken = false;          // Keep broken zones, up to the bar that broke them (grey)
input bool          InpMidline    = true;           // Middle line
input bool          InpLabels     = true;           // Labels (D / S, x2 = second entry)
input bool          InpSwings     = false;          // Mark the swing that was closed through
input int           InpDrawBars   = 1000;           // Draw zones made within this many bars
input int           InpMaxZones   = 60;             // Draw at most this many zones (newest first)
input int           InpExtendBars = 15;             // Extend live zones this many bars past the last bar
input bool          InpFill       = true;           // Fill fresh zones
input color         InpClrDem     = C'38,120,90';   // Demand colour
input color         InpClrSup     = C'150,52,60';   // Supply colour
input color         InpClrBroken  = C'110,110,110'; // Broken zone colour

#include "SignalAlerts.mqh"

input bool          InpAlNew      = true;           // Alert: new zone
input bool          InpAlTest     = true;           // Alert: a fresh zone is tested
input bool          InpAlBroken   = false;          // Alert: a zone is broken

const string PRODUCT="Displacement Order Blocks";
const string PFX="DZ_";

//--- the 13 buffers, series-indexed (0 = live bar) as every MT4 buffer; the engine counts bars from the oldest
double b0[],b1[],b2[],b3[],b4[],b5[],b6[],b7[],b8[],b9[],b10[],b11[],b12[];
CDzEngine g_eng;
SDzStyle  g_style;
double    g_out[];
int       g_draw_stamp=-1;
bool      g_no_draw=false;

//--- buffer k at series index s
void SetB(const int k,const int s,const double v)
  {
   switch(k)
     {
      case 0:  b0[s]=v;  break;
      case 1:  b1[s]=v;  break;
      case 2:  b2[s]=v;  break;
      case 3:  b3[s]=v;  break;
      case 4:  b4[s]=v;  break;
      case 5:  b5[s]=v;  break;
      case 6:  b6[s]=v;  break;
      case 7:  b7[s]=v;  break;
      case 8:  b8[s]=v;  break;
      case 9:  b9[s]=v;  break;
      case 10: b10[s]=v; break;
      case 11: b11[s]=v; break;
      case 12: b12[s]=v; break;
     }
  }

int OnInit()
  {
   if(InpSwing<1 || InpSwing>20 || InpATR<1 || InpDispMult<0 || InpBodyPct<0 || InpBodyPct>100 || InpSearch<1 ||
      InpMaxLive<0 || InpDrawBars<1 || InpMaxZones<0 || InpExtendBars<0)
     {
      Print(PRODUCT,": check the inputs (swing 1-20, ATR period 1+, body 0-100 %, search 1+ bars)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   string names[DZ_B_COUNT]={"New demand top","New demand bottom","New supply top","New supply bottom","Swing high closed through",
                             "Swing low closed through","Zones tested","Retests","Zones broken","Live demand zones",
                             "Live supply zones","Demand base, bars back","Supply base, bars back"};
   ArrayResize(g_out,DZ_B_COUNT);
   IndicatorBuffers(DZ_B_COUNT);
   SetIndexBuffer(0,b0);   SetIndexBuffer(1,b1);   SetIndexBuffer(2,b2);   SetIndexBuffer(3,b3);
   SetIndexBuffer(4,b4);   SetIndexBuffer(5,b5);   SetIndexBuffer(6,b6);   SetIndexBuffer(7,b7);
   SetIndexBuffer(8,b8);   SetIndexBuffer(9,b9);   SetIndexBuffer(10,b10); SetIndexBuffer(11,b11);
   SetIndexBuffer(12,b12);
   for(int k=0; k<DZ_B_COUNT; k++)
     {
      SetIndexStyle(k,DRAW_NONE);
      SetIndexEmptyValue(k,EMPTY_VALUE);
      SetIndexLabel(k,names[k]);
     }
   g_eng.Defaults();
   g_eng.swing=InpSwing;
   g_eng.atr_period=InpATR;
   g_eng.disp_mult=InpDispMult;
   g_eng.body_pct=InpBodyPct;
   g_eng.search=InpSearch;
   g_eng.base_mode=(int)InpBaseMode;
   g_eng.zone_mode=(int)InpZoneMode;
   g_eng.test_mode=(int)InpTestMode;
   g_eng.break_mode=(int)InpBreakMode;
   g_eng.max_live=InpMaxLive;
   g_eng.Reset();
   g_style.fill=InpFill;
   g_style.show_tested=InpShowTested;
   g_style.show_broken=InpShowBroken;
   g_style.midline=InpMidline;
   g_style.labels=InpLabels;
   g_style.swings=InpSwings;
   g_style.draw_bars=InpDrawBars;
   g_style.max_zones=InpMaxZones;
   g_style.extend=InpExtendBars;
   g_style.dem=InpClrDem;
   g_style.sup=InpClrSup;
   g_style.broken=InpClrBroken;
   g_draw_stamp=-1;
   g_no_draw=(IsTesting() && !IsVisualMode());
   IndicatorShortName(PRODUCT);
   IndicatorDigits(_Digits);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,PFX);
   ChartRedraw();
  }

void Redraw(const datetime &time[],const int n)
  {
   ObjectsDeleteAll(0,PFX);
   datetime from_t=time[MathMax(0,n-1-InpDrawBars)];
   datetime right_t=time[n-1]+(datetime)((long)InpExtendBars*PeriodSeconds(PERIOD_CURRENT));
   DzDrawEngine(g_eng,time,PFX,from_t,right_t,InpMaxZones,g_style,_Digits);
   ChartRedraw();
  }

//--- the alert text for the closed bar just processed
string Events(const double &o[])
  {
   string s="";
   if(InpAlNew)
     {
      if(o[DZ_B_DEM_TOP]!=EMPTY_VALUE)
         s+="new demand zone "+DoubleToString(o[DZ_B_DEM_BOT],_Digits)+"-"+DoubleToString(o[DZ_B_DEM_TOP],_Digits)+"; ";
      if(o[DZ_B_SUP_TOP]!=EMPTY_VALUE)
         s+="new supply zone "+DoubleToString(o[DZ_B_SUP_BOT],_Digits)+"-"+DoubleToString(o[DZ_B_SUP_TOP],_Digits)+"; ";
     }
   if(InpAlTest && o[DZ_B_TESTED]!=EMPTY_VALUE && o[DZ_B_TESTED]>0)
      s+=StringFormat("%d fresh zone(s) tested; ",(int)o[DZ_B_TESTED]);
   if(InpAlBroken && o[DZ_B_BROKEN]!=EMPTY_VALUE && o[DZ_B_BROKEN]>0)
      s+=StringFormat("%d zone(s) broken; ",(int)o[DZ_B_BROKEN]);
   return(s);
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<3)
      return(0);
//--- the engine and the drawing count bars from the oldest, as MT5 does
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);
   if(prev_calculated==0 || g_eng.done>rates_total-2)
      g_eng.Reset();
   bool moved=false;
   for(int i=g_eng.done+1; i<=rates_total-2; i++)
     {
      g_eng.Step(i,time,open,high,low,close,g_out);
      for(int k=0; k<DZ_B_COUNT; k++)
         SetB(k,rates_total-1-i,g_out[k]);
      moved=true;
      if(i==rates_total-2 && prev_calculated>0)
        {
         string ev=Events(g_out);
         if(ev!="")
            SignalAlert(PRODUCT,ev,time[i],true);
        }
     }
   for(int k=0; k<DZ_B_COUNT; k++)
      SetB(k,0,EMPTY_VALUE);
   if(g_no_draw)                                   // non-visual Strategy Tester: no chart, so no objects
      return(rates_total);
   if(moved || g_draw_stamp!=rates_total)
     {
      Redraw(time,rates_total);
      g_draw_stamp=rates_total;
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
