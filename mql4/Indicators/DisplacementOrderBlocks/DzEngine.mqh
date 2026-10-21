//+------------------------------------------------------------------+
//|                                                     DzEngine.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Displacement zone engine. A bar-by-bar state machine: Step(i)    |
//| uses bars 0..i only, and what it decided about a bar never       |
//| changes later. Rules (d = +1 demand, -1 supply):                 |
//|  ATR      Wilder's smoothing of the true range, seeded with the  |
//|           SMA of the first `atr_period` values. The displacement |
//|           test uses the ATR as it was BEFORE the bar (bar i-1).  |
//|  swing    bar p is a swing high when the `swing` bars on its left|
//|           have lower highs and the `swing` bars on its right     |
//|           highs not above it (mirror for lows). Known at p+swing.|
//|  break    the first close beyond the newest swing high (low).    |
//|           That close uses the swing up, with or without a zone.  |
//|  impulse  the break bar must be a displacement candle: range at  |
//|           least disp_mult x ATR, body at least body_pct % of the |
//|           range, closing in the break's direction.               |
//|  base     base_mode 0: the nearest candle of the other colour    |
//|           among the `search` bars before the break bar.          |
//|           base_mode 1: where the move started: the lowest low    |
//|           (demand; supply: highest high, latest bar on a tie) of |
//|           those bars, then the nearest candle of the other       |
//|           colour at or before it, in the same bars. None: no zone|
//|  zone     0 full candle, 1 body, 2 mixed (demand: low to body    |
//|           top, supply: body bottom to high).                     |
//|  states   fresh -> tested (price reaches the near edge, middle   |
//|           or far edge, from the bar after the zone was made) ->  |
//|           broken (a close or a wick beyond the far edge; checked |
//|           first, so a bar that does both only breaks it). Each   |
//|           later re-entry after a bar outside counts a retest.    |
//|  cap      at most `max_live` live zones per side (0 = no limit): |
//|           the oldest live one of that side is dropped.           |
//| An analysis tool: it describes zones, it does not trade.         |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#ifndef DZENGINE_MQH
#define DZENGINE_MQH

#define DZ_B_DEM_TOP     0
#define DZ_B_DEM_BOT     1
#define DZ_B_SUP_TOP     2
#define DZ_B_SUP_BOT     3
#define DZ_B_BREAK_UP    4     // the swing high broken on this bar (price)
#define DZ_B_BREAK_DN    5     // the swing low broken on this bar (price)
#define DZ_B_TESTED      6     // zones tested for the first time on this bar
#define DZ_B_RETESTS     7     // retests of already tested zones on this bar
#define DZ_B_BROKEN      8     // zones broken on this bar
#define DZ_B_LIVE_DEM    9     // live demand zones after this bar
#define DZ_B_LIVE_SUP    10    // live supply zones after this bar
#define DZ_B_DEM_BASE    11    // bars from the break bar back to the base candle of a new demand zone
#define DZ_B_SUP_BASE    12
#define DZ_B_COUNT       13

#define DZ_FRESH    0
#define DZ_TESTED   1
#define DZ_BROKEN   2
#define DZ_DROPPED  3

struct SDzZone
  {
   int      dir;
   double   top,bot,mid;
   int      t0;              // base candle
   int      born;            // break bar (the zone exists from the next bar on)
   int      state;
   int      end;             // broken or dropped, -1 live
   int      retests;         // entries counted: 1 = the first test
   bool     inside;
  };
struct SDzSwing { int i; double p; bool broken; };
struct SDzBreak { int dir; double level; int frm; int at; int zone; };

class CDzEngine
  {
public:
   //--- settings
   int      swing,atr_period,search,zone_mode,test_mode,break_mode,max_live,base_mode;
   double   disp_mult,body_pct;
   //--- results
   SDzZone  zones[];
   SDzBreak breaks[];
   int      nz,nb;
   int      done;                       // last bar processed, -1 = none
private:
   SDzSwing m_sw[2];                    // newest swing: [0] high, [1] low
   int      m_live[];
   int      m_nlive;
   double   m_atr,m_atr_sum;
   int      m_active[2];

   bool IsSwing(const double &h[],const double &l[],const int p,const int side)
     {
      for(int k=1; k<=swing; k++)
        {
         if(side>0 && (h[p-k]>=h[p] || h[p+k]>h[p]))
            return(false);
         if(side<0 && (l[p-k]<=l[p] || l[p+k]<l[p]))
            return(false);
        }
      return(true);
     }
   bool Reaches(const SDzZone &z,const double h,const double l)
     {
      double tol=MathAbs(z.mid)*1e-10;  // a wick exactly on the middle counts ((top+bot)/2 can be 1 ulp off)
      if(z.dir>0)
         return(test_mode==0 ? l<=z.top : test_mode==1 ? l<=z.mid+tol : l<=z.bot);
      return(test_mode==0 ? h>=z.bot : test_mode==1 ? h>=z.mid-tol : h>=z.top);
     }
   bool Breaks(const SDzZone &z,const double h,const double l,const double c)
     {
      if(z.dir>0)
         return(break_mode==0 ? c<z.bot : l<z.bot);
      return(break_mode==0 ? c>z.top : h>z.top);
     }
   void Drop(const int side,const int i)
     {
      for(int q=0; q<m_nlive; q++)
        {
         int z=m_live[q];
         if((zones[z].dir>0 ? 0 : 1)!=side)
            continue;
         zones[z].state=DZ_DROPPED;
         zones[z].end=i;
         for(int k=q; k<m_nlive-1; k++)
            m_live[k]=m_live[k+1];
         m_nlive--;
         m_active[side]--;
         return;
        }
     }
   int AddZone(const int dir,const double top,const double bot,const int t0,const int born)
     {
      if(nz>=ArraySize(zones))
         ArrayResize(zones,nz+256);
      zones[nz].dir=dir;
      zones[nz].top=top;
      zones[nz].bot=bot;
      zones[nz].mid=(top+bot)/2.0;
      zones[nz].t0=t0;
      zones[nz].born=born;
      zones[nz].state=DZ_FRESH;
      zones[nz].end=-1;
      zones[nz].retests=0;
      zones[nz].inside=false;
      if(m_nlive>=ArraySize(m_live))
         ArrayResize(m_live,m_nlive+256);
      m_live[m_nlive++]=nz;
      int side=(dir>0 ? 0 : 1);
      m_active[side]++;
      if(max_live>0 && m_active[side]>max_live)
         Drop(side,born);
      return(nz++);
     }

public:
   void Defaults(void)
     {
      swing=3; atr_period=14; search=12; zone_mode=0; test_mode=0; break_mode=0; max_live=12; base_mode=0;
      disp_mult=1.0; body_pct=55.0;
     }
   void Reset(void)
     {
      ArrayResize(zones,0,1024);
      ArrayResize(breaks,0,256);
      ArrayResize(m_live,0,256);
      nz=nb=m_nlive=0;
      for(int s=0; s<2; s++)
        {
         m_sw[s].i=-1;
         m_sw[s].p=0;
         m_sw[s].broken=true;
        }
      m_atr=EMPTY_VALUE;
      m_atr_sum=0;
      m_active[0]=m_active[1]=0;
      done=-1;
     }

   //--- process closed bar i (bars 0..i are known); out[] gets the DZ_B_* values for it
   void Step(const int i,const datetime &t[],const double &o[],const double &h[],const double &l[],const double &c[],double &out[])
     {
      ArrayInitialize(out,EMPTY_VALUE);
      done=i;
      double prev=m_atr;
      double tr=(i==0 ? h[i]-l[i] : MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1]))));
      if(i<atr_period-1)
         m_atr_sum+=tr;
      else
         if(i==atr_period-1)
           {
            m_atr_sum+=tr;
            m_atr=m_atr_sum/atr_period;
           }
         else
            m_atr=(m_atr*(atr_period-1)+tr)/atr_period;
      if(prev!=EMPTY_VALUE && prev>0)
        {
         //--- 1. zones made before this bar: broken, tested, retested
         int n_test=0,n_re=0,n_brk=0,keep=0;
         for(int q=0; q<m_nlive; q++)
           {
            int z=m_live[q];
            bool reach=Reaches(zones[z],h[i],l[i]);
            if(Breaks(zones[z],h[i],l[i],c[i]))
              {
               zones[z].state=DZ_BROKEN;
               zones[z].end=i;
               n_brk++;
               m_active[zones[z].dir>0 ? 0 : 1]--;
               continue;
              }
            if(reach)
              {
               if(zones[z].state==DZ_FRESH)
                 {
                  zones[z].state=DZ_TESTED;
                  zones[z].retests=1;
                  n_test++;
                 }
               else
                  if(!zones[z].inside)
                    {
                     zones[z].retests++;
                     n_re++;
                    }
              }
            zones[z].inside=reach;
            m_live[keep++]=z;
           }
         m_nlive=keep;
         out[DZ_B_TESTED]=n_test;
         out[DZ_B_RETESTS]=n_re;
         out[DZ_B_BROKEN]=n_brk;
         //--- 2. a break of the newest swing, and its zone
         for(int d=1; d>=-1; d-=2)
           {
            int s=(d>0 ? 0 : 1);
            if(m_sw[s].broken || c[i]*d<=m_sw[s].p*d)
               continue;
            m_sw[s].broken=true;
            out[d>0 ? DZ_B_BREAK_UP : DZ_B_BREAK_DN]=m_sw[s].p;
            double rng=h[i]-l[i],body=MathAbs(c[i]-o[i]);
            //--- a body of exactly body_pct % (common with decimal prices) counts: 1e-9 of the range absorbs the last-bit
            //--- difference between compilers in body_pct/100*rng
            bool impulse=(rng>0 && rng>=disp_mult*prev && body>=body_pct/100.0*rng-rng*1e-9 && (c[i]-o[i])*d>0);
            int base=-1,lo_j=MathMax(0,i-search),from_j=i-1;
            if(impulse && base_mode==1)
               for(int j=i-2; j>=lo_j; j--)                // the move's start: the lowest low (highest high), latest on a tie
                  if(d>0 ? l[j]<l[from_j] : h[j]>h[from_j])
                     from_j=j;
            if(impulse)
               for(int j=from_j; j>=lo_j; j--)
                  if((c[j]-o[j])*d<0)
                    {
                     base=j;
                     break;
                    }
            int zi=-1;
            if(base>=0)
              {
               double bt=MathMax(o[base],c[base]),bb=MathMin(o[base],c[base]);
               double top=(zone_mode==1 ? bt : (zone_mode==2 && d>0 ? bt : h[base]));
               double bot=(zone_mode==1 ? bb : (zone_mode==2 && d<0 ? bb : l[base]));
               if(top>bot)
                 {
                  zi=AddZone(d,top,bot,base,i);
                  out[d>0 ? DZ_B_DEM_TOP : DZ_B_SUP_TOP]=top;
                  out[d>0 ? DZ_B_DEM_BOT : DZ_B_SUP_BOT]=bot;
                  out[d>0 ? DZ_B_DEM_BASE : DZ_B_SUP_BASE]=i-base;
                 }
              }
            if(nb>=ArraySize(breaks))
               ArrayResize(breaks,nb+128);
            breaks[nb].dir=d;
            breaks[nb].level=m_sw[s].p;
            breaks[nb].frm=m_sw[s].i;
            breaks[nb].at=i;
            breaks[nb].zone=zi;
            nb++;
           }
         out[DZ_B_LIVE_DEM]=m_active[0];
         out[DZ_B_LIVE_SUP]=m_active[1];
        }
      //--- 3. the swing `swing` bars back is known from the next bar on
      int p=i-swing;
      if(p>=swing)
         for(int side=1; side>=-1; side-=2)
            if(IsSwing(h,l,p,side))
              {
               int s=(side>0 ? 0 : 1);
               m_sw[s].i=p;
               m_sw[s].p=(side>0 ? h[p] : l[p]);
               m_sw[s].broken=false;
              }
     }
  };

#endif
//+------------------------------------------------------------------+
