-- Server-side geofence: distances on the spheroid, configurable radius/accuracy, fails closed.
-- retailer-01 (Lagos Prime customer) is at lat 6.6200, lng 3.3450. 0.0009 deg latitude ~ 99.5 m.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create temp table g as
select (select id from public.organisations where slug = 'lagos-prime') as lp,
       (select id from public.organisations where slug = 'abuja-central') as ac,
       (select id from public.organisations where slug = 'retailer-01') as r01,
       (select id from public.organisations where slug = 'retailer-13') as r13;

select results_eq($$ select ok, reason, distance_m, radius_m from g, app.evaluate_geofence(g.lp, g.r01, 6.6200, 3.3450, 10) $$,
                  $$ values (true, 'ok', 0, 150) $$, 'at the shop with a good fix: ok, 0 m, default radius 150 m');
select results_eq($$ select ok, reason, distance_m between 95 and 105 from g, app.evaluate_geofence(g.lp, g.r01, 6.6209, 3.3450, 10) $$,
                  $$ values (true, 'ok', true) $$, '~100 m away: inside the radius');
select results_eq($$ select ok, reason, distance_m between 290 and 310 from g, app.evaluate_geofence(g.lp, g.r01, 6.6227, 3.3450, 10) $$,
                  $$ values (false, 'outside_radius', true) $$, '~300 m away: outside the radius');
select results_eq($$ select ok, reason from g, app.evaluate_geofence(g.lp, g.r01, 6.6200, 3.3450, 80) $$,
                  $$ values (false, 'low_accuracy') $$, 'at the shop but GPS accuracy 80 m > 50 m: fails closed');
select results_eq($$ select ok, reason from g, app.evaluate_geofence(g.lp, g.r01, 6.6200, 3.3450, null) $$,
                  $$ values (false, 'low_accuracy') $$, 'missing accuracy fails closed');
select results_eq($$ select ok, reason from g, app.evaluate_geofence(g.lp, g.r13, 9.0800, 7.4700, 5) $$,
                  $$ values (false, 'not_a_customer') $$, 'a shop that is not this distributor''s customer fails');
select throws_ok($$ select * from g, app.evaluate_geofence(g.lp, g.r01, 6.62, 999, 5) $$, 'SOL05', null,
                 'invalid coordinates raise');

update public.organisations set geofence_radius_m = 500, geofence_max_accuracy_m = 100 where slug = 'lagos-prime';
select results_eq($$ select ok, radius_m, max_accuracy_m from g, app.evaluate_geofence(g.lp, g.r01, 6.6227, 3.3450, 80) $$,
                  $$ values (true, 500, 100) $$, 'distributor-configured 500 m / 100 m: the same 300 m, 80 m fix passes');
update public.organisations set geofence_radius_m = null, geofence_max_accuracy_m = null where slug = 'lagos-prime';
select throws_ok($$ update public.organisations set geofence_radius_m = 200 where slug = 'retailer-01' $$, '23514', null,
                 'geofence settings exist only on distributors');

-- Client-callable variant is scoped
grant select on g to authenticated;
select set_config('request.jwt.claims', json_build_object('sub', (select id from auth.users where email = 'lp.agent1@solus.test'))::text, true);
set local role authenticated;
select results_eq($$ select ok, reason from g, app.check_geofence(g.lp, g.r01, 6.6200, 3.3450, 10) $$,
                  $$ values (true, 'ok') $$, 'agent checks a shop in their territory');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', (select id from auth.users where email = 'lp.agent3@solus.test'))::text, true);
set local role authenticated;
select throws_ok($$ select * from g, app.check_geofence(g.lp, g.r01, 6.62, 3.345, 10) $$, 'SOL03', null,
                 'an agent of another territory cannot probe that shop''s location');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', (select id from auth.users where email = 'ac.agent1@solus.test'))::text, true);
set local role authenticated;
select throws_ok($$ select * from g, app.check_geofence(g.lp, g.r01, 6.62, 3.345, 10) $$, 'SOL03', null,
                 'another distributor''s agent cannot use this distributor''s geofence');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', (select id from auth.users where email = 'retailer01@solus.test'))::text, true);
set local role authenticated;
select throws_ok($$ select * from g, app.check_geofence(g.lp, g.r01, 6.62, 3.345, 10) $$, 'SOL03', null,
                 'retailers cannot call the geofence check');
select throws_ok($$ select * from g, app.evaluate_geofence(g.lp, g.r01, 6.62, 3.345, 10) $$, '42501', null,
                 'the unscoped evaluator is internal only');
reset role;

select * from finish();
rollback;
