
libname brt "C:\Users\user\Documents\GitHub\BRT\Group assignment"; RUN;
proc sql;
*Delay and Temperature sheet;
create table brt.delays_temp as
select b.month
	,"all" as origin
	,avg(case when b.arr_delay>0 then b.arr_delay end) as avgarrdelay
	,avg(case when b.dep_delay>0 then b.dep_delay end) as avgdepdelay
	,avg(c.temp) as avgtemp
from brt.flights b,brt.weather c
where b.time_hour = c.time_hour
and (b.arr_delay>0 or b.dep_delay>0)
group by 1
	union
select b.month
	,b.origin
	,avg(case when b.arr_delay>0 then b.arr_delay end) as avgarrdelay
	,avg(case when b.dep_delay>0 then b.dep_delay end) as avgdepdelay
	,avg(c.temp) as avgtemp
from brt.flights b,brt.weather c
where b.time_hour = c.time_hour
and (b.arr_delay>0 or b.dep_delay>0)
group by 1,2;

proc sql;
*Delay and Number of Flights sheet;
create table brt.delays_flights as
select b.month
	,"all" as origin
	,avg(((case when b.arr_delay>0 then b.arr_delay end)+(case when b.dep_delay>0 then b.dep_delay end))/2) as avg_delay
	,avg(c.temp) as avgtemp
	,count(flight) as n_flight
from brt.flights b,brt.weather c
where b.time_hour = c.time_hour
and (b.arr_delay>0 or b.dep_delay>0)
group by 1
	union
select b.month
	,b.origin
	,avg(((case when b.arr_delay>0 then b.arr_delay end)+(case when b.dep_delay>0 then b.dep_delay end))/2) as avg_delay
	,avg(c.temp) as avgtemp
	,count(flight) as n_flight
from brt.flights b,brt.weather c
where b.time_hour = c.time_hour
and (b.arr_delay>0 or b.dep_delay>0)
group by 1,2;

proc sql;
*"Weekday" sheet;
create table brt.wd_flight (index=(origin)) as
select 
	f.origin
	,datepart(f.time_hour) as date format DDMMYY10.
	,case when weekday(datepart(f.time_hour))=1 then 7
		else weekday(datepart(f.time_hour))-1 end as weekday /*1=Sunday, transformed to 7=Sunday*/
	,count(f.flight) as n_flights
	,coalesce(sum(case when f.dep_delay>0 then f.dep_delay else 0 end),0) as avg_delay_pos
from brt.flights f 
group by 1,2,3;

proc sql;
*Hour sheet;
create table brt.delays_hour (index=(composite=(origin hour))) as
select
	f.origin
	,f.hour
	,count(f.flight)/count(distinct f.day) as n_flights
	,coalesce(avg(case when f.arr_delay>0 then f.arr_delay end),0) as arr_delay
	,coalesce(avg(case when f.dep_delay>0 then f.dep_delay end),0) as dep_delay
from brt.flights f
where (f.arr_delay>0 or f.dep_delay>0)
group by 1,2;

proc sql;
*Intermediate table to create routes, not used on Tableau;
create table brt.routeids (index=(id/unique)) as
	select monotonic() as id, origin, dest
	from ( 
		select distinct
		f.origin
		,f.dest
		from brt.flights f ) t1;

proc sql;
*448 rows, used to create routes on "Top 10 Slowest Routes" sheet;
create table brt.routes (index=(composite=(id airport))) as
	select ri.id, ri.origin as airport,a.lat,a.lon, 1 as order
	from brt.routeids ri
	left join brt.airports a on a.faa=ri.origin
		union
	select ri.id, ri.dest as airport,a.lat,a.lon, 2 as order
	from brt.routeids ri
	left join brt.airports a on a.faa=ri.dest;

proc sql;
*Table used to create a ranking, not used in Tableau;
create table brt.test (index=(dest)) as
select * 
from
(select 
	f.dest
	,trim(put(month, 6.)) as month
	,f.origin
	,coalesce(avg(case when f.arr_delay>0 then f.arr_delay end),0) as arr_delay
	,coalesce(avg(case when f.dep_delay>0 then f.dep_delay end),0) as dep_delay
	,count(f.flight) as n_flight
	from brt.flights f
	where (f.arr_delay>0 or f.dep_delay>0)
		group by 1,2,3
	union
select 
	f.dest
	,put(0,6.) as month
	,f.origin
	,coalesce(avg(case when f.arr_delay>0 then f.arr_delay end),0) as arr_delay
	,coalesce(avg(case when f.dep_delay>0 then f.dep_delay end),0) as dep_delay
	,count(f.flight) as n_flight
	from brt.flights f
	where (f.arr_delay>0 or f.dep_delay>0)
		group by 1,3)
		order by 2 asc,4 desc;

*Ranking procedure to select worst 10 routes, not used in Tableau;
proc rank data=brt.test descending out=brt.r_test; 
by month;
var arr_delay;
 ranks ranking;
run; 

proc sql;
*Table used for Top 10 Slowest Routes;
create table brt.top10 (index=(dest)) as
select 
	id.id,
	r.dest,
	r.origin,
	input(trim(r.month),BEST12.) as month,
	r.ranking,
	r.arr_delay,
	r.dep_delay,
	r.n_flight
	from brt.r_test r
	left join brt.routeids id on id.origin=r.origin and id.dest=r.dest
where r.ranking<=10
order by id asc;

proc sql;
*Table used for Airlines Dashboard;
create table brt.manuf (index=(origin name date)) as
select a.name,f.origin,datepart(f.time_hour) as date format DDMMYY10.,f.month,p.engines,
case when dep_delay>0 and arr_delay>0 then "Both delayed" 
		when dep_delay>0 and dep_delay>arr_delay then "Only departure delayed" 
		when arr_delay>0 and arr_delay>dep_delay then "Only arrival delayed"
		else "Both on time" end as delay_flag,
coalesce(sum(case when f.dep_delay>0 then f.dep_delay end),0) as dep_delay,
coalesce(sum(case when f.arr_delay>0 then f.arr_delay end),0) as arr_delay,
count(f.flight) as n_flight,
count(distinct p.tailnum) as planes
from brt.flights f 
join brt.planes p on f.tailnum=p.tailnum
join brt.airlines a on a.carrier=f.carrier
group by 1,2,3,4,5,6;
