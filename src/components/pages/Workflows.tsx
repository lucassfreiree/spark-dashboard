import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { GitBranch } from '@phosphor-icons/react'

interface Props {
  data: DashboardState
}

export function Workflows({ data }: Props) {
  const workflows = data.recentWorkflows || []

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <GitBranch className="w-5 h-5" />
          GitHub Actions Workflows ({workflows.length})
        </CardTitle>
      </CardHeader>
      <CardContent>
        {workflows.length === 0 ? (
          <div className="text-sm text-muted-foreground text-center py-4">No workflow data</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-muted-foreground">
                  <th className="text-left py-2 px-3">Workflow</th>
                  <th className="text-left py-2 px-3">Status</th>
                  <th className="text-left py-2 px-3">Branch</th>
                  <th className="text-left py-2 px-3">Event</th>
                  <th className="text-left py-2 px-3">Run #</th>
                </tr>
              </thead>
              <tbody>
                {workflows.map((wf, i) => (
                  <tr key={i} className="border-b border-border/50 hover:bg-muted/30">
                    <td className="py-2 px-3 font-semibold max-w-[300px] truncate" title={wf.name}>{wf.name}</td>
                    <td className="py-2 px-3">
                      <StatusBadge status={wf.conclusion || wf.status} />
                    </td>
                    <td className="py-2 px-3 font-mono text-xs">{wf.head_branch || '-'}</td>
                    <td className="py-2 px-3 text-xs text-muted-foreground">{wf.event || '-'}</td>
                    <td className="py-2 px-3 font-mono text-xs">#{wf.run_number || '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
