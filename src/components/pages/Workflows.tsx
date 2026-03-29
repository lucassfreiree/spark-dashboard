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
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <GitBranch className="w-5 h-5" />
          GitHub Actions Workflows
        </CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Workflow</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Branch</TableHead>
              <TableHead>Last Run</TableHead>
              <TableHead>Duration</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(data.workflows || []).map((workflow) => (
              <TableRow key={workflow.id}>
                <TableCell className="font-semibold">{workflow.name}</TableCell>
                <TableCell>
                  <StatusBadge status={workflow.status} />
                </TableCell>
                <TableCell className="font-mono text-sm">{workflow.branch}</TableCell>
                <TableCell className="text-sm">
                  {formatDistanceToNowSaoPaulo(workflow.lastRun, { addSuffix: true })}
                </TableCell>
                <TableCell className="font-mono text-sm">{workflow.duration}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
