import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useMemo } from 'react'

interface Props {
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

  const lessons = data.lessonsLearned
  const errors = data.knownErrors || []
  const workflows = data.recentWorkflows || []
  const successCount = workflows.filter(w => w.conclusion === 'success').length
  const failCount = workflows.filter(w => w.conclusion === 'failure').length
  const successRate = workflows.length > 0 ? Math.round((successCount / workflows.length) * 100) : 0

  return (
    <div className="space-y-6">
      {/* Health + Stats */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Health Score</CardTitle></CardHeader>
          <CardContent>
            <div className={`text-4xl font-bold font-mono ${health.score >= 80 ? 'text-success' : health.score >= 50 ? 'text-warning' : 'text-destructive'}`}>{health.score}</div>
            <div className="text-xs text-muted-foreground mt-1">{health.reasons[0] || 'All OK'}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Success Rate</CardTitle></CardHeader>
          <CardContent>
            <div className={`text-4xl font-bold font-mono ${successRate >= 80 ? 'text-success' : 'text-warning'}`}>{successRate}%</div>
            <div className="text-xs text-muted-foreground mt-1">{successCount} ok / {failCount} failed</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Total Lessons</CardTitle></CardHeader>
          <CardContent>
            <div className="text-4xl font-bold font-mono">{lessons?.total || 0}</div>
            <div className="text-xs text-muted-foreground mt-1">Copilot: {lessons?.copilot || 0} | Codex: {lessons?.codex || 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Known Errors</CardTitle></CardHeader>
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

      {/* Workspaces */}
      <Card>
        <CardHeader><CardTitle>Workspaces</CardTitle></CardHeader>
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
                <div className="font-mono text-xs text-muted-foreground">{ws.id}</div>
                {ws.status === 'locked' && <div className="text-xs text-destructive mt-1">Third-party — do not operate</div>}
                {ws.controllerVersion && <div className="text-xs mt-1">Ctrl: {ws.controllerVersion} | Agent: {ws.agentVersion || '?'}</div>}
                {ws.stack && <div className="text-xs text-muted-foreground mt-1">{ws.stack}</div>}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Known Error Patterns */}
      <Card>
        <CardHeader><CardTitle>Known Error Patterns ({errors.length})</CardTitle></CardHeader>
        <CardContent>
          {errors.length === 0 ? (
            <div className="text-sm text-muted-foreground text-center py-4">No error patterns loaded</div>
          ) : (
            <div className="space-y-1">
              {errors.map((e, i) => (
                <div key={i} className="p-2 rounded bg-muted/30 border-l-2 border-destructive text-xs">
                  <div className="flex items-center justify-between">
                    <code className="font-bold">{e.code}</code>
                  </div>
                  <div className="mt-1">{e.desc}</div>
                  <div className="text-success mt-1">Fix: {e.fix}</div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
