import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useMemo } from 'react'

interface Props {
  data: DashboardState
}

export function Analytics({ data }: Props) {
  const health = useMemo(() => {
    let score = 100
    const reasons: string[] = []
    if (data.controller?.ciResult === 'failure') { score -= 20; reasons.push('Controller CI failed') }
    if (data.agent?.ciResult === 'failure') { score -= 20; reasons.push('Agent CI failed') }
    if (data.pipeline?.status === 'failure') { score -= 15; reasons.push('Pipeline failed') }
    if (data.corporateReal?.controller?.drift) { score -= 25; reasons.push('Controller drift') }
    if (data.corporateReal?.agent?.drift) { score -= 25; reasons.push('Agent drift') }
    if (data.controller?.promoted === false && data.controller?.status === 'success') { score -= 10; reasons.push('Not promoted') }
    return { score: Math.max(0, score), reasons }
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
            <div className="text-4xl font-bold font-mono">{errors.length}</div>
            <div className="text-xs text-muted-foreground mt-1">Auto-matched patterns</div>
          </CardContent>
        </Card>
      </div>

      {/* Workspaces */}
      <Card>
        <CardHeader><CardTitle>Workspaces</CardTitle></CardHeader>
        <CardContent>
          <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
            {(data.workspaces || []).map((ws, i) => (
              <div key={i} className={`p-3 rounded-lg border ${ws.status === 'active' ? 'border-success/30' : ws.status === 'locked' ? 'border-destructive/30' : 'border-border'}`}>
                <div className="flex items-center justify-between mb-1">
                  <span className="font-medium text-sm">{ws.company}</span>
                  <span className={`text-xs px-1.5 py-0.5 rounded ${ws.status === 'active' ? 'bg-success/20 text-success' : ws.status === 'locked' ? 'bg-destructive/20 text-destructive' : 'bg-muted text-muted-foreground'}`}>{ws.status}</span>
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
