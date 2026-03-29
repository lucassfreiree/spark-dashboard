import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { formatDistanceToNowSaoPaulo } from '@/lib/utils'

interface Props {
  data: DashboardState
}

export function Workflows({ data }: Props) {
  const workflows = data.recentWorkflows || []

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Recent Workflows ({workflows.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {workflows.length === 0 ? (
            <div className="text-sm text-muted-foreground text-center py-8">No workflow runs available</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-muted-foreground">
                    <th className="text-left py-2 px-3">Workflow</th>
                    <th className="text-left py-2 px-3">Status</th>
                    <th className="text-left py-2 px-3">Result</th>
                    <th className="text-left py-2 px-3">Branch</th>
                    <th className="text-left py-2 px-3">When</th>
                  </tr>
                </thead>
                <tbody>
                  {workflows.map((wf, i) => (
                    <tr key={i} className="border-b border-border/50 hover:bg-muted/30">
                      <td className="py-2 px-3">
                        {wf.url ? (
                          <a href={wf.url} target="_blank" rel="noopener noreferrer" className="hover:underline">{wf.name}</a>
                        ) : wf.name}
                      </td>
                      <td className="py-2 px-3"><StatusBadge status={wf.status} /></td>
                      <td className="py-2 px-3">{wf.conclusion ? <StatusBadge status={wf.conclusion} /> : <span className="text-muted-foreground">in progress</span>}</td>
                      <td className="py-2 px-3 font-mono text-xs text-muted-foreground max-w-[120px] truncate">{wf.head_branch || ''}</td>
                      <td className="py-2 px-3 text-muted-foreground text-xs whitespace-nowrap">{wf.created ? formatDistanceToNowSaoPaulo(wf.created, { addSuffix: true }) : ''}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Open PRs */}
      <Card>
        <CardHeader>
          <CardTitle>Open Pull Requests ({(data.openPRs || []).length})</CardTitle>
        </CardHeader>
        <CardContent>
          {(data.openPRs || []).length === 0 ? (
            <div className="text-sm text-muted-foreground text-center py-4">No open PRs</div>
          ) : (
            <div className="space-y-2">
              {(data.openPRs || []).map((pr, i) => (
                <div key={i} className="flex items-start gap-3 p-3 rounded-lg bg-muted/30">
                  <span className="font-mono text-xs text-muted-foreground">#{pr.number}</span>
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm truncate">{pr.title}</div>
                    <div className="flex items-center gap-2 mt-1 text-xs text-muted-foreground">
                      <span>by {pr.author}</span>
                      <span className="font-mono bg-primary/10 text-primary px-1.5 py-0.5 rounded text-[10px]">{pr.branch}</span>
                      {pr.draft && <span className="bg-muted px-1.5 py-0.5 rounded">draft</span>}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
