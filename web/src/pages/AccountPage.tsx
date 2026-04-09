import { Tabs, TabsContent, TabsList, TabsTrigger } from '../components/ui/tabs';
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card';
import { Button } from '../components/ui/button';
import { Badge } from '../components/ui/badge';
import Header from '../components/layout/Header';
import Footer from '../components/layout/Footer';

export default function AccountPage() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 lg:px-8">
        <div className="mx-auto max-w-4xl">
          <h1 className="text-3xl font-bold tracking-tight mb-8">My Account</h1>

          <Tabs defaultValue="profile" className="w-full">
            <TabsList className="bg-zinc-900 border border-zinc-800">
              <TabsTrigger value="profile">Profile</TabsTrigger>
              <TabsTrigger value="subscription">Subscription</TabsTrigger>
              <TabsTrigger value="devices">Devices</TabsTrigger>
              <TabsTrigger value="referrals">Referrals</TabsTrigger>
            </TabsList>

            <TabsContent value="profile" className="mt-6">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader>
                  <CardTitle>Profile</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-zinc-400">Sign in to view and manage your profile.</p>
                  <Button className="bg-emerald-600 hover:bg-emerald-500 text-white">
                    Sign In with Apple
                  </Button>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="subscription" className="mt-6">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader>
                  <CardTitle className="flex items-center gap-3">
                    Subscription
                    <Badge variant="outline" className="border-zinc-600 text-zinc-400">
                      Inactive
                    </Badge>
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-zinc-400 mb-4">
                    Subscribe through the iOS app to unlock all GearSnitch features including unlimited
                    device monitoring, gym geofencing, and health tracking.
                  </p>
                  <div className="p-4 rounded-lg border border-zinc-800 bg-zinc-950">
                    <div className="flex justify-between items-center">
                      <div>
                        <p className="font-semibold">GearSnitch Annual</p>
                        <p className="text-sm text-zinc-400">365-day subscription</p>
                      </div>
                      <p className="text-xl font-bold">$29.99/yr</p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="devices" className="mt-6">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader>
                  <CardTitle>My Devices</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-zinc-400">
                    Pair and manage your Bluetooth devices from the iOS app. Your device status will
                    appear here once connected.
                  </p>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="referrals" className="mt-6">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader>
                  <CardTitle>Referrals</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-zinc-400">
                    Share your referral code and earn 90 days of free subscription credit for every
                    friend who subscribes.
                  </p>
                  <div className="p-4 rounded-lg border border-zinc-800 bg-zinc-950 flex items-center justify-between">
                    <code className="text-emerald-400 font-mono text-lg">GEAR-XXXX</code>
                    <Button variant="outline" size="sm" className="border-zinc-700">
                      Copy Code
                    </Button>
                  </div>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </div>
      </section>

      <Footer />
    </div>
  );
}
