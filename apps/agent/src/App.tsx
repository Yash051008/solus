// Solus Field: the offline-first agent app. Every action is saved to the phone's outbox first and synced
// when there is signal. The server decides; rejected events stay visible and go to the manager's review queue.
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as Crypto from 'expo-crypto';
import * as Location from 'expo-location';
import { AgentEngine, REJECTION_TEXT, createSupabaseTransport, minimalFromSupabase, type FieldState, type Fix, type OutboxEvent } from '@solus/agent-core';
import { configured, supabase } from './supabase';
import { openStore } from './sqlite-store';

type Screen = 'home' | 'sell' | 'checkin' | 'activity' | 'request';
type SkuNames = Record<string, { code: string; name: string; cartonPieces: number | null }>;

const store = openStore();

export default function App() {
  const [ready, setReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);
  const [orgId, setOrgId] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      const { data } = await supabase.auth.getSession();
      setSignedIn(Boolean(data.session));
      setOrgId(await store.getMeta('org_id'));
      setReady(true);
    })();
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(Boolean(s)));
    return () => data.subscription.unsubscribe();
  }, []);

  if (!ready) return <Center><ActivityIndicator /></Center>;
  if (!configured) return <Center><Text style={s.h1}>Not configured</Text><Text style={s.muted}>Run `npm run agent:env` on the Mac, then restart Expo.</Text></Center>;
  if (!signedIn || !orgId) return <Login onDone={(id) => setOrgId(id)} />;
  return <Field orgId={orgId} onSignOut={async () => { await supabase.auth.signOut(); setSignedIn(false); }} />;
}

function Login({ onDone }: { onDone: (orgId: string) => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  async function submit() {
    setBusy(true); setError('');
    const { data, error: e } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (e || !data.user) { setError('Email or password is incorrect.'); setBusy(false); return; }
    const { data: m } = await supabase.from('memberships').select('org_id, role, status').eq('user_id', data.user.id).eq('role', 'agent').eq('status', 'active');
    const org = (m as { org_id: string }[] | null)?.[0]?.org_id;
    if (!org) { setError('This account is not an active agent.'); await supabase.auth.signOut(); setBusy(false); return; }
    await store.setMeta('org_id', org);
    setBusy(false);
    onDone(org);
  }
  return (
    <SafeAreaView style={s.screen}>
      <StatusBar style="auto" />
      <Text style={s.h1}>Solus Field</Text>
      <Text style={s.muted}>Sign in once with signal. After that the app works offline.</Text>
      <TextInput style={s.input} placeholder="Email" autoCapitalize="none" keyboardType="email-address" value={email} onChangeText={setEmail} />
      <TextInput style={s.input} placeholder="Password" secureTextEntry value={password} onChangeText={setPassword} />
      {error ? <Text style={s.error}>{error}</Text> : null}
      <Button label={busy ? 'Signing in…' : 'Sign in'} onPress={submit} disabled={busy} />
    </SafeAreaView>
  );
}

function Field({ orgId, onSignOut }: { orgId: string; onSignOut: () => void }) {
  const engine = useMemo(() => new AgentEngine({
    store, uuid: () => Crypto.randomUUID(),
    transport: createSupabaseTransport(minimalFromSupabase(supabase), orgId),
  }), [orgId]);
  const [screen, setScreen] = useState<Screen>('home');
  const [state, setState] = useState<FieldState | null>(null);
  const [events, setEvents] = useState<OutboxEvent[]>([]);
  const [carried, setCarried] = useState<Map<string, number>>(new Map());
  const [skus, setSkus] = useState<SkuNames>({});
  const [status, setStatus] = useState('');
  const [syncing, setSyncing] = useState(false);

  const refresh = useCallback(async () => {
    await engine.signIn(orgId);
    setState(await engine.state());
    setEvents(await store.all());
    setCarried(await engine.estimatedCarried());
    setSkus(JSON.parse((await store.getMeta('skus')) ?? '{}') as SkuNames);
  }, [engine, orgId]);

  const sync = useCallback(async () => {
    setSyncing(true);
    try {
      const r = await engine.sync();
      if (r.online) {
        const { data } = await supabase.from('skus').select('id, code, name, sku_uom(uom_code, pieces_per_uom)');
        const names: SkuNames = {};
        for (const k of (data ?? []) as { id: string; code: string; name: string; sku_uom: { uom_code: string; pieces_per_uom: number }[] }[]) {
          names[k.id] = { code: k.code, name: k.name, cartonPieces: k.sku_uom.find((u) => u.uom_code === 'carton')?.pieces_per_uom ?? null };
        }
        await store.setMeta('skus', JSON.stringify(names));
        setStatus(`Synced: ${r.accepted} accepted, ${r.rejected} sent to review${r.deferred ? `, ${r.deferred} waiting` : ''}.`);
      } else {
        setStatus('No signal. Your records are saved on the phone and will sync later.');
      }
    } catch (e) {
      setStatus(e instanceof Error ? e.message : 'Sync failed.');
    } finally {
      setSyncing(false);
      await refresh();
    }
  }, [engine, refresh]);

  useEffect(() => { void refresh().then(sync); }, [refresh, sync]);

  const pending = events.filter((e) => e.status === 'pending').length;
  const rejected = events.filter((e) => e.status === 'rejected').length;
  const nameOf = (id: string) => skus[id]?.name ?? id.slice(0, 8);

  if (screen === 'sell' || screen === 'checkin') {
    return <Visit kind={screen} engine={engine} state={state} carried={carried} nameOf={nameOf}
      onDone={async (msg) => { setStatus(msg); setScreen('home'); await refresh(); void sync(); }} onBack={() => setScreen('home')} />;
  }
  if (screen === 'activity') return <Activity events={events} nameOf={nameOf} onBack={() => setScreen('home')} />;
  if (screen === 'request') return <RequestStock orgId={orgId} skus={skus} onDone={async (msg) => { setStatus(msg); setScreen('home'); await sync(); }} onBack={() => setScreen('home')} />;

  return (
    <SafeAreaView style={s.screen}>
      <StatusBar style="auto" />
      <ScrollView contentContainerStyle={{ gap: 12 }}>
        <Text style={s.h1}>Solus Field</Text>
        {status ? <Text style={s.note}>{status}</Text> : null}
        <View style={s.card}>
          <Text style={s.h2}>Stock run: {state?.shipment ? state.shipment.status.replaceAll('_', ' ') : 'none'}</Text>
          {state?.shipment?.note ? <Text style={s.error}>{state.shipment.note}</Text> : null}
          {state?.shipment?.status === 'awaiting_acceptance' ? <Text style={s.muted}>Go to the warehouse. Read the SMS code to the staff in person.</Text> : null}
          {[...carried].filter(([, n]) => n !== 0).map(([id, n]) => (
            <Text key={id} style={n < 0 ? s.error : undefined}>{nameOf(id)}: {n} pcs{n < 0 ? ' (more than recorded: needs review)' : ''}</Text>
          ))}
          {state?.fetchedAt ? <Text style={s.muted}>Server data from {new Date(state.fetchedAt).toLocaleString()}</Text> : null}
        </View>
        <Button label={syncing ? 'Syncing…' : `Sync now${pending ? ` (${pending} waiting)` : ''}`} onPress={sync} disabled={syncing} />
        {state?.shipment?.status === 'open' ? <Button label="Record a cash sale" onPress={() => setScreen('sell')} /> : null}
        <Button label="Check in at a shop" onPress={() => setScreen('checkin')} secondary />
        <Button label={`Activity${rejected ? ` (${rejected} in review)` : ''}`} onPress={() => setScreen('activity')} secondary />
        {!state?.shipment ? <Button label="Request stock (needs signal)" onPress={() => setScreen('request')} secondary /> : null}
        <Button label="Sign out" onPress={onSignOut} secondary />
      </ScrollView>
    </SafeAreaView>
  );
}

function Visit({ kind, engine, state, carried, nameOf, onDone, onBack }: {
  kind: 'sell' | 'checkin'; engine: AgentEngine; state: FieldState | null; carried: Map<string, number>;
  nameOf: (id: string) => string; onDone: (msg: string) => void; onBack: () => void;
}) {
  const [shopId, setShopId] = useState<string | null>(null);
  const [qty, setQty] = useState<Record<string, string>>({});
  const [fix, setFix] = useState<Fix | null>(null);
  const [hint, setHint] = useState('');
  const [error, setError] = useState('');

  async function locate() {
    setError('');
    const perm = await Location.requestForegroundPermissionsAsync();
    if (perm.status !== 'granted') { setError('Location permission is needed to prove you are at the shop.'); return; }
    const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
    const f = { lat: pos.coords.latitude, lng: pos.coords.longitude, accuracyM: pos.coords.accuracy };
    setFix(f);
    if (shopId) {
      const g = await engine.geofenceHint(shopId, f);
      setHint(g ? (g.ok ? `At the shop (${g.distanceM} m).` : g.reason === 'low_accuracy' ? 'GPS too weak: wait for a better fix.' : `About ${g.distanceM} m from the shop.`) : '');
    }
  }

  async function save() {
    if (!shopId) { setError('Choose the shop.'); return; }
    try {
      if (kind === 'checkin') {
        await engine.checkIn(shopId, fix);
        onDone('Check-in saved.');
        return;
      }
      const lines = Object.entries(qty).map(([skuId, v]) => ({ skuId, qtyPieces: Number(v || '0') })).filter((l) => l.qtyPieces > 0);
      const { exceedsEstimate } = await engine.recordSale(shopId, lines, fix);
      onDone(exceedsEstimate ? 'Sale saved. It is more than your recorded stock, so your manager will review it.' : 'Sale saved.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save.');
    }
  }

  return (
    <SafeAreaView style={s.screen}>
      <ScrollView contentContainerStyle={{ gap: 10 }}>
        <Text style={s.h1}>{kind === 'sell' ? 'Cash sale' : 'Check in'}</Text>
        <Text style={s.h2}>Shop</Text>
        {(state?.shops ?? []).map((shop) => (
          <Pressable key={shop.id} onPress={() => { setShopId(shop.id); setHint(''); }} style={[s.choice, shopId === shop.id && s.choiceOn]}>
            <Text>{shop.name}</Text>
          </Pressable>
        ))}
        {kind === 'sell' ? (
          <>
            <Text style={s.h2}>Pieces sold</Text>
            {[...carried].filter(([, n]) => n > 0).map(([id, n]) => (
              <View key={id} style={s.row}>
                <Text style={{ flex: 1 }}>{nameOf(id)} (have {n})</Text>
                <TextInput style={[s.input, { width: 80 }]} keyboardType="number-pad" value={qty[id] ?? ''} onChangeText={(v) => setQty({ ...qty, [id]: v.replace(/\D/g, '') })} />
              </View>
            ))}
          </>
        ) : null}
        <Button label={fix ? `Location ±${Math.round(fix.accuracyM ?? 0)} m: refresh` : 'Get my location'} onPress={locate} secondary />
        {hint ? <Text style={s.note}>{hint}</Text> : null}
        {error ? <Text style={s.error}>{error}</Text> : null}
        <Button label="Save (works offline)" onPress={save} />
        <Button label="Back" onPress={onBack} secondary />
      </ScrollView>
    </SafeAreaView>
  );
}

function Activity({ events, nameOf, onBack }: { events: OutboxEvent[]; nameOf: (id: string) => string; onBack: () => void }) {
  return (
    <SafeAreaView style={s.screen}>
      <ScrollView contentContainerStyle={{ gap: 8 }}>
        <Text style={s.h1}>Activity</Text>
        {[...events].reverse().map((e) => (
          <View key={e.eventId} style={s.card}>
            <Text style={s.h2}>#{e.seq} {e.type === 'sale.recorded' ? 'Sale' : 'Check-in'}: {e.status}</Text>
            {e.type === 'sale.recorded'
              ? (e.payload['lines'] as { sku_id: string; qty_pieces: number }[]).map((l) => <Text key={l.sku_id}>{nameOf(l.sku_id)} × {l.qty_pieces}</Text>)
              : null}
            <Text style={s.muted}>{new Date(e.clientTs).toLocaleString()}</Text>
            {e.reason ? <Text style={s.error}>{REJECTION_TEXT[e.reason] ?? e.reason}</Text> : null}
          </View>
        ))}
        <Button label="Back" onPress={onBack} secondary />
      </ScrollView>
    </SafeAreaView>
  );
}

function RequestStock({ orgId, skus, onDone, onBack }: { orgId: string; skus: SkuNames; onDone: (msg: string) => void; onBack: () => void }) {
  const [warehouses, setWarehouses] = useState<{ id: string; name: string }[]>([]);
  const [wh, setWh] = useState<string | null>(null);
  const [sku, setSku] = useState<string | null>(null);
  const [cartons, setCartons] = useState('');
  const [error, setError] = useState('');
  useEffect(() => {
    void supabase.from('v_warehouses').select('id, name').eq('org_id', orgId).eq('active', true)
      .then(({ data }) => setWarehouses((data ?? []) as { id: string; name: string }[]));
  }, [orgId]);
  async function submit() {
    if (!wh || !sku || !Number(cartons)) { setError('Choose a warehouse, a product and a number of cartons.'); return; }
    const { error: e } = await supabase.schema('app').rpc('request_stock', {
      p_warehouse_id: wh, p_lines: [{ sku_id: sku, uom_code: 'carton', uom_qty: Number(cartons) }],
    });
    if (e) { setError(e.message); return; }
    onDone('Request sent to your branch manager.');
  }
  return (
    <SafeAreaView style={s.screen}>
      <ScrollView contentContainerStyle={{ gap: 8 }}>
        <Text style={s.h1}>Request stock</Text>
        {warehouses.map((w) => <Pressable key={w.id} onPress={() => setWh(w.id)} style={[s.choice, wh === w.id && s.choiceOn]}><Text>{w.name}</Text></Pressable>)}
        {Object.entries(skus).filter(([, v]) => v.cartonPieces).map(([id, v]) => (
          <Pressable key={id} onPress={() => setSku(id)} style={[s.choice, sku === id && s.choiceOn]}><Text>{v.code}: {v.name}</Text></Pressable>
        ))}
        <TextInput style={s.input} placeholder="Cartons" keyboardType="number-pad" value={cartons} onChangeText={setCartons} />
        {error ? <Text style={s.error}>{error}</Text> : null}
        <Button label="Send request" onPress={submit} />
        <Button label="Back" onPress={onBack} secondary />
      </ScrollView>
    </SafeAreaView>
  );
}

function Button({ label, onPress, secondary, disabled }: { label: string; onPress: () => void; secondary?: boolean; disabled?: boolean }) {
  return (
    <Pressable onPress={onPress} disabled={disabled} style={[s.button, secondary && s.buttonSecondary, disabled && { opacity: 0.5 }]}>
      <Text style={secondary ? s.buttonTextSecondary : s.buttonText}>{label}</Text>
    </Pressable>
  );
}

function Center({ children }: { children: React.ReactNode }) {
  return <SafeAreaView style={[s.screen, { justifyContent: 'center', alignItems: 'center' }]}>{children}</SafeAreaView>;
}

const s = StyleSheet.create({
  screen: { flex: 1, padding: 16, gap: 12, backgroundColor: '#f7f7f5' },
  h1: { fontSize: 24, fontWeight: '700', marginTop: 8 },
  h2: { fontSize: 16, fontWeight: '600' },
  muted: { color: '#6b6b66' },
  note: { backgroundColor: '#e7f4ec', padding: 10, borderRadius: 8 },
  error: { color: '#a3261e' },
  card: { backgroundColor: '#fff', borderRadius: 10, padding: 12, gap: 4, borderWidth: 1, borderColor: '#e3e3de' },
  input: { borderWidth: 1, borderColor: '#d0d0ca', borderRadius: 8, padding: 10, backgroundColor: '#fff' },
  row: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  choice: { padding: 12, borderRadius: 8, borderWidth: 1, borderColor: '#d0d0ca', backgroundColor: '#fff' },
  choiceOn: { borderColor: '#1f6f4a', backgroundColor: '#e7f4ec' },
  button: { backgroundColor: '#1f6f4a', padding: 14, borderRadius: 8, alignItems: 'center' },
  buttonSecondary: { backgroundColor: 'transparent', borderWidth: 1, borderColor: '#d0d0ca' },
  buttonText: { color: '#fff', fontWeight: '600' },
  buttonTextSecondary: { color: '#1c1c1a', fontWeight: '600' },
});
