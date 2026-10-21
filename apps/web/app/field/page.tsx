import { Shell } from '@/components/shell';
import { requireSession } from '@/lib/session';

export default async function FieldPage() {
  const { memberships } = await requireSession();
  const field = memberships.filter((m) => (m.role === 'agent' || m.role === 'driver') && m.status === 'active');
  return (
    <Shell>
      <h1>Field staff</h1>
      <p>Agents and drivers work in the <strong>Solus field app</strong> (works offline). It arrives in Phase 5b.</p>
      <div className="panel"><ul>{field.map((m) => <li key={`${m.orgId}-${m.role}`}>{m.role} at {m.orgName}</li>)}</ul></div>
    </Shell>
  );
}
