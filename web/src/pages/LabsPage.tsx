import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { api } from '@/lib/api';

interface BloodworkProduct {
  id: string;
  name: string;
  price: number;
  currency: string;
  includes: string[];
}

interface LabAppointment {
  _id: string;
  appointmentDate: string;
  location: string;
  provider: string;
  status: string;
  amountCharged: number;
  createdAt: string;
}

async function getProduct(): Promise<BloodworkProduct> {
  const res = await api.get<BloodworkProduct>('/labs/product');
  if (!res.success || !res.data) throw new Error('Failed to load product');
  return res.data;
}

async function getAppointments(): Promise<LabAppointment[]> {
  const res = await api.get<LabAppointment[]>('/labs/appointments');
  if (!res.success || !res.data) throw new Error('Failed to load appointments');
  return res.data;
}

async function scheduleLab(date: string): Promise<unknown> {
  const res = await api.post<unknown>('/labs/schedule', {
    date,
    paymentToken: 'web-checkout-pending',
    productId: 'com.gearsnitch.app.bloodwork',
  });
  if (!res.success) throw new Error(res.error?.message || 'Failed to schedule');
  return res.data;
}

async function cancelAppointment(id: string): Promise<unknown> {
  const res = await api.patch<unknown>(`/labs/appointments/${id}/cancel`, {});
  if (!res.success) throw new Error(res.error?.message || 'Failed to cancel');
  return res.data;
}

function formatDate(iso: string) {
  return new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(iso));
}

function statusBadge(status: string) {
  switch (status) {
    case 'confirmed': return 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300';
    case 'completed': return 'border-cyan-400/30 bg-cyan-400/10 text-cyan-300';
    case 'cancelled': return 'border-red-400/30 bg-red-400/10 text-red-300';
    default: return 'border-zinc-400/30 bg-zinc-400/10 text-zinc-300';
  }
}

export default function LabsPage() {
  const queryClient = useQueryClient();
  const [date, setDate] = useState('');
  const [time, setTime] = useState('09:00');
  const [success, setSuccess] = useState(false);

  const { data: product, error: productError } = useQuery({ queryKey: ['labs-product'], queryFn: getProduct, staleTime: 300_000 });
  const { data: appointments = [], error: appointmentsError } = useQuery({ queryKey: ['labs-appointments'], queryFn: getAppointments, staleTime: 30_000 });

  const scheduleMutation = useMutation({
    mutationFn: () => {
      const dateTime = new Date(`${date}T${time}:00`).toISOString();
      return scheduleLab(dateTime);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['labs-appointments'] });
      setSuccess(true);
      setDate(''); setTime('09:00');
    },
  });

  const cancelMutation = useMutation({
    mutationFn: (id: string) => cancelAppointment(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['labs-appointments'] }),
  });

  // Default to tomorrow
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const minDate = tomorrow.toISOString().slice(0, 10);

  return (
    <div className="dark min-h-screen bg-black text-white">
      <Header />
      <main className="mx-auto max-w-3xl space-y-6 px-4 pb-16 pt-28 sm:px-6">
        <section className="relative overflow-hidden rounded-[2rem] border border-white/5 bg-zinc-900/70 px-6 py-8">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,_rgba(34,211,238,0.12),_transparent_32%)]" />
          <div className="relative">
            <Badge variant="secondary" className="border border-cyan-500/20 bg-cyan-500/10 text-cyan-400">Blood Work</Badge>
            <h1 className="mt-4 text-3xl font-bold text-white">Schedule Labs</h1>
            <p className="mt-2 text-sm text-zinc-400">Comprehensive blood panel at one of our designated provider locations.</p>
          </div>
        </section>

        {/* What's included */}
        {productError && <p className="text-sm text-red-400">Failed to load product details: {(productError as Error).message}</p>}
        {appointmentsError && <p className="text-sm text-red-400">Failed to load appointments: {(appointmentsError as Error).message}</p>}

        {product && (
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Panel Includes</CardTitle></CardHeader>
            <CardContent className="space-y-1.5 pb-4">
              {product.includes.map(item => (
                <div key={item} className="flex items-center gap-2 text-sm">
                  <span className="text-emerald-400">&#10003;</span>
                  <span className="text-zinc-300">{item}</span>
                </div>
              ))}
              <p className="mt-3 text-xl font-bold text-emerald-400">${product.price} <span className="text-sm font-normal text-zinc-500">one-time</span></p>
            </CardContent>
          </Card>
        )}

        {/* Schedule Form */}
        {!success ? (
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Pick a Date & Time</CardTitle></CardHeader>
            <CardContent className="space-y-4 pb-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label className="text-zinc-400">Date</Label>
                  <Input type="date" min={minDate} value={date} onChange={e => setDate(e.target.value)} className="border-zinc-700 bg-zinc-950 text-white" />
                </div>
                <div>
                  <Label className="text-zinc-400">Time</Label>
                  <Input type="time" value={time} onChange={e => setTime(e.target.value)} className="border-zinc-700 bg-zinc-950 text-white" />
                </div>
              </div>
              {scheduleMutation.isError && <p className="text-xs text-red-400">{(scheduleMutation.error as Error).message}</p>}
              <Button className="w-full bg-emerald-600 text-white hover:bg-emerald-700" onClick={() => scheduleMutation.mutate()} disabled={!date || scheduleMutation.isPending}>
                {scheduleMutation.isPending ? 'Scheduling...' : `Schedule & Pay $${product?.price ?? '69.99'}`}
              </Button>
              <p className="text-[10px] text-zinc-600">Please fast 8-12 hours before your appointment. Results in 3-5 business days.</p>
            </CardContent>
          </Card>
        ) : (
          <Card className="border-emerald-500/20 bg-zinc-900/70">
            <CardContent className="flex flex-col items-center gap-3 p-6">
              <span className="text-4xl">&#10003;</span>
              <p className="text-lg font-bold text-emerald-400">Appointment Scheduled!</p>
              <p className="text-sm text-zinc-400">Check your appointments below for details.</p>
              <Button variant="outline" onClick={() => setSuccess(false)}>Schedule Another</Button>
            </CardContent>
          </Card>
        )}

        {/* Appointment History */}
        {appointments.length > 0 && (
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Your Appointments</CardTitle></CardHeader>
            <CardContent className="space-y-2 pb-4">
              {appointments.map(appt => (
                <div key={appt._id} className="flex items-center justify-between rounded-lg border border-white/5 bg-zinc-950 px-4 py-3">
                  <div>
                    <p className="text-sm font-medium text-zinc-200">{formatDate(appt.appointmentDate)}</p>
                    <p className="text-xs text-zinc-500">{appt.location}</p>
                    <p className="text-xs text-zinc-600">${appt.amountCharged}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" className={`text-[10px] ${statusBadge(appt.status)}`}>{appt.status}</Badge>
                    {appt.status === 'confirmed' && (
                      <Button size="sm" variant="ghost" className="h-7 text-xs text-red-400" onClick={() => cancelMutation.mutate(appt._id)}>Cancel</Button>
                    )}
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        )}
      </main>
      <Footer />
    </div>
  );
}
