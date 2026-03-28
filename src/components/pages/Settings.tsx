import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Gear, FloppyDisk, ArrowCounterClockwise } from '@phosphor-icons/react'
import { toast } from 'sonner'

export function Settings() {
  const [refreshInterval, setRefreshInterval] = useState(30)
  const [enableNotifications, setEnableNotifications] = useState(true)
  const [notifyOnFailure, setNotifyOnFailure] = useState(true)
  const [notifyOnSuccess, setNotifyOnSuccess] = useState(false)
  const [dashboardLayout, setDashboardLayout] = useState('comfortable')
  const [dataRetentionDays, setDataRetentionDays] = useState(30)
  const [failureRateThreshold, setFailureRateThreshold] = useState(20)
  const [longRunningThreshold, setLongRunningThreshold] = useState(10)

  const handleSave = () => {
    toast.success('Settings saved successfully')
  }

  const handleReset = () => {
    setRefreshInterval(30)
    setEnableNotifications(true)
    setNotifyOnFailure(true)
    setNotifyOnSuccess(false)
    setDashboardLayout('comfortable')
    setDataRetentionDays(30)
    setFailureRateThreshold(20)
    setLongRunningThreshold(10)
    toast.info('Settings reset to defaults')
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold tracking-tight flex items-center gap-3">
            <Gear className="w-8 h-8" />
            Settings
          </h2>
          <p className="text-muted-foreground mt-1">Configure your dashboard preferences</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={handleReset}>
            <ArrowCounterClockwise className="w-4 h-4 mr-2" />
            Reset to Defaults
          </Button>
          <Button onClick={handleSave}>
            <FloppyDisk className="w-4 h-4 mr-2" />
            Save Changes
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Refresh Settings</CardTitle>
          <CardDescription>Control how frequently the dashboard updates</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="refresh-interval">Auto-Refresh Interval (seconds)</Label>
            <Input
              id="refresh-interval"
              type="number"
              min="5"
              max="300"
              value={refreshInterval}
              onChange={(e) => setRefreshInterval(parseInt(e.target.value))}
            />
            <p className="text-xs text-muted-foreground">
              Currently set to refresh every {refreshInterval} seconds
            </p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Notifications</CardTitle>
          <CardDescription>Manage when you receive notifications</CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label>Enable Notifications</Label>
              <p className="text-sm text-muted-foreground">
                Receive notifications for important events
              </p>
            </div>
            <Switch
              checked={enableNotifications}
              onCheckedChange={setEnableNotifications}
            />
          </div>

          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label>Notify on Failure</Label>
              <p className="text-sm text-muted-foreground">
                Get alerts when deployments fail
              </p>
            </div>
            <Switch
              checked={notifyOnFailure}
              disabled={!enableNotifications}
              onCheckedChange={setNotifyOnFailure}
            />
          </div>

          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label>Notify on Success</Label>
              <p className="text-sm text-muted-foreground">
                Get alerts when deployments succeed
              </p>
            </div>
            <Switch
              checked={notifyOnSuccess}
              disabled={!enableNotifications}
              onCheckedChange={setNotifyOnSuccess}
            />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Display Preferences</CardTitle>
          <CardDescription>Customize how information is displayed</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="dashboard-layout">Dashboard Layout</Label>
            <Select
              value={dashboardLayout}
              onValueChange={setDashboardLayout}
            >
              <SelectTrigger id="dashboard-layout">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="compact">Compact</SelectItem>
                <SelectItem value="comfortable">Comfortable</SelectItem>
                <SelectItem value="spacious">Spacious</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Data Management</CardTitle>
          <CardDescription>Control data retention and storage</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="retention-days">Data Retention (days)</Label>
            <Input
              id="retention-days"
              type="number"
              min="7"
              max="365"
              value={dataRetentionDays}
              onChange={(e) => setDataRetentionDays(parseInt(e.target.value))}
            />
            <p className="text-xs text-muted-foreground">
              Historical data older than {dataRetentionDays} days will be archived
            </p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Alert Thresholds</CardTitle>
          <CardDescription>Set when to trigger warnings and alerts</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="failure-rate">Failure Rate Alert (%)</Label>
            <Input
              id="failure-rate"
              type="number"
              min="0"
              max="100"
              value={failureRateThreshold}
              onChange={(e) => setFailureRateThreshold(parseInt(e.target.value))}
            />
            <p className="text-xs text-muted-foreground">
              Alert when failure rate exceeds {failureRateThreshold}%
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="long-running">Long-Running Deploy Threshold (minutes)</Label>
            <Input
              id="long-running"
              type="number"
              min="1"
              max="60"
              value={longRunningThreshold}
              onChange={(e) => setLongRunningThreshold(parseInt(e.target.value))}
            />
            <p className="text-xs text-muted-foreground">
              Alert when deployments exceed {longRunningThreshold} minutes
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
