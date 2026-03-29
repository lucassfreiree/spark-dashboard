import { DashboardState } from '@/types/dashboard'


    converted.deployHistory = converted.deployHis

  if (converted.deployHistory) {
    converted.deployHistory = converted.deployHistory.map((deploy: any) => ({
      ...deploy,
      date: new Date(deploy.date).toISOString(),
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
    converted.workflows = converted.workflows.map((workflow: any) => ({
      l
  }

      ...stage,
      endTime: stage.endTime ? new Date(stage.endTime).toISOString() : 
  }
  if (converted.lastDeploy?.date) {
  }
  r










    converted.lastDeploy.date = new Date(converted.lastDeploy.date).toISOString()
  }

  return converted
}
