//+------------------------------------------------------------------+
//|                                                       DzDraw.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Draws a CDzEngine's zones on the chart: rectangles (fresh filled,|
//| tested outlined, broken grey up to the bar that broke them), the |
//| middle line, a short label and the broken swing. Objects share   |
//| one prefix and are rebuilt only when a bar closes.               |
//| MT4 edition: MT4 fills a rectangle only when it is drawn in the  |
//| background, so OBJPROP_BACK follows the fill (else as MT5).      |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#ifndef DZDRAW_MQH
#define DZDRAW_MQH

#include "DzEngine.mqh"

struct SDzStyle
  {
   bool  fill,show_tested,show_broken,midline,labels,swings;
   int   draw_bars,max_zones,extend;
   color dem,sup,broken;
  };

void DzRect(const string name,const datetime t1,const double top,const datetime t2,const double bot,const color clr,
            const bool fill,const ENUM_LINE_STYLE style,const string tip)
  {
   if(ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bot))
     {
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_FILL,fill);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_BACK,fill);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
     }
  }

void DzSeg(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,
           const ENUM_LINE_STYLE style,const string tip)
  {
   if(ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2))
     {
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
     }
  }

void DzText(const string name,const datetime t,const double p,const string text,const color clr,const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectCreate(0,name,OBJ_TEXT,0,t,p))
     {
      ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }
  }

string DzStateText(const SDzZone &z)
  {
   if(z.state==DZ_FRESH)
      return("fresh");
   if(z.state==DZ_TESTED)
      return(z.retests>1 ? StringFormat("tested, %d entries",z.retests) : "tested");
   return("broken");
  }

//--- draw the zones of the engine; `t` = bar times of the series it ran on
int DzDrawEngine(CDzEngine &e,const datetime &t[],const string pfx,const datetime from_t,
                 const datetime right_t,const int budget,const SDzStyle &st,const int digits)
  {
   int drawn=0;
   for(int z=e.nz-1; z>=0 && drawn<budget; z--)
     {
      if(t[e.zones[z].born]<from_t)
         break;                                    // zones are stored in birth order: all older ones are out too
      int s=e.zones[z].state;
      if(s==DZ_DROPPED || (s==DZ_TESTED && !st.show_tested) || (s==DZ_BROKEN && !st.show_broken))
         continue;
      bool dem=(e.zones[z].dir>0),live=(e.zones[z].end<0);
      color clr=(s==DZ_BROKEN ? st.broken : (dem ? st.dem : st.sup));
      datetime t2=(live ? right_t : t[e.zones[z].end]);
      string tip=StringFormat("%s zone %s - %s, made %s, %s",dem ? "Demand" : "Supply",
                              DoubleToString(e.zones[z].bot,digits),DoubleToString(e.zones[z].top,digits),
                              TimeToString(t[e.zones[z].born]),DzStateText(e.zones[z]));
      string nm=StringFormat("%sZ%d",pfx,z);
      bool fill=(st.fill && s==DZ_FRESH);
      DzRect(nm,t[e.zones[z].t0],e.zones[z].top,t2,e.zones[z].bot,clr,fill,s==DZ_TESTED ? STYLE_DASH : STYLE_SOLID,tip);
      if(st.midline)
         DzSeg(nm+"m",t[e.zones[z].t0],e.zones[z].mid,t2,e.zones[z].mid,clr,STYLE_DOT,tip);
      if(st.labels)
        {
         string lb=(dem ? "D" : "S")+(e.zones[z].retests>1 ? "x"+IntegerToString(e.zones[z].retests) : "");
         DzText(nm+"l",t[e.zones[z].t0],dem ? e.zones[z].bot : e.zones[z].top,lb,clr,dem ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
        }
      drawn++;
     }
   int shown=0;
   if(st.swings)
      for(int b=e.nb-1; b>=0 && shown<budget; b--)
        {
         if(t[e.breaks[b].at]<from_t)
            break;
         if(e.breaks[b].zone<0)
            continue;
         bool up=(e.breaks[b].dir>0);
         DzSeg(StringFormat("%sB%d",pfx,b),t[e.breaks[b].frm],e.breaks[b].level,t[e.breaks[b].at],e.breaks[b].level,
               up ? st.dem : st.sup,STYLE_DOT,up ? "Swing high closed through with displacement" : "Swing low closed through with displacement");
         shown++;
        }
   return(drawn);
  }

#endif
//+------------------------------------------------------------------+
