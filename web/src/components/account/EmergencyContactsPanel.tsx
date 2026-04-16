import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { getEmergencyContacts, createEmergencyContact, deleteEmergencyContact } from '@/lib/api';

export default function EmergencyContactsPanel() {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');

  const { data: contacts = [], isLoading } = useQuery({
    queryKey: ['emergency-contacts'],
    queryFn: getEmergencyContacts,
    staleTime: 30_000,
  });

  const createMutation = useMutation({
    mutationFn: () => createEmergencyContact({
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim() || undefined,
      notifyOnPanic: true,
      notifyOnDisconnect: false,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['emergency-contacts'] });
      setShowAdd(false);
      setName(''); setPhone(''); setEmail('');
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteEmergencyContact(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['emergency-contacts'] }),
  });

  return (
    <>
      <Card className="border-white/5 bg-zinc-900/70">
        <CardHeader className="pb-2">
          <div className="flex items-center justify-between">
            <CardTitle className="text-sm font-medium text-zinc-400">Emergency Contacts</CardTitle>
            <Button size="sm" className="h-7 bg-emerald-600 px-3 text-xs text-white" onClick={() => setShowAdd(true)} disabled={contacts.length >= 5}>
              Add Contact
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-2 pb-4">
          {isLoading ? (
            <p className="text-xs text-zinc-500">Loading...</p>
          ) : contacts.length === 0 ? (
            <p className="text-xs text-zinc-500">No emergency contacts. Add someone who should be notified during a panic alarm.</p>
          ) : (
            contacts.map(contact => (
              <div key={contact._id} className="flex items-center justify-between rounded-lg border border-white/5 bg-zinc-950 px-4 py-3">
                <div>
                  <p className="text-sm font-medium text-zinc-200">{contact.name}</p>
                  <p className="text-xs text-zinc-500">{contact.phone}{contact.email ? ` · ${contact.email}` : ''}</p>
                  <div className="mt-1 flex gap-2">
                    {contact.notifyOnPanic && (
                      <span className="rounded bg-red-500/10 px-1.5 py-0.5 text-[10px] font-medium text-red-400">Panic</span>
                    )}
                    {contact.notifyOnDisconnect && (
                      <span className="rounded bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-medium text-amber-400">Disconnect</span>
                    )}
                  </div>
                </div>
                <Button size="sm" variant="ghost" className="h-7 text-xs text-red-400" onClick={() => deleteMutation.mutate(contact._id)}>
                  Remove
                </Button>
              </div>
            ))
          )}
          {contacts.length >= 5 && (
            <p className="text-[10px] text-zinc-600">Maximum 5 contacts reached</p>
          )}
        </CardContent>
      </Card>

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader><DialogTitle>Add Emergency Contact</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div>
              <Label className="text-zinc-400">Name</Label>
              <Input value={name} onChange={e => setName(e.target.value)} placeholder="Jane Doe" className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
            <div>
              <Label className="text-zinc-400">Phone</Label>
              <Input value={phone} onChange={e => setPhone(e.target.value)} placeholder="+1 (555) 123-4567" type="tel" className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
            <div>
              <Label className="text-zinc-400">Email (optional)</Label>
              <Input value={email} onChange={e => setEmail(e.target.value)} placeholder="jane@example.com" type="email" className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
            {createMutation.isError && <p className="text-xs text-red-400">{(createMutation.error as Error).message}</p>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAdd(false)}>Cancel</Button>
            <Button className="bg-emerald-600 text-white" onClick={() => createMutation.mutate()} disabled={!name.trim() || !phone.trim() || createMutation.isPending}>
              {createMutation.isPending ? 'Adding...' : 'Add Contact'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
