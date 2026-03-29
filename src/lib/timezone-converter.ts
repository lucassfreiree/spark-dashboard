import { DashboardState } from '@/types/dashboard'

export function convertApiDataToSaoPauloTimezone(data: any): DashboardState {
  const converted = { ...data }

  if (converted.lastUpdated) {
    converted.lastUpdated = new Date(converted.lastUpdated).toISOString()
  }

  if (converted.deployHistory) {
    converted.deployHistory = converted.deployHistory.map((deploy: any) => ({
      ...deploy,
      timestamp: new Date(deploy.timestamp).toISOString(),
    }))
  }

  if (converted.agentActivity) {
    converted.agentActivity.timeline = converted.agentActivity.timeline.map((event: any) => ({
      ...event,
      timestamp: new Date(event.timestamp).toISOString(),
    }))

    converted.agentActivity.recentSessions = converted.agentActivity.recentSessions.map((session: any) => ({
      ...session,
      startTime: new Date(session.startTime).toISOString(),
      endTime: session.endTime ? new Date(session.endTime).toISOString() : undefined,
    }))
  }

  if (converted.workflows) {
    converted.workflows = converted.workflows.map((workflow: any) => ({
      ...workflow,
      lastRun: new Date(workflow.lastRun).toISOString(),
    }))
  }

  return converted
}








