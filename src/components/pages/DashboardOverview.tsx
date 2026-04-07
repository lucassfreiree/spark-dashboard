import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { MetricCard } from '@/components/MetricCard'
import { Package, Robot, GitBranch, Pulse, Lock, CheckCircle } from '@phosphor-icons/react'
import { useMemo } from 'react'

interface Props {
  data: DashboardState
}

function computeHealth(data: DashboardState) {
  let score = 100
  const reasons: string[] = []
  const c = data.controller
  const a = data.agent
  const p = data.pipeline

  if (c?.ciResult === 'failure') { score -= 20; reasons.push('Controller CI failed (-20)') }
  if (a?.ciResult === 'failure') { score -= 20; reasons.push('Agent CI failed (-20)') }
  if (p?.status === 'failure' || p?.status === 'failed') { score -= 15; reasons.push('Pipeline failed (-15)') }
  if (c?.promoted === false && c?.status === 'success') { score -= 10; reasons.push('Controller not promoted (-10)') }
  if (data.corporateReal?.controller?.drift) { score -= 25; reasons.push('CONTROLLER DRIFT (-25)') }
  if (data.corporateReal?.agent?.drift) { score -= 25; reasons.push('AGENT DRIFT (-25)') }

  if (data.lastSync) {
    const age = (Date.now() - new Date(data.lastSync).getTime()) / 60000
    if (age > 30) { score -= 10; reasons.push('Sync stale >30min (-10)') }
  }

  const lock = data.sessionLock
  if (lock?.agentId && lock.agentId !== 'none' && lock.expiresAt) {
    if (new Date(lock.expiresAt) <= new Date()) { score -= 5; reasons.push('Expired lock (-5)') }
  }

  return { score: Math.max(0, Math.min(100, score)), reasons }
}

export function DashboardOverview({ data }: Props) {
  const health = useMemo(() => computeHealth(data), [data])
  const claude = data.agents?.claude
  const lock = data.sessionLock

  return (
    <div className="space-y-6">
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        <MetricCard
          title="Controller Version"
          value={data.controller?.version || '?'}
          icon={<Package className="w-5 h-5" />}
        />
        <MetricCard
          title="Agent Version"
          value={data.agent?.version || '?'}
          icon={<Package className="w-5 h-5" />}
        />
        <MetricCard
          title="Last Trigger Run"
          value={`#${data.pipeline?.lastRun || 0}`}
          icon={<GitBranch className="w-5 h-5" />}
        />
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Pulse className="w-5 h-5" />Pipeline</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-3">
              <StatusBadge status={data.pipeline?.status || 'idle'} className="text-base px-4 py-2" />
              {data.pipeline?.commitMessage && <div className="text-xs text-muted-foreground mt-1 truncate">{data.pipeline.commitMessage}</div>}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Robot className="w-5 h-5" />Active Agent</CardTitle></CardHeader>
          <CardContent>
            {claude?.status === 'active' ? (
              <>
                <div className="text-2xl font-bold font-mono mb-1">Claude</div>
                <div className="text-sm text-muted-foreground">{claude.task || 'Working...'}</div>
                {claude.phase && <div className="text-xs text-muted-foreground">Phase: {claude.phase}</div>}
              </>
            ) : (
              <>
                <div className="text-2xl font-bold font-mono text-muted-foreground">idle</div>
                <div className="text-sm text-muted-foreground">No agent active</div>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Lock className="w-5 h-5" />Session Lock</CardTitle></CardHeader>
          <CardContent>
            {lock?.agentId && lock.agentId !== 'none' ? (
              <>
                <div className="text-lg font-bold font-mono text-warning">{lock.agentId}</div>
                <div className="text-sm text-muted-foreground">Op: {lock.operation || '?'}</div>
              </>
            ) : (
              <>
                <div className="flex items-center gap-2"><CheckCircle className="w-5 h-5 text-success" /><span className="text-success font-medium">Free</span></div>
                <div className="text-sm text-muted-foreground">No active lock</div>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader><CardTitle>Recent Deploys</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-2">
              {(data.deployHistory || []).slice(0, 5).map((path, i) => {
                const parts = path.split('/')
                const filename = parts[parts.length - 1] || path
                return (
                  <div key={i} className="flex items-center justify-between p-2 rounded-lg bg-muted/30">
                    <span className="font-mono text-xs truncate flex-1" title={path}>{filename}</span>
                  </div>
                )
              })}
              {(data.deployHistory || []).length === 0 && (
                <div className="text-sm text-muted-foreground text-center py-4">No deploy history</div>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Recent Workflows</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-2">
              {(data.recentWorkflows || []).slice(0, 5).map((wf, i) => (
                <div key={i} className="flex items-center justify-between p-2 rounded-lg bg-muted/30">
                  <div className="flex-1 truncate">
                    <div className="font-semibold text-xs truncate">{wf.name}</div>
                    <div className="text-xs text-muted-foreground font-mono">{wf.head_branch}</div>
                  </div>
                  <StatusBadge status={wf.conclusion || wf.status} />
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
