import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface Props {
  data: DashboardState
}

export function DeployHistory({ data }: Props) {
  const history = data.deployHistory || []
  const corpCtrl = data.corporateReal?.controller
  const corpAgent = data.corporateReal?.agent

  return (
    <div className="space-y-6">
      {/* Corporate Commits (real activity from repos) */}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader><CardTitle>Controller Recent Commits</CardTitle></CardHeader>
          <CardContent>
            {(corpCtrl?.recentCommits || []).length === 0 ? (
              <div className="text-sm text-muted-foreground text-center py-4">No commit data (BBVINET_TOKEN may be unavailable)</div>
            ) : (
              <div className="space-y-1">
                {(corpCtrl?.recentCommits || []).map((cm, i) => (
                  <div key={i} className="flex items-start gap-2 p-2 rounded bg-muted/30 text-xs">
                    <code className="text-primary min-w-[60px]">{cm.sha}</code>
                    <div className="flex-1 truncate" title={cm.message}>{cm.message}</div>
                    <span className="text-muted-foreground whitespace-nowrap">{cm.author}</span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Agent Recent Commits</CardTitle></CardHeader>
          <CardContent>
            {(corpAgent?.recentCommits || []).length === 0 ? (
              <div className="text-sm text-muted-foreground text-center py-4">No commit data</div>
            ) : (
              <div className="space-y-1">
                {(corpAgent?.recentCommits || []).map((cm, i) => (
                  <div key={i} className="flex items-start gap-2 p-2 rounded bg-muted/30 text-xs">
                    <code className="text-primary min-w-[60px]">{cm.sha}</code>
                    <div className="flex-1 truncate" title={cm.message}>{cm.message}</div>
                    <span className="text-muted-foreground whitespace-nowrap">{cm.author}</span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Audit Trail */}
      <Card>
        <CardHeader><CardTitle>Deploy Audit Trail ({history.length})</CardTitle></CardHeader>
        <CardContent>
          {history.length === 0 ? (
            <div className="text-sm text-muted-foreground text-center py-4">No deploy history</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-muted-foreground">
                    <th className="text-left py-2 px-3">#</th>
                    <th className="text-left py-2 px-3">Audit File</th>
                    <th className="text-left py-2 px-3">Workspace</th>
                  </tr>
                </thead>
                <tbody>
                  {history.map((path, i) => {
                    const parts = (path || '').split('/')
                    const ws = parts[2] || '?'
                    const filename = parts[parts.length - 1] || path
                    return (
                      <tr key={i} className="border-b border-border/50 hover:bg-muted/30">
                        <td className="py-2 px-3 text-muted-foreground">{i + 1}</td>
                        <td className="py-2 px-3 font-mono text-xs max-w-[300px] truncate" title={path}>{filename}</td>
                        <td className="py-2 px-3"><span className="px-2 py-0.5 rounded bg-primary/10 text-primary text-xs">{ws}</span></td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
