import { useState } from 'react'
import { useDashboardData } from '@/hooks/use-dashboard-data'
import { DashboardOverview } from '@/components/pages/DashboardOverview'
import { DeployHistory } from '@/components/pages/DeployHistory'
import { AgentActivity } from '@/components/pages/AgentActivity'
import { Workflows } from '@/components/pages/Workflows'
import { PipelineMonitor } from '@/components/pages/PipelineMonitor'
import { Analytics } from '@/components/pages/Analytics'
import { Settings } from '@/components/pages/Settings'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { ChartBar, ClockCounterClockwise, Robot, GitBranch, Rows, ArrowsClockwise, ChartLine, Gear } from '@phosphor-icons/react'
import { cn } from '@/lib/utils'
import { formatDistanceToNow } from 'date-fns'
import { Toaster } from '@/components/ui/sonner'

type Page = 'dashboard' | 'deploy-history' | 'agent-activity' | 'workflows' | 'pipeline-monitor' | 'analytics' | 'settings'

function App() {
  const [currentPage, setCurrentPage] = useState<Page>('dashboard')
  const { data, isLoading, error, refetch } = useDashboardData()

  const navItems = [
    { id: 'dashboard' as Page, label: 'Dashboard', icon: ChartBar },
    { id: 'analytics' as Page, label: 'Analytics', icon: ChartLine },
    { id: 'deploy-history' as Page, label: 'Deploy History', icon: ClockCounterClockwise },
    { id: 'agent-activity' as Page, label: 'Agent Activity', icon: Robot },
    { id: 'workflows' as Page, label: 'Workflows', icon: GitBranch },
    { id: 'pipeline-monitor' as Page, label: 'Pipeline Monitor', icon: Rows },
  ]

  const renderPage = () => {
    switch (currentPage) {
      case 'dashboard':
        return <DashboardOverview data={data} />
      case 'analytics':
        return <Analytics data={data} />
      case 'deploy-history':
        return <DeployHistory data={data} />
      case 'agent-activity':
        return <AgentActivity data={data} />
      case 'workflows':
        return <Workflows data={data} />
      case 'pipeline-monitor':
        return <PipelineMonitor data={data} />
      case 'settings':
        return <Settings />
      default:
        return <DashboardOverview data={data} />
    }
  }

  return (
    <div className="min-h-screen flex bg-background">
      <aside className="w-64 border-r border-border bg-card flex flex-col">
        <div className="p-6 border-b border-border">
          <h1 className="text-2xl font-bold tracking-tight">Autopilot Dashboard</h1>
          <p className="text-sm text-muted-foreground mt-1">CI/CD Operations Monitor</p>
        </div>
        
        <nav className="flex-1 p-4 space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon
            return (
              <button
                key={item.id}
                onClick={() => setCurrentPage(item.id)}
                className={cn(
                  "w-full flex items-center gap-3 px-4 py-3 rounded-lg transition-all text-left",
                  currentPage === item.id
                    ? "bg-primary text-primary-foreground font-semibold"
                    : "text-foreground hover:bg-muted"
                )}
              >
                <Icon className="w-5 h-5" weight={currentPage === item.id ? "fill" : "regular"} />
                <span>{item.label}</span>
              </button>
            )
          })}
          
          <div className="pt-4">
            <button
              onClick={() => setCurrentPage('settings')}
              className={cn(
                "w-full flex items-center gap-3 px-4 py-3 rounded-lg transition-all text-left border-t border-border",
                currentPage === 'settings'
                  ? "bg-primary text-primary-foreground font-semibold"
                  : "text-foreground hover:bg-muted"
              )}
            >
              <Gear className="w-5 h-5" weight={currentPage === 'settings' ? "fill" : "regular"} />
              <span>Settings</span>
            </button>
          </div>
        </nav>

        <div className="p-4 border-t border-border">
          <div className="text-xs text-muted-foreground space-y-1">
            <div className="flex items-center justify-between">
              <span>Last updated:</span>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => refetch()}
                disabled={isLoading}
                className="h-6 px-2"
              >
                <ArrowsClockwise className={cn("w-4 h-4", isLoading && "animate-spin")} />
              </Button>
            </div>
            <div className="font-mono text-xs">
              {formatDistanceToNow(new Date(data.lastUpdated), { addSuffix: true })}
            </div>
            {error && (
              <div className="text-xs text-warning mt-2 p-2 bg-warning/10 rounded">
                {error}
              </div>
            )}
          </div>
        </div>
      </aside>

      <main className="flex-1 overflow-auto">
        <div className="p-6">
          <div className="max-w-7xl mx-auto">
            {renderPage()}
          </div>
        </div>
      </main>

      <Toaster />
    </div>
  )
}

export default App
