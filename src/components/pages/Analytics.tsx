import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { ChartBar, TrendUp, Clock, CheckCircle } from '@phosphor-icons/react'
import { useMemo } from 'react'

interface AnalyticsProps {
  data: DashboardState
}

export function Analytics({ data }: AnalyticsProps) {
  const stats = useMemo(() => {
    const total = data.deployHistory.length
    const successful = data.deployHistory.filter(d => d.status === 'success').length
    const failed = data.deployHistory.filter(d => d.status === 'failed').length
    const successRate = total > 0 ? ((successful / total) * 100).toFixed(1) : '0.0'
    
    const durations = data.deployHistory
      .map(d => {
        const match = d.duration.match(/(\d+)m\s*(\d+)s/)
        if (match) {
          return parseInt(match[1]) * 60 + parseInt(match[2])
        }
        return 0
      })
      .filter(d => d > 0)
    
    const avgDuration = durations.length > 0 
      ? Math.floor(durations.reduce((a, b) => a + b, 0) / durations.length)
      : 0
    
    const avgMinutes = Math.floor(avgDuration / 60)
    const avgSeconds = avgDuration % 60
    
    const componentStats = data.deployHistory.reduce((acc, deploy) => {
      if (!acc[deploy.component]) {
        acc[deploy.component] = { total: 0, success: 0, failed: 0 }
      }
      acc[deploy.component].total++
      if (deploy.status === 'success') acc[deploy.component].success++
      if (deploy.status === 'failed') acc[deploy.component].failed++
      return acc
    }, {} as Record<string, { total: number; success: number; failed: number }>)
    
    const agentStats = (data.agentActivity?.recentSessions || []).reduce((acc, session) => {
      if (!acc[session.agent]) {
        acc[session.agent] = { sessions: 0, deploys: 0, success: 0 }
      }
      acc[session.agent].sessions++
      acc[session.agent].deploys += session.deploysCount
      if (session.status === 'success') acc[session.agent].success++
      return acc
    }, {} as Record<string, { sessions: number; deploys: number; success: number }>)
    
    return {
      total,
      successful,
      failed,
      successRate,
      avgDuration: `${avgMinutes}m ${avgSeconds}s`,
      componentStats,
      agentStats
    }
  }, [data])

  return (
    <div className="space-y-6">
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">Total Deploys</CardTitle>
            <ChartBar className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-mono">{stats.total}</div>
            <p className="text-xs text-muted-foreground mt-2">All time deployments</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">Success Rate</CardTitle>
            <TrendUp className="w-4 h-4 text-success" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-mono text-success">{stats.successRate}%</div>
            <p className="text-xs text-muted-foreground mt-2">{stats.successful} successful deploys</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">Avg Duration</CardTitle>
            <Clock className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-mono">{stats.avgDuration}</div>
            <p className="text-xs text-muted-foreground mt-2">Per deployment</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">Failed Deploys</CardTitle>
            <CheckCircle className="w-4 h-4 text-destructive" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-mono text-destructive">{stats.failed}</div>
            <p className="text-xs text-muted-foreground mt-2">Require attention</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Performance by Component</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {Object.entries(stats.componentStats).map(([component, stat]) => {
                const rate = ((stat.success / stat.total) * 100).toFixed(0)
                return (
                  <div key={component}>
                    <div className="flex items-center justify-between mb-2">
                      <span className="font-mono text-sm">{component}</span>
                      <span className="text-sm text-muted-foreground">{rate}% success</span>
                    </div>
                    <div className="w-full bg-muted rounded-full h-2">
                      <div 
                        className="bg-success h-2 rounded-full transition-all"
                        style={{ width: `${rate}%` }}
                      />
                    </div>
                    <div className="flex justify-between mt-1 text-xs text-muted-foreground">
                      <span>{stat.success} success</span>
                      <span>{stat.failed} failed</span>
                      <span>{stat.total} total</span>
                    </div>
                  </div>
                )
              })}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Agent Performance</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-6">
              {Object.entries(stats.agentStats).map(([agent, stat]) => (
                <div key={agent}>
                  <div className="flex items-center justify-between mb-3">
                    <span className="font-mono font-semibold">{agent}</span>
                    <span className="text-sm text-muted-foreground">
                      {(((stat as any).success / (stat as any).sessions) * 100).toFixed(0)}% success rate
                    </span>
                  </div>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="bg-muted/50 rounded-lg p-3">
                      <div className="text-2xl font-bold font-mono">{(stat as any).sessions}</div>
                      <div className="text-xs text-muted-foreground">Sessions</div>
                    </div>
                    <div className="bg-muted/50 rounded-lg p-3">
                      <div className="text-2xl font-bold font-mono">{(stat as any).deploys}</div>
                      <div className="text-xs text-muted-foreground">Deploys</div>
                    </div>
                    <div className="bg-muted/50 rounded-lg p-3">
                      <div className="text-2xl font-bold font-mono text-success">{(stat as any).success}</div>
                      <div className="text-xs text-muted-foreground">Success</div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Pipeline Stage Performance</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {(data.pipeline.stages || []).map(stage => (
              <div key={stage.name} className="flex items-center gap-4">
                <div className="w-32 font-mono text-sm">{stage.name}</div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <div className="flex-1 bg-muted rounded-full h-2">
                      <div 
                        className={`h-2 rounded-full ${
                          stage.status === 'success' ? 'bg-success' :
                          stage.status === 'failed' ? 'bg-destructive' :
                          stage.status === 'running' ? 'bg-warning' :
                          'bg-idle'
                        }`}
                        style={{ width: stage.duration ? '100%' : '0%' }}
                      />
                    </div>
                    <span className="font-mono text-xs text-muted-foreground w-16 text-right">
                      {stage.duration || 'N/A'}
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
