import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'

interface Props {
  data: DashboardState
}

export function AgentActivity({ data }: Props) {
  const claude = data.agents?.claude
  const copilot = data.agents?.copilot
  const codex = data.agents?.codex

  // Combine sessions from copilot + codex, sorted by date
  const allSessions = [
    ...(copilot?.sessions || []).map(s => ({ ...s, agent: 'Copilot' as const })),
    ...(codex?.sessions || []).map(s => ({ ...s, agent: 'Codex' as const })),
  ].sort((a, b) => (b.date || '').localeCompare(a.date || ''))

  const lessons = data.lessonsLearned

  return (
    <div className="space-y-6">
      {/* Agent Status Cards */}
      <div className="grid gap-4 md:grid-cols-3">
        {/* Claude */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center justify-between">
              <span>Claude</span>
              <StatusBadge status={claude?.status || 'idle'} />
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-xs text-muted-foreground mb-2">Primary agent — architecture, deploys, CI fixes</div>
            {claude?.task && (
              <div className="p-2 rounded bg-muted/30 border-l-2 border-primary text-xs">
                <div className="font-medium">{claude.task}</div>
                {claude.phase && <div className="text-muted-foreground mt-1">Phase: {claude.phase}</div>}
              </div>
            )}
            {claude?.lastAction && (
              <div className="text-xs text-muted-foreground mt-2">Last: {claude.lastAction}</div>
            )}
          </CardContent>
        </Card>

        {/* Copilot */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center justify-between">
              <span>Copilot</span>
              <span className="text-xs font-mono text-muted-foreground">{copilot?.sessionCount || 0} sessions</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-xs text-muted-foreground mb-2">Backup agent — code completion, inline assist</div>
            <div className="grid grid-cols-2 gap-2 mt-2">
              <div className="text-center p-2 rounded bg-muted/30">
                <div className="text-xl font-bold">{copilot?.sessionCount || 0}</div>
                <div className="text-[10px] text-muted-foreground">Sessions</div>
              </div>
              <div className="text-center p-2 rounded bg-muted/30">
                <div className="text-xl font-bold">{copilot?.lessonsCount || 0}</div>
                <div className="text-[10px] text-muted-foreground">Lessons</div>
              </div>
            </div>
            {copilot?.lastSession && copilot.lastSession !== 'none' && (
              <div className="p-2 rounded bg-muted/30 border-l-2 border-purple-500 text-xs mt-2 line-clamp-2">{copilot.lastSession}</div>
            )}
          </CardContent>
        </Card>

        {/* Codex */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center justify-between">
              <span>Codex</span>
              <span className="text-xs font-mono text-muted-foreground">{codex?.sessionCount || 0} sessions</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-xs text-muted-foreground mb-2">Code implementation + CI monitoring</div>
            <div className="grid grid-cols-2 gap-2 mt-2">
              <div className="text-center p-2 rounded bg-muted/30">
                <div className="text-xl font-bold">{codex?.sessionCount || 0}</div>
                <div className="text-[10px] text-muted-foreground">Sessions</div>
              </div>
              <div className="text-center p-2 rounded bg-muted/30">
                <div className="text-xl font-bold">{codex?.lessonsCount || 0}</div>
                <div className="text-[10px] text-muted-foreground">Lessons</div>
              </div>
            </div>
            {codex?.lastSession && codex.lastSession !== 'none' && (
              <div className="p-2 rounded bg-muted/30 border-l-2 border-orange-500 text-xs mt-2 line-clamp-2">{codex.lastSession}</div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Session Timeline */}
      <Card>
        <CardHeader><CardTitle>Session Timeline</CardTitle></CardHeader>
        <CardContent>
          {allSessions.length === 0 ? (
            <div className="text-sm text-muted-foreground text-center py-4">No session data</div>
          ) : (
            <div className="space-y-2">
              {allSessions.slice(0, 10).map((s, i) => (
                <div key={i} className="flex items-start gap-3 p-3 rounded-lg bg-muted/30">
                  <span className={`px-2 py-0.5 rounded text-xs font-medium ${s.agent === 'Copilot' ? 'bg-purple-500/20 text-purple-400' : 'bg-orange-500/20 text-orange-400'}`}>{s.agent}</span>
                  <div className="flex-1 text-sm">{s.summary || 'No summary'}</div>
                  <span className="text-xs text-muted-foreground whitespace-nowrap">{s.date} | {s.actions} actions</span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Lessons Learned */}
      <Card>
        <CardHeader><CardTitle>Lessons Learned ({lessons?.total || 0})</CardTitle></CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <h4 className="text-sm font-medium mb-2 text-purple-400">Copilot ({lessons?.copilot || 0})</h4>
              <div className="space-y-1 max-h-64 overflow-y-auto">
                {(lessons?.copilotLessons || []).slice(0, 10).map((l, i) => (
                  <div key={i} className="p-2 rounded bg-muted/30 border-l-2 border-purple-500 text-xs">
                    <div className="font-medium">{l.lesson}</div>
                    {l.fix && <div className="text-success mt-1">Fix: {l.fix}</div>}
                  </div>
                ))}
              </div>
            </div>
            <div>
              <h4 className="text-sm font-medium mb-2 text-orange-400">Codex ({lessons?.codex || 0})</h4>
              <div className="space-y-1 max-h-64 overflow-y-auto">
                {(lessons?.codexLessons || []).slice(0, 10).map((l, i) => (
                  <div key={i} className="p-2 rounded bg-muted/30 border-l-2 border-orange-500 text-xs">
                    <div className="font-medium">{l.lesson}</div>
                    {l.fix && <div className="text-success mt-1">Fix: {l.fix}</div>}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
