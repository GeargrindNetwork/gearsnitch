import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { getAdminUsers, getAdminStats, updateAdminUser, deleteAdminUser, type AdminUser } from '@/lib/api';

function StatCard({ label, value, accent = 'text-zinc-200' }: { label: string; value: string | number; accent?: string }) {
  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardContent className="flex flex-col gap-1 p-4">
        <span className="text-xs font-medium uppercase tracking-wider text-zinc-500">{label}</span>
        <span className={`text-2xl font-bold ${accent}`}>{value}</span>
      </CardContent>
    </Card>
  );
}

function formatDate(iso: string | null) {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(iso));
}

function statusBadge(status: string) {
  switch (status) {
    case 'active': return 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300';
    case 'suspended': return 'border-amber-400/30 bg-amber-400/10 text-amber-300';
    case 'banned': case 'deleted': return 'border-red-400/30 bg-red-400/10 text-red-300';
    default: return 'border-zinc-400/30 bg-zinc-400/10 text-zinc-300';
  }
}

export default function AdminPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [showEdit, setShowEdit] = useState(false);
  const [showDelete, setShowDelete] = useState(false);
  const [selectedUser, setSelectedUser] = useState<AdminUser | null>(null);
  const [editStatus, setEditStatus] = useState('');

  const { data: stats } = useQuery({
    queryKey: ['admin-stats'],
    queryFn: getAdminStats,
    staleTime: 30_000,
  });

  const { data: usersResponse, isLoading } = useQuery({
    queryKey: ['admin-users', page, search],
    queryFn: () => getAdminUsers({ page, limit: 25, search: search || undefined }),
    staleTime: 15_000,
  });

  const users = usersResponse?.data ?? [];
  const meta = usersResponse?.meta ?? { page: 1, limit: 25, total: 0, totalPages: 0 };

  const updateMutation = useMutation({
    mutationFn: () => updateAdminUser(selectedUser!._id, { status: editStatus }),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['admin-users'] }); setShowEdit(false); },
  });

  const deleteMutation = useMutation({
    mutationFn: () => deleteAdminUser(selectedUser!._id),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['admin-users'] }); queryClient.invalidateQueries({ queryKey: ['admin-stats'] }); setShowDelete(false); },
  });

  return (
    <div className="dark min-h-screen bg-black text-white">
      <Header />
      <main className="mx-auto max-w-6xl space-y-6 px-4 pb-16 pt-28 sm:px-6">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">Admin Panel</h1>
          <Badge variant="secondary" className="border-red-500/20 bg-red-500/10 text-red-400">Admin</Badge>
        </div>

        {/* Stats Dashboard */}
        {stats && (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard label="Total Users" value={stats.users.total} accent="text-emerald-400" />
            <StatCard label="Active (30d)" value={stats.users.active30d} accent="text-cyan-400" />
            <StatCard label="New (7d)" value={stats.users.new7d} accent="text-amber-400" />
            <StatCard label="Devices" value={stats.devices.total} />
            <StatCard label="Total Sessions" value={stats.sessions.total} />
            <StatCard label="Active Sessions" value={stats.sessions.active} accent="text-green-400" />
            <StatCard label="Subscriptions" value={stats.subscriptions.active} accent="text-emerald-400" />
            <StatCard label="HR Samples" value={stats.health.heartRateSamples.toLocaleString()} />
          </div>
        )}

        {/* User Search */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between gap-3">
              <CardTitle className="text-sm text-zinc-400">Users ({meta.total})</CardTitle>
              <Input
                placeholder="Search by email or name..."
                value={search}
                onChange={e => { setSearch(e.target.value); setPage(1); }}
                className="max-w-xs border-zinc-700 bg-zinc-950 text-sm text-white"
              />
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {isLoading ? (
              <p className="p-6 text-sm text-zinc-400">Loading users...</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-white/5 text-left text-xs text-zinc-500">
                      <th className="px-4 py-3">Email</th>
                      <th className="px-4 py-3">Name</th>
                      <th className="px-4 py-3">Status</th>
                      <th className="px-4 py-3">Tier</th>
                      <th className="px-4 py-3">Providers</th>
                      <th className="px-4 py-3">Joined</th>
                      <th className="px-4 py-3">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map(user => (
                      <tr key={user._id} className="border-b border-white/5 hover:bg-zinc-800/50">
                        <td className="px-4 py-3 text-zinc-200">{user.email || '—'}</td>
                        <td className="px-4 py-3 text-zinc-300">{user.displayName || '—'}</td>
                        <td className="px-4 py-3">
                          <Badge variant="outline" className={`text-[10px] ${statusBadge(user.status)}`}>{user.status}</Badge>
                        </td>
                        <td className="px-4 py-3 text-zinc-400">{user.subscriptionTier || 'free'}</td>
                        <td className="px-4 py-3 text-zinc-500">{user.authProviders.join(', ') || '—'}</td>
                        <td className="px-4 py-3 text-zinc-500">{formatDate(user.createdAt)}</td>
                        <td className="px-4 py-3">
                          <div className="flex gap-1">
                            <Button size="sm" variant="ghost" className="h-7 px-2 text-xs text-zinc-400" onClick={() => { setSelectedUser(user); setEditStatus(user.status); setShowEdit(true); }}>
                              Edit
                            </Button>
                            <Button size="sm" variant="ghost" className="h-7 px-2 text-xs text-red-400" onClick={() => { setSelectedUser(user); setShowDelete(true); }}>
                              Delete
                            </Button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {/* Pagination */}
            {meta.totalPages > 1 && (
              <div className="flex items-center justify-between border-t border-white/5 px-4 py-3">
                <span className="text-xs text-zinc-500">Page {meta.page} of {meta.totalPages}</span>
                <div className="flex gap-2">
                  <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>Previous</Button>
                  <Button size="sm" variant="outline" disabled={page >= meta.totalPages} onClick={() => setPage(p => p + 1)}>Next</Button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </main>
      <Footer />

      {/* Edit User Dialog */}
      <Dialog open={showEdit} onOpenChange={setShowEdit}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader><DialogTitle>Edit User: {selectedUser?.displayName || selectedUser?.email}</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div>
              <label className="text-xs text-zinc-400">Status</label>
              <select value={editStatus} onChange={e => setEditStatus(e.target.value)} className="mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-white">
                <option value="active">Active</option>
                <option value="suspended">Suspended</option>
                <option value="banned">Banned</option>
              </select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowEdit(false)}>Cancel</Button>
            <Button className="bg-emerald-600 text-white" onClick={() => updateMutation.mutate()} disabled={updateMutation.isPending}>
              {updateMutation.isPending ? 'Saving...' : 'Save'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete User Dialog */}
      <Dialog open={showDelete} onOpenChange={setShowDelete}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader><DialogTitle>Delete User</DialogTitle></DialogHeader>
          <p className="text-sm text-zinc-400">Are you sure you want to delete {selectedUser?.displayName || selectedUser?.email}? This action soft-deletes the account.</p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowDelete(false)}>Cancel</Button>
            <Button variant="destructive" onClick={() => deleteMutation.mutate()} disabled={deleteMutation.isPending}>
              {deleteMutation.isPending ? 'Deleting...' : 'Delete User'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
