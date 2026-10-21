-- app.round_div: the only rounding function. Every mode at ties, negatives, extremes and errors.
begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

-- exact division never rounds
select is(app.round_div(10, 5), 2::bigint, 'exact: 10/5 = 2');
select is(app.round_div(-10, 5, 'floor'), -2::bigint, 'exact negative floor: -10/5 = -2');

-- half_even (default): ties go to the even neighbour
select is(app.round_div(5, 2), 2::bigint, 'half_even  2.5 -> 2');
select is(app.round_div(7, 2), 4::bigint, 'half_even  3.5 -> 4');
select is(app.round_div(-5, 2), -2::bigint, 'half_even -2.5 -> -2');
select is(app.round_div(-7, 2), -4::bigint, 'half_even -3.5 -> -4');
select is(app.round_div(1, 2), 0::bigint, 'half_even  0.5 -> 0');
select is(app.round_div(3, 2), 2::bigint, 'half_even  1.5 -> 2');
select is(app.round_div(26, 10), 3::bigint, 'half_even  2.6 -> 3');
select is(app.round_div(24, 10), 2::bigint, 'half_even  2.4 -> 2');
select is(app.round_div(-26, 10), -3::bigint, 'half_even -2.6 -> -3');

-- half_up: ties away from zero
select is(app.round_div(5, 2, 'half_up'), 3::bigint, 'half_up  2.5 -> 3');
select is(app.round_div(-5, 2, 'half_up'), -3::bigint, 'half_up -2.5 -> -3');
select is(app.round_div(24, 10, 'half_up'), 2::bigint, 'half_up  2.4 -> 2');
select is(app.round_div(1, 3, 'half_up'), 0::bigint, 'half_up  0.333 -> 0');
select is(app.round_div(2, 3, 'half_up'), 1::bigint, 'half_up  0.667 -> 1');

-- floor / ceil
select is(app.round_div(7, 2, 'floor'), 3::bigint, 'floor  3.5 -> 3');
select is(app.round_div(-7, 2, 'floor'), -4::bigint, 'floor -3.5 -> -4');
select is(app.round_div(7, 2, 'ceil'), 4::bigint, 'ceil  3.5 -> 4');
select is(app.round_div(-7, 2, 'ceil'), -3::bigint, 'ceil -3.5 -> -3');
select is(app.round_div(1, 1000000, 'ceil'), 1::bigint, 'ceil tiny positive -> 1');
select is(app.round_div(-1, 1000000, 'floor'), -1::bigint, 'floor tiny negative -> -1');

-- extremes
select is(app.round_div(9223372036854775807, 1), 9223372036854775807::bigint, 'max bigint / 1');
select is(app.round_div(9223372036854775807, 2), 4611686018427387904::bigint, 'max bigint / 2 half_even (odd .5 -> even up)');
select is(app.round_div(-9223372036854775808, 2), -4611686018427387904::bigint, 'min bigint / 2 exact');
select throws_ok($$ select app.round_div(9223372036854775807, 1, 'ceil') + 1 $$, '22003', null,
                 'overflow raises (never wraps)');

-- basis points
select is(app.apply_bps(1000000, 150), 15000::bigint, 'N10,000 at 1.5% = N150.00');
select is(app.apply_bps(333, 150), 5::bigint, '333 kobo at 1.5% = 4.995 -> 5 (half_even)');
select is(app.apply_bps(330, 250), 8::bigint, '330 kobo at 2.5% = 8.25 -> 8');
select throws_ok($$ select app.apply_bps(9223372036854775807, 2) $$, '22003', null,
                 'bps multiply overflow raises');

-- errors
select throws_ok($$ select app.round_div(1, 0) $$, 'SOL05', 'round_div: denominator must be positive', 'zero denominator');
select throws_ok($$ select app.round_div(1, -3) $$, 'SOL05', 'round_div: denominator must be positive', 'negative denominator');
select throws_ok($$ select app.round_div(1, 3, 'bankers') $$, 'SOL05', 'round_div: unknown mode bankers', 'unknown mode');
select throws_ok($$ select app.round_div(null, 3) $$, 'SOL05', 'round_div: null argument', 'null argument');

select * from finish();
rollback;
