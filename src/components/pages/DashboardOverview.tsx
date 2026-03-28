import { DashboardState } from '@/types/dashboard'
import { MetricCard } from '@/components/MetricCard'
import { StatusBadge } from '@/components/StatusBadge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Package, Robot, GitBranch, Pulse, NumberCircleOne, TrendUp, TrendDown } from '@phosphor-icons/react'
import { formatDistanceToNowSaoPaulo } from '@/lib/utils'
import { useMemo } from 'react'

interface DashboardOverviewProps {
  data: DashboardState
}

export function DashboardOverview({ data }: DashboardOverviewProps) {
  const stats = useMemo(() => {
    const recent = data.deployHistory.slice(0, 5)
    const older = data.deployHistory.slice(5, 10)
    
    const recentSuccess = recent.filter(d => d.status === 'success').length
    const olderSuccess = older.filter(d => d.status === 'success').length
    
    const recentRate = recent.length > 0 ? (recentSuccess / recent.length) * 100 : 0
    const olderRate = older.length > 0 ? (olderSuccess / older.length) * 100 : 0
    
    const trend = recentRate > olderRate ? 'up' : recentRate < olderRate ? 'down' : 'same'
    const trendPercentage = Math.abs(recentRate - olderRate).toFixed(1)
    
    return { trend, trendPercentage, recentRate: recentRate.toFixed(0) }
  }, [data.deployHistory])

  return (
    <div className="space-y-6">
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        <MetricCard
          title="Controller Version"
          value={data.controllerVersion}
          icon={<Package className="w-5 h-5" />}
        />
        
        <MetricCard
          title="Agent Version"
          value={data.agentVersion}
          icon={<Package className="w-5 h-5" />}
        />
        
        <MetricCard
          title="Last Trigger Run"
          value={`#${data.lastTriggerRun}`}
          icon={<NumberCircleOne className="w-5 h-5" />}
        />
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Pulse className="w-5 h-5" />
              Pipeline Status
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <StatusBadge status={data.pipelineStatus} className="text-base px-4 py-2" />
              {data.pipeline.currentStage && (
                <div className="text-sm text-muted-foreground">
                  Current stage: <span className="font-mono text-foreground">{data.pipeline.currentStage}</span>
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Robot className="w-5 h-5" />
              Active Agent
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-mono mb-2">
              {data.activeAgent}
            </div>
            <div className="text-sm text-muted-foreground">
              {data.activeAgent === 'idle' ? 'No active sessions' : 'Currently processing deployments'}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              {stats.trend === 'up' ? (
                <TrendUp className="w-5 h-5 text-success" />
              ) : (
                <TrendDown className="w-5 h-5 text-destructive" />
              )}
              Success Rate
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className={`text-3xl font-bold font-mono mb-2 ${
              stats.trend === 'up' ? 'text-success' : 'text-destructive'
            }`}>
              {stats.recentRate}%
            </div>
            <div className="text-sm text-muted-foreground flex items-center gap-1">
              {stats.trend === 'up' ? '+' : '-'}{stats.trendPercentage}% from previous period
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <GitBranch className="w-5 h-5" />
            Last Deploy
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <div>
              <div className="text-sm text-muted-foreground mb-1">Component</div>
              <div className="font-mono text-base">{data.lastDeploy.component}</div>
            </div>
            <div>
              <div className="text-sm text-muted-foreground mb-1">Status</div>
              <StatusBadge status={data.lastDeploy.status} />
            </div>
            <div>
              <div className="text-sm text-muted-foreground mb-1">Time</div>
              <div className="text-sm">
                {formatDistanceToNowSaoPaulo(data.lastDeploy.date, { addSuffix: true })}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Recent Deploys</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {data.deployHistory.slice(0, 5).map((deploy) => (
                <div key={deploy.id} className="flex items-center justify-between p-3 rounded-lg bg-muted/30">
                  <div className="flex-1">
                    <div className="font-mono text-sm font-semibold">{deploy.component}</div>
                    <div className="text-xs text-muted-foreground">{deploy.version}</div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-xs text-muted-foreground">{deploy.duration}</span>
                    <StatusBadge status={deploy.status} />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Active Workflows</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {data.workflows.slice(0, 5).map((workflow) => (
                <div key={workflow.id} className="flex items-center justify-between p-3 rounded-lg bg-muted/30">
                  <div className="flex-1">
                    <div className="font-semibold text-sm">{workflow.name}</div>
                    <div className="text-xs text-muted-foreground font-mono">{workflow.branch}</div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-xs text-muted-foreground">{workflow.duration}</span>
                    <StatusBadge status={workflow.status} />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
